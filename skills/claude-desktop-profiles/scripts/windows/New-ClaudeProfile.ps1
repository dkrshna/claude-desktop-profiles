<#
.SYNOPSIS
    Cria, lista, repara ou remove instancias isoladas do Claude Desktop (Windows).

.DESCRIPTION
    Cada instancia tem pasta propria em <ProfilesRoot>\<Slug>, usada como
    --user-data-dir do Claude Desktop (login, conversas, sessoes, MCP) e, em
    <Slug>\.claude, como CLAUDE_CONFIG_DIR do Claude Code embutido (memoria,
    historico, credenciais, plugins, settings). As instancias rodam em paralelo.

    Todas compartilham um unico launcher (launch-claude-profile.ps1/.vbs) na raiz,
    que e reescrito a cada execucao deste script; assim correcoes no launcher
    chegam a todos os perfis.

.EXAMPLE
    .\New-ClaudeProfile.ps1 -Name "Cliente Acme"
.EXAMPLE
    .\New-ClaudeProfile.ps1 -Name "Pessoal" -Slug Pessoal -StartMenuShortcut -Launch
.EXAMPLE
    .\New-ClaudeProfile.ps1 -List
.EXAMPLE
    .\New-ClaudeProfile.ps1 -Remove -Slug ClienteAcme
#>
[CmdletBinding()]
param(
    # Nome exibido no atalho: "Claude - <Name>". Aceita acentos e espacos.
    [string]$Name,
    # Nome da pasta do perfil. Padrao: derivado de -Name (sem acentos/espacos).
    [string]$Slug,
    # Pasta que guarda todos os perfis. Nao use pasta sincronizada (OneDrive etc.).
    [string]$ProfilesRoot = (Join-Path $env:USERPROFILE 'ClaudeProfiles'),
    # .ico proprio para diferenciar a instancia visualmente.
    [string]$IconPath,
    # Pasta .claude de outra instancia para copiar settings.json e CLAUDE.md.
    # Nunca copia credenciais, historico ou memoria.
    [string]$CopySettingsFrom,
    [switch]$NoDesktopShortcut,
    # Pasta do atalho principal. Padrao: Area de Trabalho (respeita redirecionamento do OneDrive).
    [string]$ShortcutDir = [Environment]::GetFolderPath('Desktop'),
    [switch]$StartMenuShortcut,
    [switch]$Launch,
    # Recria launcher e atalhos de um perfil que ja existe (nao toca nos dados).
    [switch]$Repair,
    [switch]$List,
    # Envia a pasta do perfil para a Lixeira e apaga os atalhos dele.
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$launcherPs1 = 'launch-claude-profile.ps1'
$launcherVbs = 'launch-claude-profile.vbs'
$markerFile  = '.claude-profile.json'

function Write-Utf8Bom([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $true))
}

function ConvertTo-Slug([string]$s) {
    $decomposed = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $decomposed.ToCharArray()) {
        $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -eq [Globalization.UnicodeCategory]::NonSpacingMark) { continue }
        if ($ch -match '[A-Za-z0-9]') { [void]$sb.Append($ch) } else { [void]$sb.Append(' ') }
    }
    $words = $sb.ToString().Split([char[]]' ', [StringSplitOptions]::RemoveEmptyEntries)
    $out = ($words | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ''
    if ($out.Length -gt 40) { $out = $out.Substring(0, 40) }
    return $out
}

function Test-Slug([string]$s) { return $s -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' }

function Get-SafeFileName([string]$s) {
    foreach ($c in [IO.Path]::GetInvalidFileNameChars()) { $s = $s.Replace([string]$c, '') }
    return $s.Trim().TrimEnd('.')
}

function Get-ProfileProcesses([string]$dir) {
    # Processos principais do Claude abertos com este --user-data-dir.
    $pattern = '--user-data-dir="?' + [regex]::Escape($dir.TrimEnd('\')) + '\\?"?(\s|$)'
    Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine -match $pattern }
}

function Get-ShortcutDirs {
    @($ShortcutDir, [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs')) |
        Select-Object -Unique |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) }
}

function Get-ProfileShortcuts([string]$slug) {
    # Atalhos criados por este script: wscript.exe "<ProfilesRoot>\launch-claude-profile.vbs" <slug>
    $vbs = Join-Path $ProfilesRoot $launcherVbs
    $sh = New-Object -ComObject WScript.Shell
    foreach ($d in Get-ShortcutDirs) {
        Get-ChildItem -LiteralPath $d -Filter '*.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
            $l = $sh.CreateShortcut($_.FullName)
            if ($l.TargetPath -notmatch 'wscript\.exe$') { return }
            if ($l.Arguments -match '^\s*"(?<vbs>[^"]+)"\s+"?(?<slug>[^"\s]+)"?\s*$') {
                if ($Matches.vbs -eq $vbs -and $Matches.slug -eq $slug) { $_.FullName }
            } elseif ($l.Arguments -match '^\s*"(?<vbs>[^"]+\.vbs)"\s*$' -and (Test-Path -LiteralPath $Matches.vbs)) {
                # Atalho antigo, com .vbs/.ps1 proprios do perfil (feitos a mao):
                # e do perfil se o .vbs, ou o .ps1 que ele chama, cita a pasta dele.
                $text = Get-Content -LiteralPath $Matches.vbs -Raw
                $ps1 = [regex]::Match($text, '[A-Za-z]:\\[^"]+\.ps1').Value
                if ($ps1 -and (Test-Path -LiteralPath $ps1)) { $text += Get-Content -LiteralPath $ps1 -Raw }
                $dir = [regex]::Escape((Join-Path $ProfilesRoot $slug))
                if ($text -match ($dir + '(["''\\]|\s|$)')) { $_.FullName }
            }
        }
    }
}

function Find-ClaudeExe {
    $pkg = Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if ($pkg) {
        $p = Join-Path $pkg.InstallLocation 'app\Claude.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $sq = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (Test-Path -LiteralPath $sq) {
        $p = Get-ChildItem -LiteralPath $sq -Filter 'claude.exe' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($p) { return $p.FullName }
    }
    return $null
}

function Install-SharedLauncher {
    $src = $PSScriptRoot
    foreach ($f in @($launcherPs1, $launcherVbs)) {
        $from = Join-Path $src $f
        if (-not (Test-Path -LiteralPath $from)) { throw "Arquivo do launcher ausente: $from" }
        Copy-Item -LiteralPath $from -Destination (Join-Path $ProfilesRoot $f) -Force
    }
    $ico = Join-Path $ProfilesRoot 'claude.ico'
    if (-not (Test-Path -LiteralPath $ico)) {
        # Copia o icone para fora da pasta do app: o caminho do app muda a cada
        # atualizacao e o atalho ficaria com icone quebrado.
        $exe = Find-ClaudeExe
        if ($exe) {
            try {
                Add-Type -AssemblyName System.Drawing
                $icon = [Drawing.Icon]::ExtractAssociatedIcon($exe)
                $fs = [IO.File]::Create($ico)
                try { $icon.Save($fs) } finally { $fs.Dispose() }
            } catch { Write-Warning "Nao consegui extrair o icone do Claude: $($_.Exception.Message)" }
        }
    }
}

function New-ProfileShortcut([string]$dir, [string]$displayName, [string]$slug, [string]$icon) {
    $file = Join-Path $dir ((Get-SafeFileName "Claude - $displayName") + '.lnk')
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($file)
    $l.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $l.Arguments = ('"{0}" {1}' -f (Join-Path $ProfilesRoot $launcherVbs), $slug)
    $l.WorkingDirectory = $ProfilesRoot
    if ($icon -and (Test-Path -LiteralPath $icon)) { $l.IconLocation = "$icon,0" }
    $l.Description = "Claude Desktop - perfil isolado ($displayName)"
    $l.Save()
    return $file
}

function Read-Marker([string]$dir) {
    $m = Join-Path $dir $markerFile
    if (Test-Path -LiteralPath $m) {
        try { return Get-Content -LiteralPath $m -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    return $null
}

# ---------------------------------------------------------------- validacoes

$ProfilesRoot = [IO.Path]::GetFullPath($ProfilesRoot).TrimEnd('\')
$modes = @($List, $Remove, $Repair) | Where-Object { $_ }
if (@($modes).Count -gt 1) { throw 'Use apenas um entre -List, -Repair e -Remove.' }

foreach ($cloud in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial, (Join-Path $env:USERPROFILE 'Dropbox'), (Join-Path $env:USERPROFILE 'Google Drive'))) {
    if ($cloud -and $ProfilesRoot.ToLowerInvariant().StartsWith($cloud.TrimEnd('\').ToLowerInvariant() + '\')) {
        throw "ProfilesRoot esta dentro de uma pasta sincronizada ($cloud). Bancos LevelDB/SQLite do perfil corrompem com sincronizacao. Use, por exemplo, $env:USERPROFILE\ClaudeProfiles."
    }
}

# ---------------------------------------------------------------- -List

if ($List) {
    # A instancia principal (icone normal do Claude) nao fica em ProfilesRoot:
    # usa %APPDATA%\Claude e %USERPROFILE%\.claude. Aparece primeiro na lista.
    $mainDir = Join-Path $env:APPDATA 'Claude'
    $mainOpen = [bool](Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '--type=' -and $_.CommandLine -notmatch '--user-data-dir' })
    $rows = @()
    if (Test-Path -LiteralPath $mainDir) {
        $rows += [pscustomobject]@{ Slug = '(principal)'; Nome = "Instancia padrao - $mainDir"; Aberto = $mainOpen; JaUsado = $true; Atalhos = 'icone normal do Claude' }
    }
    if (Test-Path -LiteralPath $ProfilesRoot) { $rows += @(Get-ChildItem -LiteralPath $ProfilesRoot -Directory | ForEach-Object {
        $isProfile = (Test-Path -LiteralPath (Join-Path $_.FullName $markerFile)) -or
                     (Test-Path -LiteralPath (Join-Path $_.FullName 'Local State')) -or
                     (Test-Path -LiteralPath (Join-Path $_.FullName '.claude'))
        if ($isProfile) {
            $m = Read-Marker $_.FullName
            [pscustomobject]@{
                Slug      = $_.Name
                Nome      = if ($m) { $m.name } else { '(perfil criado sem este script)' }
                Aberto    = [bool](Get-ProfileProcesses $_.FullName)
                JaUsado   = Test-Path -LiteralPath (Join-Path $_.FullName 'Local State')
                Atalhos   = (@(Get-ProfileShortcuts $_.Name) | ForEach-Object { Split-Path $_ -Leaf }) -join '; '
            }
        }
    }) }
    if ($rows.Count -le 1) { Write-Host "Nenhum perfil isolado em $ProfilesRoot" }
    $rows | Format-Table -AutoSize -Wrap
    return
}

# ---------------------------------------------------------------- slug

if (-not $Slug) {
    if (-not $Name) { throw 'Informe -Name (e opcionalmente -Slug).' }
    $Slug = ConvertTo-Slug $Name
}
if (-not (Test-Slug $Slug)) { throw "Slug invalido: '$Slug'. Use letras, numeros, ponto, hifen ou underline (comecando por letra/numero)." }
$profileDir = Join-Path $ProfilesRoot $Slug

# ---------------------------------------------------------------- -Remove

if ($Remove) {
    if (-not (Test-Path -LiteralPath $profileDir)) { throw "Perfil nao encontrado: $profileDir" }
    if (Get-ProfileProcesses $profileDir) { throw "O perfil '$Slug' esta aberto. Feche o Claude dessa instancia (inclusive na bandeja) e tente de novo." }
    foreach ($s in @(Get-ProfileShortcuts $Slug)) { Remove-Item -LiteralPath $s -Force; Write-Host "Atalho removido: $s" }
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($profileDir,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
    Write-Host "Perfil '$Slug' enviado para a Lixeira ($profileDir)."
    return
}

# ---------------------------------------------------------------- criar / reparar

if (-not (Find-ClaudeExe)) { throw 'Claude Desktop nao encontrado. Instale-o antes: https://claude.ai/download' }

$exists = Test-Path -LiteralPath $profileDir
if ($exists -and -not $Repair) {
    throw "Ja existe um perfil em $profileDir. Use outro -Slug, ou -Repair para recriar launcher e atalhos dele."
}
if (-not $exists -and $Repair) { throw "Perfil nao encontrado para reparar: $profileDir" }

$marker = Read-Marker $profileDir
if (-not $Name) { $Name = if ($marker) { $marker.name } else { $Slug } }

New-Item -ItemType Directory -Path $ProfilesRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $profileDir '.claude') -Force | Out-Null
Install-SharedLauncher

$created = if ($marker -and $marker.created) { $marker.created } else { (Get-Date).ToString('s') }
Write-Utf8Bom (Join-Path $profileDir $markerFile) (@{ name = $Name; slug = $Slug; created = $created; platform = 'windows' } | ConvertTo-Json)

if ($CopySettingsFrom) {
    $srcDir = [IO.Path]::GetFullPath($CopySettingsFrom)
    foreach ($f in @('settings.json', 'CLAUDE.md')) {
        $from = Join-Path $srcDir $f
        $to = Join-Path $profileDir ".claude\$f"
        if ((Test-Path -LiteralPath $from) -and -not (Test-Path -LiteralPath $to)) {
            Copy-Item -LiteralPath $from -Destination $to
            Write-Host "Copiado: $f"
        }
    }
}

$icon = if ($IconPath) { [IO.Path]::GetFullPath($IconPath) } else { Join-Path $ProfilesRoot 'claude.ico' }
$shortcuts = @()
if (-not $NoDesktopShortcut) { $shortcuts += New-ProfileShortcut $ShortcutDir $Name $Slug $icon }
if ($StartMenuShortcut)      { $shortcuts += New-ProfileShortcut ([Environment]::GetFolderPath('Programs')) $Name $Slug $icon }

Write-Host ''
Write-Host "Perfil:        $profileDir"
Write-Host "Claude Code:   $profileDir\.claude  (CLAUDE_CONFIG_DIR)"
foreach ($s in $shortcuts) { Write-Host "Atalho:        $s" }
Write-Host ("Abrir manual:  wscript.exe ""{0}"" {1}" -f (Join-Path $ProfilesRoot $launcherVbs), $Slug)

if ($Launch) {
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') `
        -ArgumentList ('"{0}" {1}' -f (Join-Path $ProfilesRoot $launcherVbs), $Slug)
    Write-Host 'Instancia aberta. Faca login com a conta desejada.'
}
