# Abre o Claude Desktop num perfil isolado.
#
# Uso:  launch-claude-profile.ps1 -Slug <PastaDoPerfil>
#
# Fica na raiz dos perfis (ex.: %USERPROFILE%\ClaudeProfiles) e e compartilhado
# por todos eles: o perfil e a subpasta <Slug> ao lado deste arquivo. Nenhum
# caminho fica gravado aqui, entao mover a pasta raiz nao quebra nada.
#
# Normalmente e chamado pelo launch-claude-profile.vbs (sem janela de console).

param([Parameter(Mandatory = $true)][string]$Slug)

$ErrorActionPreference = 'Stop'
$title = 'Claude - perfil isolado'
$noUi  = [bool]$env:CLAUDEPROFILES_NO_UI   # usado nos testes automatizados

function Fail([string]$msg) {
    if (-not $noUi) {
        try { (New-Object -ComObject WScript.Shell).Popup($msg, 0, $title, 16) | Out-Null } catch { }
    }
    [Console]::Error.WriteLine($msg)
    exit 1
}

if ($Slug -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    Fail "Nome de perfil invalido: '$Slug'. Use so letras, numeros, ponto, hifen e underline."
}

$profileDir = Join-Path $PSScriptRoot $Slug
$ccHome     = Join-Path $profileDir '.claude'

# Nao cria perfil novo aqui: um erro de digitacao no atalho viraria um perfil
# vazio silencioso. Perfis sao criados pelo New-ClaudeProfile.ps1.
if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
    Fail "Perfil nao encontrado: $profileDir`nCrie-o com New-ClaudeProfile.ps1."
}
if (-not (Test-Path -LiteralPath $ccHome)) {
    New-Item -ItemType Directory -Path $ccHome -Force | Out-Null
}

function Find-ClaudeExe {
    # 1) Instalacao MSIX (Microsoft Store / instalador atual). O caminho muda a
    #    cada atualizacao, por isso e resolvido na hora.
    $pkg = Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if ($pkg) {
        $p = Join-Path $pkg.InstallLocation 'app\Claude.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    # 2) Instalador antigo (Squirrel) em %LOCALAPPDATA%\AnthropicClaude\app-x.y.z
    $sq = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (Test-Path -LiteralPath $sq) {
        $apps = Get-ChildItem -LiteralPath $sq -Directory -Filter 'app-*' | ForEach-Object {
            $v = $null
            if ([version]::TryParse(($_.Name -replace '^app-', ''), [ref]$v)) {
                [pscustomobject]@{ Dir = $_.FullName; Version = $v }
            }
        } | Sort-Object Version -Descending
        foreach ($a in $apps) {
            $p = Join-Path $a.Dir 'claude.exe'
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return $null
}

$exe = Find-ClaudeExe
if (-not $exe) { Fail 'Claude Desktop nao encontrado. Instale-o em https://claude.ai/download' }

# Limpa variaveis herdadas. Se o atalho for disparado de dentro de uma sessao do
# Claude Code (ou de um terminal com ANTHROPIC_API_KEY etc.), essas variaveis
# vazariam para o novo perfil e misturariam conta, sessao e endpoint.
# Variaveis que um perfil precisar de fato vao no "env" do settings.json dele.
Get-ChildItem Env: | Where-Object { $_.Name -match '^(CLAUDE|ANTHROPIC)' } |
    ForEach-Object { Remove-Item -LiteralPath ("Env:" + $_.Name) }

# Isola o Claude Code embutido. Sem isto ele usa %USERPROFILE%\.claude e
# %USERPROFILE%\.claude.json, compartilhados com a instancia principal
# (memoria, historico, credenciais, plugins, settings).
$env:CLAUDE_CONFIG_DIR = $ccHome

# --user-data-dir isola o app Electron inteiro (login, cookies, conversas,
# sessoes do Code, config de MCP/extensoes) e tambem o lock de instancia unica,
# o que permite rodar em paralelo com as outras instancias.
Start-Process -FilePath $exe `
    -ArgumentList ('--user-data-dir="{0}"' -f $profileDir) `
    -WorkingDirectory $env:USERPROFILE
