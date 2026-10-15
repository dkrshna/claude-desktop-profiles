---
name: claude-desktop-profiles
description: Cria, lista, repara ou remove instâncias isoladas do Claude Desktop (Windows e macOS), cada uma com conta, conversas, sessões do Claude Code, memória, histórico, plugins e settings próprios, rodando em paralelo com as outras. Use quando o usuário pedir uma "nova instância", "segunda conta", "perfil separado/isolado", "outro Claude Desktop em paralelo", "Claude para o cliente X", ou quiser listar, consertar ou apagar essas instâncias.
---

# Instâncias isoladas do Claude Desktop

Cada instância é uma pasta `<raiz>/<Slug>` usada de dois jeitos:

- `--user-data-dir` do Claude Desktop (Electron): login, cookies, conversas, sessões do Code, config de MCP/extensões e o lock de instância única. É isso que permite rodar em paralelo.
- `<Slug>/.claude` como `CLAUDE_CONFIG_DIR` do Claude Code embutido: memória, histórico de projetos, credenciais, plugins, `settings.json`, `CLAUDE.md` do usuário.

Um launcher compartilhado, na raiz, abre a instância. Ele resolve o caminho do app na hora (sobrevive a atualizações), limpa as variáveis `CLAUDE*`/`ANTHROPIC*` herdadas (para não vazar conta ou sessão de quem disparou) e só abre perfis que já existem.

Os scripts ficam em `scripts/` ao lado deste arquivo. Use o caminho absoluto a partir do diretório base da skill.

## Fluxo

1. **Plataforma.** Windows → `scripts/windows/New-ClaudeProfile.ps1` (PowerShell 5.1+). macOS → `scripts/macos/new-claude-profile.sh` (bash 3.2+). Linux não tem Claude Desktop oficial: diga isso e pare.
2. **Nome.** Se o usuário não deu um nome, pergunte. É o que aparece no atalho/app (`Claude - <Nome>`) e aceita acentos. O slug (nome da pasta) é derivado sem acentos e espaços, por exemplo "Cérebro Comércio" vira `CerebroComercio`. Passe `-Slug`/`--slug` só se o usuário pedir um específico.
3. **Antes de criar,** liste (`-List`/`--list`) para ver o que já existe e evitar duplicata. Perfis antigos criados à mão aparecem como "(perfil criado sem este script)".
4. **Criar.**
   - Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/windows/New-ClaudeProfile.ps1" -Name "<Nome>"`
     Opcionais: `-StartMenuShortcut`, `-NoDesktopShortcut`, `-IconPath <.ico>`, `-CopySettingsFrom <pasta .claude>`, `-Launch`, `-ProfilesRoot <dir>`.
   - macOS: `bash "<skill>/scripts/macos/new-claude-profile.sh" --name "<Nome>"`
     Opcionais: `--copy-settings-from <pasta .claude>`, `--launch`, `--no-app`, `--root <dir>`, `--apps-dir <dir>`.
   - A raiz padrão é `~/ClaudeProfiles` (`%USERPROFILE%\ClaudeProfiles`). O script recusa pastas sincronizadas (OneDrive, iCloud, Dropbox, Google Drive), porque a sincronização corrompe os bancos do perfil. Não contorne isso.
   - `-CopySettingsFrom` copia só `settings.json` e `CLAUDE.md`. Nunca copie `.credentials.json`, `.claude.json`, `projects/` ou memórias entre perfis: isso desfaz o isolamento.
5. **Abrir.** O launcher já limpa o ambiente, então usar `-Launch`/`--launch` de dentro desta sessão é seguro. Abra só se o usuário quiser abrir agora. Caso contrário, diga onde está o atalho.
6. **Relate** a pasta do perfil, o atalho/app criado, que o login é feito na primeira abertura e as limitações relevantes de [reference/isolamento.md](reference/isolamento.md). Avise sempre sobre o login por link (deep link) e sobre "abrir ao iniciar o sistema".

## Outras operações

- **Listar:** `-List` / `--list` mostra slug, nome, se está aberto e quais atalhos/apps apontam para ele.
- **Reparar ou migrar:** `-Repair -Slug <Slug>` / `--repair --slug <Slug>` recria launcher e atalho sem tocar nos dados. Serve para perfis antigos com launcher próprio. Depois, o atalho antigo pode ser apagado; confira com o usuário qual é.
- **Remover:** é destrutivo. **Confirme com o usuário** nome e pasta antes. O script se recusa a remover perfil aberto e manda a pasta para a Lixeira (recuperável), junto com os atalhos dele. Lembre que a conta continua existindo no claude.ai; só os dados locais saem.

## Erros comuns

- "Claude Desktop não encontrado": instale em https://claude.ai/download. No Windows o script aceita MSIX e o instalador antigo (Squirrel).
- Atalho não abre nada: rode o launcher direto no terminal para ver a mensagem, por exemplo `powershell -File "<raiz>\launch-claude-profile.ps1" -Slug <Slug>` ou `"<raiz>/launch-claude-profile.sh" <Slug>`.
- Instância "já aberta" não aparece: ela pode estar só na bandeja ou no Dock. Abrir de novo só traz a janela para frente, porque o lock é por perfil.
