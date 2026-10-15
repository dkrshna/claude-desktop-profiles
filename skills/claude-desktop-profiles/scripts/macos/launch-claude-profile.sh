#!/bin/bash
# Abre o Claude Desktop num perfil isolado (macOS).
#
# Uso:  launch-claude-profile.sh <PastaDoPerfil>
#
# Fica na raiz dos perfis (ex.: ~/ClaudeProfiles) e e compartilhado por todos:
# o perfil e a subpasta <PastaDoPerfil> ao lado deste arquivo. Normalmente e
# chamado pelo app "Claude - <Nome>.app" criado pelo new-claude-profile.sh.
#
# Compativel com o bash 3.2 que vem no macOS.

set -u

title="Claude - perfil isolado"

# Opcoes de teste/override. Lidas antes da limpeza de variaveis abaixo.
no_ui="${CLAUDEPROFILES_NO_UI:-}"
app_override="${CLAUDEPROFILES_APP:-}"
force_spawn="${CLAUDEPROFILES_FORCE_SPAWN:-}"

fail() {
  echo "$1" >&2
  if [ -z "$no_ui" ] && command -v osascript >/dev/null 2>&1; then
    osascript - "$title" "$1" >/dev/null 2>&1 <<'OSA'
on run argv
  display alert (item 1 of argv) message (item 2 of argv) as critical
end run
OSA
  fi
  exit 1
}

slug="${1:-}"
case "$slug" in
  ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*)
    fail "Nome de perfil invalido: '$slug'. Use so letras, numeros, ponto, hifen e underline." ;;
esac
[ "${#slug}" -le 64 ] || fail "Nome de perfil longo demais: '$slug'."

root="$(cd "$(dirname "$0")" && pwd -P)"
profile="$root/$slug"

# Nao cria perfil novo aqui: um erro de digitacao viraria um perfil vazio
# silencioso. Perfis sao criados pelo new-claude-profile.sh.
[ -d "$profile" ] || fail "Perfil nao encontrado: $profile
Crie-o com new-claude-profile.sh."
mkdir -p "$profile/.claude" || fail "Nao consegui criar $profile/.claude"

plist_get() { # <Info.plist> <chave>
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

find_app() {
  local c
  for c in "$app_override" "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
    if [ -n "$c" ] && [ -d "$c" ]; then printf '%s\n' "$c"; return 0; fi
  done
  if command -v mdfind >/dev/null 2>&1; then
    c="$(mdfind 'kMDItemCFBundleIdentifier == "com.anthropic.claudefordesktop"' 2>/dev/null | head -n 1)"
    if [ -n "$c" ] && [ -d "$c" ]; then printf '%s\n' "$c"; return 0; fi
  fi
  return 1
}

app="$(find_app)" || fail "Claude.app nao encontrado. Instale o Claude Desktop: https://claude.ai/download"
exe_name="$(plist_get "$app/Contents/Info.plist" CFBundleExecutable)"
[ -n "$exe_name" ] || exe_name="Claude"
bin="$app/Contents/MacOS/$exe_name"

# Limpa variaveis herdadas. Se o app for aberto de um terminal ou de dentro de
# uma sessao do Claude Code, CLAUDE_*/ANTHROPIC_* vazariam para o novo perfil e
# misturariam conta, sessao e endpoint. Variaveis que um perfil precisar de
# fato vao no "env" do settings.json dele.
for v in $(compgen -e); do
  case "$v" in CLAUDE*|ANTHROPIC*) unset "$v" ;; esac
done

# Isola o Claude Code embutido (memoria, historico, credenciais, plugins).
export CLAUDE_CONFIG_DIR="$profile/.claude"

# Preferencia: abrir pelo LaunchServices (open -n). Assim o macOS atribui as
# permissoes de privacidade (Acessibilidade, Gravacao de Tela etc.) ao proprio
# Claude.app assinado, e nao a este script. "open --env" passa a variavel.
if [ -z "$force_spawn" ] && command -v open >/dev/null 2>&1 &&
   open --help 2>&1 | grep -q -- '--env'; then
  exec open -n -a "$app" --env "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR" \
    --args --user-data-dir="$profile"
fi

# Alternativa (macOS sem "open --env"): executa o binario direto, ja com o
# ambiente limpo, desacoplado deste script.
[ -x "$bin" ] || fail "Executavel do Claude nao encontrado: $bin"
nohup "$bin" --user-data-dir="$profile" >/dev/null 2>&1 &
exit 0
