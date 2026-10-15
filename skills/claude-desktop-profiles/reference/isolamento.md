# O que fica isolado e o que não fica

## Isolado por instância

| Item | Onde fica |
|---|---|
| Login do Claude Desktop, cookies, sessão claude.ai | `<perfil>/` (`--user-data-dir`) |
| Conversas, Projetos, preferências do app, janelas | `<perfil>/` |
| Sessões do Claude Code no app (aba Code), worktrees, checkpoints | `<perfil>/claude-code-sessions`, `git-shadow`, ... |
| Config de MCP do Desktop (`claude_desktop_config.json`) e extensões | `<perfil>/` |
| Versão do Claude Code embutido | `<perfil>/claude-code/` |
| Memória, histórico de projetos e transcrições do Claude Code | `<perfil>/.claude/projects/` (`CLAUDE_CONFIG_DIR`) |
| `settings.json`, `CLAUDE.md` do usuário, plugins, skills do usuário | `<perfil>/.claude/` |
| Credenciais do Claude Code (Windows/Linux) | `<perfil>/.claude/.credentials.json` |
| Lock de instância única (é o que permite rodar em paralelo) | por `--user-data-dir` |
| Variáveis `CLAUDE*` / `ANTHROPIC*` | limpas pelo launcher; defina as do perfil no `env` do `settings.json` dele |

## Compartilhado: é do sistema operacional, não do Claude

- Pastas de projeto e o que está nelas: `.claude/` do projeto, `CLAUDE.md` do repositório, `.mcp.json`. Dois perfis abrindo o mesmo repositório veem a mesma config de projeto.
- Git (`user.name`/`user.email`, credential manager), chaves SSH, `gh auth`, tokens de npm, pip, Docker e afins.
- Arquivos que o Claude lê e escreve no disco.
- No macOS, o item "Claude Safe Storage" do Keychain (chave de criptografia do Electron). Os dados criptografados continuam separados por perfil.

Se uma instância é de cliente e precisa de outra identidade no Git ou no GitHub, configure isso por repositório (`git config user.email` local, `includeIf` no `~/.gitconfig`). O perfil do Claude não cuida disso.

## Limitações conhecidas

### Links `claude://` (login pelo navegador, "abrir no app")
O protocolo `claude://` é registrado uma vez só no sistema e aponta para o app sem `--user-data-dir`, ou seja, para a instância **principal**. Se o login de uma instância isolada terminar no navegador e voltar ao app por link, ele pode cair na instância principal.
- Prefira formas de login que terminam dentro da própria janela do app.
- **macOS:** feche as outras instâncias do Claude (Cmd+Q) durante o primeiro login. Com só a instância isolada aberta, o link vai para ela.
- **Windows:** se o login cair na principal, faça logout lá, feche-a e tente o login de novo na isolada com a principal fechada. Se o app redirecionar sozinho, use a opção de login por código/e-mail.

### Extensão Claude in Chrome
O "native messaging host" do Chrome é registrado por usuário do sistema e aponta para uma só instância, em geral a principal ou a última que se registrou. Só ela conversa com a extensão.

### "Abrir ao iniciar o sistema"
Ligar essa opção **dentro** de uma instância isolada registra o app sem `--user-data-dir`, e no próximo boot abre a instância principal. Para abrir a isolada no boot:
- Windows: copie o atalho dela para `shell:startup` (Win+R → `shell:startup`).
- macOS: Ajustes do Sistema → Geral → Itens de Início → adicione `~/Applications/Claude - <Nome>.app`.

### Atalho global (Quick Entry) e ícone na barra/Dock
- O atalho global de teclado fica com a primeira instância que o registrar.
- As janelas de todas as instâncias se agrupam no mesmo ícone do Claude na barra de tarefas/Dock. Fixar a **janela aberta** fixa o Claude principal. Fixe o **atalho** da instância (Windows: botão direito no atalho → Fixar em Iniciar; macOS: arraste o `.app` para o Dock).
- Para distinguir as instâncias, use um ícone próprio: `-IconPath` no Windows. No macOS, troque `Contents/Resources/icon.icns` do app gerado.

### Credenciais do Claude Code no macOS (uso pelo terminal)
Dentro do Desktop, o Claude Code usa o login do próprio app. Se você rodar `claude` no terminal com `CLAUDE_CONFIG_DIR` apontando para um perfil, versões recentes guardam a credencial no Keychain com um nome derivado da pasta de config, separado do principal. Em versões antigas o item podia ser o mesmo. Confira no Acesso às Chaves se há um item "Claude Code-credentials" por perfil.

### Usar o Claude Code de terminal com um perfil
```powershell
# Windows (PowerShell)
$env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\ClaudeProfiles\<Slug>\.claude"; claude
```
```bash
# macOS
CLAUDE_CONFIG_DIR="$HOME/ClaudeProfiles/<Slug>/.claude" claude
```

### Pastas sincronizadas
Não ponha a raiz dos perfis no OneDrive, iCloud, Dropbox ou Google Drive. Os bancos LevelDB/SQLite do Electron corrompem com sincronização e travas de arquivo. O script recusa essas pastas.
