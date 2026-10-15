# claude-desktop-profiles

Várias contas do **Claude Desktop** abertas ao mesmo tempo, no mesmo computador, cada uma isolada: login, conversas, sessões do Claude Code, memória, histórico, plugins e settings próprios. Funciona no **Windows** e no **macOS**.

É uma skill do Claude Code (empacotada como plugin) e também um par de scripts que você pode rodar sozinho.

```
~/ClaudeProfiles/
├── launch-claude-profile.ps1 / .vbs / .sh   ← launcher compartilhado
├── Pessoal/                ← --user-data-dir do Claude Desktop
│   └── .claude/            ← CLAUDE_CONFIG_DIR do Claude Code
└── ClienteAcme/
    └── .claude/
```

## Como funciona

- `--user-data-dir=<perfil>` dá ao Claude Desktop (Electron) uma pasta de dados própria e um lock de instância única próprio. É o que permite abrir várias instâncias em paralelo.
- `CLAUDE_CONFIG_DIR=<perfil>/.claude` faz o Claude Code embutido parar de usar o `~/.claude` compartilhado. Sem isso, memória, histórico e credenciais do Code se misturariam entre as contas.
- O launcher acha o Claude na hora (o caminho muda a cada atualização no Windows), **limpa variáveis `CLAUDE*`/`ANTHROPIC*` herdadas** e só abre perfis que existem.
- Windows: atalho na Área de Trabalho (e no Menu Iniciar, opcional) via `wscript`, sem piscar console.
- macOS: um `Claude - <Nome>.app` em `~/Applications`, aberto com `open -n` para que as permissões de privacidade continuem atribuídas ao Claude.app assinado.

O que **não** fica isolado (Git, SSH, links `claude://`, extensão do Chrome, "abrir ao iniciar") está em [isolamento.md](skills/claude-desktop-profiles/reference/isolamento.md). Leia antes de usar com contas de clientes.

## Instalação como skill

No Claude Code:

```
/plugin marketplace add dkrshna/claude-desktop-profiles
/plugin install claude-desktop-profiles@claude-desktop-profiles
```

Depois é só pedir: *"cria uma nova instância isolada do Claude Desktop chamada Cliente Acme"*.

Sem o sistema de plugins, copie `skills/claude-desktop-profiles/` para `~/.claude/skills/`.

## Uso direto pelos scripts

### Windows (PowerShell 5.1+)

```powershell
$s = ".\skills\claude-desktop-profiles\scripts\windows\New-ClaudeProfile.ps1"
powershell -ExecutionPolicy Bypass -File $s -Name "Cliente Acme"            # cria + atalho na Área de Trabalho
powershell -ExecutionPolicy Bypass -File $s -Name "Pessoal" -StartMenuShortcut -Launch
powershell -ExecutionPolicy Bypass -File $s -List
powershell -ExecutionPolicy Bypass -File $s -Repair -Slug ClienteAcme       # recria launcher/atalho
powershell -ExecutionPolicy Bypass -File $s -Remove -Slug ClienteAcme       # vai para a Lixeira
```

Outras opções: `-Slug`, `-ProfilesRoot`, `-IconPath`, `-CopySettingsFrom <pasta .claude>`, `-NoDesktopShortcut`.

### macOS (bash 3.2+)

```bash
s=./skills/claude-desktop-profiles/scripts/macos/new-claude-profile.sh
bash "$s" --name "Cliente Acme"                   # cria ~/Applications/Claude - Cliente Acme.app
bash "$s" --name "Pessoal" --launch
bash "$s" --list
bash "$s" --repair --slug ClienteAcme
bash "$s" --remove --slug ClienteAcme             # vai para a Lixeira
```

Outras opções: `--slug`, `--root`, `--apps-dir`, `--copy-settings-from <pasta .claude>`, `--no-app`.

## Primeiro uso de cada instância

1. Abra pelo atalho ou app da instância, nunca pelo ícone normal do Claude.
2. Faça login com a conta desejada. Se o login voltar do navegador para a instância errada, veja "Links `claude://`" em [isolamento.md](skills/claude-desktop-profiles/reference/isolamento.md).
3. Não ligue "abrir ao iniciar o sistema" dentro de uma instância isolada: isso abre a principal. Use a pasta de inicialização ou os Itens de Início com o atalho/app da instância.

## Migrando perfis feitos à mão

Se você já tinha um perfil em `~/ClaudeProfiles/<Pasta>` com launcher próprio, rode `-Repair -Slug <Pasta>` (ou `--repair --slug <Pasta>`). Isso cria o atalho novo com o launcher compartilhado sem tocar nos dados. Depois apague o atalho antigo.

## Testes

Os dois scripts foram exercitados de ponta a ponta no Windows 11 (MSIX 2.42304): criar, duplicar, reparar, listar, abrir pelo atalho, limpar variáveis, recusar remoção com a instância aberta e remover. A lógica do script macOS (slugs, geração do .app, launcher, limpeza de variáveis, remoção) foi testada em bash com um Claude.app simulado. As partes que dependem do macOS real (`open --env`, `PlistBuddy`, `mdfind`, Finder) ainda não foram verificadas num Mac. Relatos e PRs são bem-vindos.

## Licença

MIT
