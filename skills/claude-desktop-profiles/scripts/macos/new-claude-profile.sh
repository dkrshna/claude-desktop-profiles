#!/bin/bash
# Cria, lista, repara ou remove instancias isoladas do Claude Desktop (macOS).
#
# Cada instancia tem pasta propria em <root>/<slug>, usada como --user-data-dir
# do Claude Desktop (login, conversas, sessoes, MCP) e, em <slug>/.claude, como
# CLAUDE_CONFIG_DIR do Claude Code embutido (memoria, historico, credenciais,
# plugins, settings). Para abrir, gera um app "Claude - <Nome>.app" em
# ~/Applications (aparece no Spotlight, Launchpad e pode ir para o Dock).
#
# Uso:
#   new-claude-profile.sh --name "Cliente Acme" [--slug ClienteAcme] [--launch]
#   new-claude-profile.sh --list
#   new-claude-profile.sh --repair --slug ClienteAcme
#   new-claude-profile.sh --remove --slug ClienteAcme
#
# Opcoes:
#   --name NOME            Nome exibido no app: "Claude - NOME". Aceita acentos.
#   --slug PASTA           Pasta do perfil. Padrao: derivado do nome.
#   --root DIR             Raiz dos perfis. Padrao: ~/ClaudeProfiles
#   --apps-dir DIR         Onde criar o .app. Padrao: ~/Applications
#   --copy-settings-from D Pasta .claude de outra instancia: copia settings.json
#                          e CLAUDE.md (nunca credenciais, historico ou memoria).
#   --no-app               Nao cria o .app (abrir com launch-claude-profile.sh).
#   --launch               Abre a instancia ao final.
#   --repair               Recria launcher e .app de um perfil existente.
#   --list                 Lista os perfis.
#   --remove               Move o perfil e o .app dele para a Lixeira.
#
# Compativel com o bash 3.2 que vem no macOS.

set -eu

here="$(cd "$(dirname "$0")" && pwd -P)"
launcher="launch-claude-profile.sh"
marker=".claude-profile.json"

name="" slug="" root="$HOME/ClaudeProfiles" apps_dir="$HOME/Applications"
copy_from="" no_app="" do_launch="" mode="create"

die() { echo "Erro: $*" >&2; exit 1; }
set_mode() { [ "$mode" = "create" ] || die "use apenas um entre --list, --repair e --remove."; mode="$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="${2:?--name precisa de valor}"; shift 2 ;;
    --slug) slug="${2:?--slug precisa de valor}"; shift 2 ;;
    --root) root="${2:?--root precisa de valor}"; shift 2 ;;
    --apps-dir) apps_dir="${2:?--apps-dir precisa de valor}"; shift 2 ;;
    --copy-settings-from) copy_from="${2:?--copy-settings-from precisa de valor}"; shift 2 ;;
    --no-app) no_app=1; shift ;;
    --launch) do_launch=1; shift ;;
    --repair) set_mode repair; shift ;;
    --list) set_mode list; shift ;;
    --remove) set_mode remove; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) die "opcao desconhecida: $1 (veja --help)" ;;
  esac
done

mkdir -p "$root"
root="$(cd "$root" && pwd -P)"
if [ -d "$apps_dir" ]; then apps_dir="$(cd "$apps_dir" && pwd -P)"; fi

# Pastas sincronizadas corrompem os bancos LevelDB/SQLite do perfil.
case "$root/" in
  "$HOME/Library/Mobile Documents/"*|"$HOME/Library/CloudStorage/"*|"$HOME/Dropbox/"*|"$HOME/Google Drive/"*)
    die "a raiz $root esta numa pasta sincronizada. Use, por exemplo, ~/ClaudeProfiles." ;;
  "$HOME/Desktop/"*|"$HOME/Documents/"*)
    echo "Aviso: $root fica em Mesa/Documentos. Se o iCloud sincroniza essas pastas, mova a raiz para ~/ClaudeProfiles." >&2 ;;
esac

to_slug() {
  # Remove acentos, junta as palavras em TitleCase, limita a 40 caracteres.
  # O iconv do macOS translitera "é" como "'e" (o GNU, como "?e" as vezes):
  # esses sinais sao apagados antes de separar as palavras.
  printf '%s' "$1" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr -d "'\"^\`~?" | tr -c 'A-Za-z0-9' ' ' |
    awk '{ for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2) }' | cut -c1-40
}

valid_slug() {
  case "$1" in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  [ "${#1}" -le 64 ]
}

sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }  # aspas simples seguras
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

marker_name() { # <dir do perfil>
  local f="$1/$marker" n=""
  [ -f "$f" ] || return 0
  if command -v plutil >/dev/null 2>&1; then n="$(plutil -extract name raw -o - "$f" 2>/dev/null || true)"; fi
  [ -n "$n" ] || n="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$f" | head -n 1)"
  printf '%s' "$n"
}

profile_running() { # <dir do perfil>
  ps -axo command= 2>/dev/null | grep -F -- "--user-data-dir=$1" | grep -v -- '--type=' | grep -vq grep
}

app_bundles_for() { # <slug>: .app gerados por este script para o perfil
  local a
  for a in "$apps_dir"/*.app; do
    [ -f "$a/Contents/MacOS/launcher" ] || continue
    if grep -qFx -- "CLAUDEPROFILES_ROOT=$(sq "$root")" "$a/Contents/MacOS/launcher" &&
       grep -qFx -- "CLAUDEPROFILES_SLUG=$(sq "$1")" "$a/Contents/MacOS/launcher"; then
      printf '%s\n' "$a"
    fi
  done
}

find_claude_app() {
  local c
  for c in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
    if [ -d "$c" ]; then printf '%s\n' "$c"; return 0; fi
  done
  if command -v mdfind >/dev/null 2>&1; then
    c="$(mdfind 'kMDItemCFBundleIdentifier == "com.anthropic.claudefordesktop"' 2>/dev/null | head -n 1)"
    if [ -n "$c" ] && [ -d "$c" ]; then printf '%s\n' "$c"; return 0; fi
  fi
  return 1
}

move_to_trash() { # <caminho>
  if command -v osascript >/dev/null 2>&1 &&
     osascript -e 'on run argv' -e 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)' -e 'end run' "$1" >/dev/null 2>&1; then
    return 0
  fi
  local b ext=""
  b="$(basename "$1")"
  case "$b" in *.app) ext=".app"; b="${b%.app}" ;; esac
  mkdir -p "$HOME/.Trash"
  mv "$1" "$HOME/.Trash/$b $(date +%Y%m%d%H%M%S)$ext"
}

# ------------------------------------------------------------------ --list
if [ "$mode" = "list" ]; then
  # A instancia principal (icone normal do Claude) nao fica na raiz dos perfis:
  # usa ~/Library/Application Support/Claude e ~/.claude.
  main_dir="$HOME/Library/Application Support/Claude"
  if [ -d "$main_dir" ]; then
    if ps -axo command= 2>/dev/null | grep -E '/Contents/MacOS/Claude( |$)' | grep -v -- '--type=' | grep -vq -- '--user-data-dir'; then
      st="aberto"; else st="fechado"; fi
    printf '%-28s %-34s %-8s %s\n' "(principal)" "Instancia padrao" "$st" "Claude.app normal"
  fi
  found=""
  for d in "$root"/*/; do
    d="${d%/}"
    [ -d "$d" ] || continue
    if [ -f "$d/$marker" ] || [ -d "$d/.claude" ] || [ -f "$d/Local State" ]; then
      found=1
      s="$(basename "$d")"
      n="$(marker_name "$d")"; [ -n "$n" ] || n="(perfil criado sem este script)"
      if profile_running "$d"; then st="aberto"; else st="fechado"; fi
      apps="$(app_bundles_for "$s" | while read -r a; do basename "$a"; done | paste -sd ';' -)"
      printf '%-28s %-34s %-8s %s\n' "$s" "$n" "$st" "$apps"
    fi
  done
  [ -n "$found" ] || echo "Nenhum perfil isolado em $root"
  exit 0
fi

# ------------------------------------------------------------------ slug
if [ -z "$slug" ]; then
  [ -n "$name" ] || die "informe --name (e opcionalmente --slug)."
  slug="$(to_slug "$name")"
fi
valid_slug "$slug" || die "slug invalido: '$slug'. Use letras, numeros, ponto, hifen ou underline."
profile="$root/$slug"

# ------------------------------------------------------------------ --remove
if [ "$mode" = "remove" ]; then
  [ -d "$profile" ] || die "perfil nao encontrado: $profile"
  if profile_running "$profile"; then die "o perfil '$slug' esta aberto. Feche essa instancia do Claude (Cmd+Q) e tente de novo."; fi
  app_bundles_for "$slug" | while read -r a; do move_to_trash "$a" && echo "App removido: $a"; done
  move_to_trash "$profile"
  echo "Perfil '$slug' movido para a Lixeira ($profile)."
  exit 0
fi

# ------------------------------------------------------------------ criar / reparar
claude_app="$(find_claude_app)" || die "Claude.app nao encontrado. Instale o Claude Desktop: https://claude.ai/download"

if [ -d "$profile" ] && [ "$mode" != "repair" ]; then
  die "ja existe um perfil em $profile. Use outro --slug, ou --repair para recriar launcher e app dele."
fi
if [ ! -d "$profile" ] && [ "$mode" = "repair" ]; then die "perfil nao encontrado para reparar: $profile"; fi

[ -n "$name" ] || name="$(marker_name "$profile")"
[ -n "$name" ] || name="$slug"

mkdir -p "$profile/.claude"
cp "$here/$launcher" "$root/$launcher"
chmod +x "$root/$launcher"

created="$(date +%Y-%m-%dT%H:%M:%S)"
if [ -f "$profile/$marker" ]; then
  old="$(sed -n 's/.*"created"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$profile/$marker" | head -n 1)"
  [ -z "$old" ] || created="$old"
fi
printf '{\n  "name": "%s",\n  "slug": "%s",\n  "created": "%s",\n  "platform": "macos"\n}\n' \
  "$(json_escape "$name")" "$slug" "$created" > "$profile/$marker"

if [ -n "$copy_from" ]; then
  for f in settings.json CLAUDE.md; do
    if [ -f "$copy_from/$f" ] && [ ! -e "$profile/.claude/$f" ]; then
      cp "$copy_from/$f" "$profile/.claude/$f" && echo "Copiado: $f"
    fi
  done
fi

app_path=""
if [ -z "$no_app" ]; then
  safe_name="$(printf '%s' "Claude - $name" | tr '/:' '--')"
  mkdir -p "$apps_dir"
  apps_dir="$(cd "$apps_dir" && pwd -P)"
  app_path="$apps_dir/$safe_name.app"
  rm -rf "$app_path"
  mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

  icon_line=""
  icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$claude_app/Contents/Info.plist" 2>/dev/null || true)"
  if [ -n "$icon_file" ]; then
    case "$icon_file" in *.icns) ;; *) icon_file="$icon_file.icns" ;; esac
    if cp "$claude_app/Contents/Resources/$icon_file" "$app_path/Contents/Resources/icon.icns" 2>/dev/null; then
      icon_line="  <key>CFBundleIconFile</key><string>icon</string>"
    fi
  fi

  bundle_id="local.claude-profiles.$(printf '%s' "$slug" | tr 'A-Z_' 'a-z-')"
  cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>$(xml_escape "Claude - $name")</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
$icon_line
</dict>
</plist>
PLIST

  {
    echo '#!/bin/bash'
    echo "# Gerado por new-claude-profile.sh: abre um perfil isolado do Claude."
    echo "CLAUDEPROFILES_ROOT=$(sq "$root")"
    echo "CLAUDEPROFILES_SLUG=$(sq "$slug")"
    echo 'exec /bin/bash "$CLAUDEPROFILES_ROOT/launch-claude-profile.sh" "$CLAUDEPROFILES_SLUG"'
  } > "$app_path/Contents/MacOS/launcher"
  chmod +x "$app_path/Contents/MacOS/launcher"
  touch "$app_path"
  lsreg="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [ -x "$lsreg" ] && "$lsreg" -f "$app_path" >/dev/null 2>&1 || true
fi

echo
echo "Perfil:        $profile"
echo "Claude Code:   $profile/.claude  (CLAUDE_CONFIG_DIR)"
[ -z "$app_path" ] || echo "App:           $app_path"
echo "Abrir manual:  \"$root/$launcher\" $slug"

if [ -n "$do_launch" ]; then
  "$root/$launcher" "$slug"
  echo "Instancia aberta. Faca login com a conta desejada."
fi
