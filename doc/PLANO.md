# Plano do Bando

Orquestrador de agentes de código para macOS, com interface parecida com a do Xirp, consumo de memória pequeno e agentes e providers configuráveis pelo usuário.

"Bando" é nome provisório.

Data do plano: 09/11/2026.

---

## 1. Por que existe

O Xirp resolve o problema certo: rodar vários agentes de código em paralelo, cada um no seu worktree, com uma tela para acompanhar todos. Mas tem dois problemas no uso diário:

1. **Memória.** Medido nesta máquina em 09/11/2026: cerca de **1 GB de RAM** com o app aberto (5 processos Electron, o maior com 340 MB, mais 11 processos `node` de 12 a 47 MB). O app ocupa 623 MB em disco e o CLI sozinho tem 138 MB.
2. **Agentes fechados.** A lista de agentes (Claude Code, Codex, Gemini CLI, Pi, Cursor) está compilada no binário. Não dá para adicionar o Antigravity (`agy`) nem qualquer outra CLI, e não dá para trocar o provider de um agente (por exemplo, rodar o Claude Code apontando para o OpenRouter ou para um modelo local).

## 2. Metas

| Métrica | Meta | Xirp hoje |
|---|---|---|
| RAM do app com 5 sessões abertas | até 80 MB | ~1 GB |
| RAM com o app fechado e agentes rodando | só o tmux (~5 MB) | daemon continua no ar |
| CPU com todos os agentes ociosos | 0% (sem polling) | processos node ativos |
| Tamanho do .app | até 25 MB | 623 MB |
| Abrir o app até a lista aparecer | até 300 ms | segundos |
| Adicionar um agente novo | editar um arquivo ou usar a tela de configurações, sem recompilar | impossível |

Os agentes continuam gastando a memória deles (um Claude Code aberto é um `node` de algumas centenas de MB). A economia é no que roda por cima deles.

## 3. O que ferramentas desse tipo fazem

Levantamento das funcionalidades que o usuário espera, feito a partir do uso de ferramentas parecidas (Xirp, Conductor e outras; ver [pesquisa-ux.md](pesquisa-ux.md)). Nenhum código de terceiros é usado; isto é só referência de funcionalidade.

Pontos de projeto que vieram daí:

- Cada agente precisa de: como iniciar, como retomar uma conversa, onde guarda o histórico e como saber o estado (trabalhando, esperando você, pronto).
- O estado vem de **hooks do agente** quando ele tem, ou da **leitura da saída do terminal** quando não tem.

### 3.1 Funcionalidades, por área

| Área | O que tem |
|---|---|
| Sessões | criar, listar, buscar, parar, apagar, retomar, fork, trocar de agente, mandar mensagem, terminal extra, importar sessão nativa, fila com dependência (`--depends-on`), título automático |
| Worktrees | criar, listar, apagar com trava (mudança não commitada ou push pendente), reciclar, script de setup, limpeza de worktrees antigos |
| Git | status, diff lado a lado, stage, commit, stash, branches, log, push, pull, PR do branch |
| Terminal | tmux por baixo, abrir no terminal nativo, dividir painel |
| Configurações | agente padrão, padrões de lançamento por agente, modelos, hooks, atalhos, comando do editor, prompts salvos, regras do projeto, skills |
| Extras | custo por sessão, busca em todos os transcripts, notificações com modo silencioso, upload de screenshot, URLs detectadas no terminal |
| Não interessa | Portal, telemetria, "Studio", retrospectiva semanal, análise de repositório, navegador embutido, novidades da versão |

## 4. Escolha de tecnologia

| Opção | RAM estimada | Prós | Contras |
|---|---|---|---|
| **SwiftUI + SwiftTerm** (escolhida) | 40 a 80 MB | nativo, terminal nativo, notificações e Keychain do sistema, .app pequeno | só macOS |
| Tauri 2 + xterm.js | 120 a 200 MB | multiplataforma, UI em HTML fácil de copiar o visual | cada WebView é um processo WebKit |
| Electron | 300 MB ou mais | o que o Xirp usa | é exatamente o problema |

**Decisão:** SwiftUI + SwiftTerm, com tmux segurando as sessões. Se um dia precisar de Linux ou Windows, o núcleo (`BandoCore`) fica isolado da interface para facilitar uma porta.

### Dependências

| Pacote | Uso |
|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | emulador de terminal; `LocalProcessTerminalView.startProcess(executable:args:environment:currentDirectory:)` roda `tmux attach` |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite para sessões, projetos e histórico |
| [TOMLKit](https://github.com/LebJe/TOMLKit) | leitura de `agents.toml` e `providers.toml` |
| tmux 3.3+ (externo) | sessões persistentes, `monitor-silence`, `set-hook` |

Versões exatas são fixadas na fase 0, conferindo a documentação atual de cada uma.

## 5. Arquitetura

```
┌──────────────────────── Bando.app (SwiftUI) ────────────────────────┐
│  Barra lateral         │  Terminal da sessão (SwiftTerm)             │
│  projetos / sessões    │  roda: tmux attach -t bando_<id>            │
│  ● estado de cada uma  │                                             │
└──────────┬─────────────┴──────────────────────┬──────────────────────┘
           │ lê/grava                           │ escuta
           ▼                                    │
   ~/Library/Application Support/Bando/         │ Darwin notification
     bando.sqlite (sessões, projetos)           │ "com.bando.changed"
   ~/.config/bando/                             │
     agents.toml   providers.toml               │
           ▲                                    │
           │ grava estado e avisa ──────────────┘
┌──────────┴──────────────── bando (CLI, Swift) ──────────────────────┐
│ bando new / ls / attach / msg / stop / rm / clean                    │
│ bando run <sessão>   → lê provider + Keychain, monta env, exec agente│
│ bando hook <evento>  → chamado por hooks do agente e do tmux         │
└──────────┬──────────────────────────────────────────────────────────┘
           ▼
   tmux (servidor próprio: tmux -L bando)
     sessão bando_<id>  cwd = worktree  →  claude | codex | agy | ...
```

Pontos centrais:

- **Sem daemon.** Quem mantém os agentes vivos é o tmux. O app e o CLI só leem e gravam o SQLite. Fechar o app não mata nada.
- **Servidor tmux separado** (`tmux -L bando`) para não misturar com as sessões tmux do usuário.
- **Avisos entre processos** por Darwin notification (`notify_post`), que não exige socket nem processo escutando.
- **Um pacote Swift** com três targets: `BandoCore` (biblioteca), `Bando` (app) e `bando` (CLI). App e CLI usam o mesmo código para criar sessão, ler config e falar com o tmux.
- **O app embute o CLI** em `Bando.app/Contents/MacOS/bando` e oferece criar o link em `~/.local/bin/bando`.

## 6. Agentes e providers configuráveis

Esta é a principal diferença em relação ao Xirp. Dois conceitos separados:

- **Agente:** a CLI que roda no terminal (`claude`, `codex`, `gemini`, `agy`, `opencode`, `aider`...). Diz como iniciar, como passar o prompt, como retomar e como detectar o estado.
- **Provider:** de onde vem o modelo. Diz quais variáveis de ambiente e argumentos injetar no agente: URL base, chave, modelo padrão. Por exemplo, o Claude Code pode rodar com a Anthropic direto, com OpenRouter, com o GLM da z.ai ou com um modelo local, trocando só as variáveis.

Uma sessão é **agente + provider (opcional) + modelo (opcional)**.

### 6.1 `~/.config/bando/agents.toml`

```toml
[agents.claude]
name     = "Claude Code"
cmd      = "claude"
prompt   = ["{prompt}"]                 # como passar a tarefa inicial
resume   = ["--resume", "{native_id}"]  # retomar uma conversa específica
continue = ["--continue"]               # retomar a última do diretório
model    = ["--model", "{model}"]
status   = "hooks"                      # hooks | output | silence
hooks    = "claude"                     # preset de instalação de hooks
providers = ["anthropic", "openrouter", "zai"]  # providers compatíveis
install  = "curl -fsSL https://claude.ai/install.sh | bash"

[agents.agy]
name     = "Antigravity"
cmd      = "agy"
prompt   = ["-i", "{prompt}"]
continue = ["--continue"]
resume   = ["--conversation", "{native_id}"]
model    = ["--model", "{model}"]
status   = "output"
busy     = 'esc to interrupt|Thinking|Running'
waiting  = 'Allow|Approve|\(y/n\)|Do you want'
idle_after = "4s"                       # silêncio que dispara a checagem

[agents.shell]
name   = "Terminal"
cmd    = "$SHELL"
status = "none"
```

Placeholders aceitos: `{prompt}`, `{model}`, `{native_id}`, `{worktree}`, `{branch}`, `{session_id}`.

Presets: o Bando vem com entradas prontas para Claude Code, Codex, Gemini CLI, Cursor, Pi e Antigravity. O arquivo do usuário sobrescreve campo a campo.

### 6.2 `~/.config/bando/providers.toml`

```toml
[providers.anthropic]
name = "Anthropic"
env  = { ANTHROPIC_API_KEY = "keychain:bando/anthropic" }

[providers.openrouter]
name = "OpenRouter"
env  = { ANTHROPIC_BASE_URL = "https://openrouter.ai/api", ANTHROPIC_AUTH_TOKEN = "keychain:bando/openrouter" }
models = ["anthropic/claude-sonnet-5.5", "z-ai/glm-5"]

[providers.zai]
name = "z.ai GLM"
env  = { ANTHROPIC_BASE_URL = "https://api.z.ai/api/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/zai" }

[providers.ollama]
name = "Ollama local"
env  = { OPENAI_BASE_URL = "http://localhost:11434/v1", OPENAI_API_KEY = "ollama" }
models = ["qwen3-coder"]

[providers.assinatura]
name = "Conta do agente"   # sem env: usa o login que a CLI já tem
```

Os endereços acima são exemplos e serão conferidos na documentação de cada serviço antes de virarem presets.

Regras:

- **Segredos nunca ficam no arquivo.** O valor `keychain:<serviço>/<conta>` é lido do Keychain do macOS na hora de iniciar. A tela de configurações grava no Keychain.
- **Segredos não aparecem em `ps` nem no ambiente do tmux.** O tmux não recebe a chave. Ele roda `bando run <sessão>`, que lê o Keychain, monta o ambiente e faz `exec` do agente. Assim a chave só existe no ambiente do processo do agente.
- **Valores podem referenciar variáveis** já existentes: `env:MINHA_VAR`.
- **Override por projeto:** `.bando.toml` na raiz do repositório pode definir agente e provider padrão, script de setup e variáveis extras (sem segredos).
- **Override por sessão:** a tela "Nova sessão" deixa escolher agente, provider e modelo.

### 6.3 Tela de configurações

- Lista de agentes com estado "instalado / não encontrado" (`which`), versão (`--version`) e botão de instalar com o comando do preset.
- Editor de agente com campos do TOML e botão "testar" (inicia numa sessão descartável).
- Lista de providers, campo de chave que grava no Keychain e botão "testar conexão" quando o provider tiver um endpoint de checagem conhecido.
- Botão "abrir arquivo" para editar o TOML na mão. O app recarrega sozinho quando o arquivo muda (FSEvents).

## 7. Detecção de estado

Estados: `queued` (esperando dependência), `starting`, `working`, `waiting` (pedindo permissão ou resposta), `review` (terminou a vez e há mudanças no worktree que você ainda não viu), `idle` (terminou a vez sem mudança nova), `stopped`, `exited`, `error`.

Três modos, escolhidos por agente:

1. **`hooks`**: para agentes que têm hooks (Claude Code, Codex, Gemini, Cursor). O Bando instala hooks que chamam `bando hook <evento> --session $BANDO_SESSION_ID`. O binário Swift abre, grava e fecha em poucos milissegundos, sem subir `node`. Hooks só agem quando `BANDO_SESSION_ID` existe, então não afetam o uso fora do Bando.
2. **`output`**: para agentes sem hooks (Antigravity, Pi, outros). O tmux faz o trabalho de vigiar:
   - `set-option -t bando_<id> monitor-silence <idle_after>`
   - `set-hook -t bando_<id> alert-silence 'run-shell "bando hook silence --session <id>"'`
   - `set-hook -t bando_<id> alert-activity` para voltar a `working`.
   Quando dispara, `bando hook silence` roda `tmux capture-pane -p`, aplica as regex `busy` e `waiting` e grava o estado. Não há polling.
3. **`silence`**: para agentes sem regex configurada. Silêncio vira `idle`, atividade vira `working`.

Ao mudar para `waiting` ou `idle`, o `bando hook` manda notificação do macOS (via app, se aberto; senão `osascript`). Clicar na notificação abre a sessão no app.

Fim do processo: `set-hook pane-died` marca `exited` e guarda o código de saída.

## 8. Telas

Baseadas no benchmark de 30 ferramentas parecidas em [pesquisa-ux.md](pesquisa-ux.md), que tem os wireframes completos (seção 5). Resumo das decisões:

1. **Lateral ordenada por urgência.** Grupos "Esperando você", "Pronto para revisar", "Trabalhando" e, abaixo, os projetos. Cada sessão mostra na segunda linha a pergunta pendente ou a última ação. Com vários agentes rodando, o trabalho é achar quem travou. Um seletor (⌘⇧G) troca para a visão por projeto.
2. **Terminal da CLI no centro, sem chat próprio.** O Bando mostra o agente como ele é, então qualquer CLI funciona sem adaptar a interface. Só a sessão visível tem um SwiftTerm anexado; as outras ficam só no tmux.
3. **Estado com cor e forma juntas** (acessibilidade): laranja com "!" esperando, verde com check pronto para revisar, azul animado trabalhando, cinza ocioso, vermelho erro, relógio na fila. O PR tem bolinha de cor própria.
4. **Revisão na mesma janela:** abas Terminal, Diff e Checks no centro. No diff, comentários por linha são enviados ao agente em lote (⌘Enter); commit e PR (`gh`) no mesmo lugar.
5. **Teclado em primeiro lugar:** ⌘N nova sessão, ⌘K paleta, ⌘J próxima sessão esperando você, ⌘⇧D diff, ⌘1 a ⌘9 sessões, ⌘/ lista de atalhos. Todos com ⌘, porque com o foco no terminal as outras teclas vão para a CLI.
6. **Notificação só quando você não está olhando a sessão**, com badge no Dock.

Janelas: principal (`NavigationSplitView` com lateral, centro e inspector ⌥⌘I com agente, provider, modelo, branch, custo e tempo), nova sessão (sheet), Settings (⌘,: Agentes, Providers, Projetos, Notificações, Atualizações) e Relatórios (⌘⇧R, seção 15). Barra de status com contadores e resumo do dia.

### 8.1 Grade de sessões (como no Xirp)

Vários terminais lado a lado na janela principal, para acompanhar agentes ao mesmo tempo. Entra na primeira versão do app (fase 2).

```
┌─ lateral ─┬──────────────── grade 2×2 ─────────────────────┐
│ ESPERANDO │ ◆ corrige-webhook  claude·anthropic │ ◌ refatora-api  agy      │
│ ◆ corrige │ ● Posso rodar pnpm test?            │ Editando src/api.ts…    │
│ TRABALH.  │   1. Sim  2. Não                    │                         │
│ ◌ refator │─────────────────────────────────────┼─────────────────────────│
│ ◌ docs    │ ◌ docs-readme  opencode·openrouter  │ ✓ tela-login  codex  #128│
│ PRONTO    │ Atualizando README.md…              │ Pronto. 4 arquivos.     │
│ ✓ tela-lo │                                     │                         │
└───────────┴─────────────────────────────────────┴─────────────────────────┘
```

- **Layouts:** 1 (foco), 2 lado a lado, 2 empilhados, 2×2, 3×2 e livre (arrastar divisórias). ⌘⌥G alterna entre foco e grade; ⌘⌥1 a ⌘⌥6 escolhem o layout.
- **Montar a grade:** arrastar sessões da lateral para uma célula, ou "Mostrar na grade" no menu de contexto. Opção "grade automática": preenche com as sessões ativas, as que esperam você primeiro.
- **Cada célula** tem cabeçalho fino com estado (cor e forma), nome, agente·provider e botões maximizar, diff e fechar. A célula com foco tem borda de destaque; o teclado vai só para ela. ⌘⌥ setas move o foco entre células.
- **Grade salva por projeto** (ou global), restaurada ao reabrir o app.
- **Custo de memória:** só as células visíveis têm SwiftTerm anexado. Célula que sai da tela é desanexada (o agente continua no tmux). Limite padrão de 6 células, configurável. O `bench.sh` mede o custo por célula, e a meta de 80 MB vale para a grade 2×2 com quatro agentes.
- **Divisão dentro de uma sessão:** terminal extra no mesmo worktree (⌘T) abre ao lado do agente, como o `tmux:split-pane` do Xirp.

O que fica para depois está na seção 5.12 da pesquisa (mesma tarefa em vários agentes com comparação de diffs, resposta pela notificação, barra de menus).

### 8.2 Temas e logo

- **Temas** no mesmo modelo de agentes e providers: catálogo em `catalog/themes.toml` (15 temas: Bando Escuro e Bando Claro, Dracula, Nord, Gruvbox, Solarized, Catppuccin, Tokyo Night, One Dark, GitHub e Monokai), temas do usuário em `~/.config/bando/themes.toml`, mescla campo a campo e `base = "<tema>"` para herdar de outro.
- Cada tema define aparência (claro ou escuro), cor de destaque e as cores do terminal (fundo, texto, cursor, seleção, 16 ANSI).
- Ajustes > Aparência: um tema fixo, ou "seguir o sistema" com um tema claro e um escuro escolhidos à parte.
- As cores de estado das sessões não mudam com o tema (são as cores do sistema), para manter o significado e o contraste.
- **Logo:** fonte em `assets/logo/` (`currentColor`), com versões preta e branca, completa (símbolo + "bando") e só símbolo. Regra de uso:
  - Ícone do app, Dock, barra de menus, favicon e espaços pequenos: **só o símbolo**.
  - Tela "Sobre", README, site, boas-vindas e documentos: **logo completo**.
  - Cor: **preto em tema claro, branco em tema escuro**. No app, o símbolo é desenhado como `Shape` com a cor do texto do tema, então troca sozinho.
  - Ícone do app: símbolo branco sobre quadrado arredondado escuro (`assets/logo/bando-icone.svg` → `scripts/gen-icon.sh` → `assets/AppIcon.icns`).

## 9. Modelo de dados (SQLite)

```
projects(id, name, path, default_agent, default_provider, setup_script, created_at, last_used_at)
sessions(id, project_id, name, prompt, agent, provider, model,
         worktree_path, branch, base_branch, uses_worktree,
         tmux_name, native_id, status, exit_code,
         depends_on, created_at, updated_at, finished_at)
events(id, session_id, kind, payload_json, at)     -- histórico de estados e hooks
```

`native_id` guarda o ID da conversa do agente (quando o hook informa), para retomar com `resume`.

## 10. Fluxo de uma sessão

1. Usuário pede nova sessão (app ou `bando new`).
2. `git worktree add <projeto>/../.bando-worktrees/<projeto>/<slug> -b <branch> <base>` (pasta configurável).
3. Roda o script de setup do projeto, se houver (copiar `.env`, instalar dependências).
4. Se tiver `depends_on` e a sessão pai não terminou, fica `queued`. Quando a pai vira `idle` ou `exited`, o `bando hook` da pai inicia as filhas.
5. `tmux -L bando new-session -d -s bando_<id> -c <worktree> "bando run <id>"`.
6. `bando run` resolve agente + provider, lê o Keychain, monta argumentos e ambiente (`BANDO_SESSION_ID`, `BANDO_PROJECT_ID` e as variáveis do provider), e faz `exec`.
7. Configura `monitor-silence` e hooks do tmux quando o modo for `output` ou `silence`.
8. O app mostra a sessão; o terminal embutido roda `tmux -L bando attach -t bando_<id>`.
9. Apagar: recusa se houver mudança não commitada ou commits sem push, a menos que o usuário confirme. Remove sessão tmux, worktree e, se pedido, o branch.

## 11. Fases

### Fase 0: base (1 a 2 dias)
- Pacote Swift com `BandoCore`, `Bando`, `bando`; dependências fixadas.
- Script `scripts/build-app.sh` que gera `Bando.app` (Info.plist, ícone, CLI e Sparkle embutidos) sem depender de projeto Xcode.
- Sparkle configurado (chave EdDSA, `SUFeedURL`, menu "Procurar atualizações…") e workflow de release no GitHub Actions, para que a primeira versão distribuída já se atualize sozinha.
- Leitura de `agents.toml` e `providers.toml` com presets embutidos.
- **Pronto quando:** `swift build` passa e `bando agents` lista os agentes com estado de instalação.

### Fase 1: núcleo pelo CLI (3 a 4 dias)
- `bando new | ls | attach | msg | stop | rm | run | hook | clean`.
- Worktree, tmux com servidor próprio, SQLite, providers com Keychain.
- Detecção de estado nos três modos; notificação via `osascript`.
- Fila com `depends_on`.
- Tabela `events` gravando cada mudança de estado com horário (base dos relatórios).
- `bando import xirp` (seção 16).
- **Pronto quando:** criar uma sessão com `agy` e outra com `claude` via OpenRouter, ver os estados mudando em `bando ls`, receber notificação quando cada uma termina e ver os projetos importados do Xirp em `bando projects`.

### Fase 2: app (5 a 7 dias)
- Janela principal, nova sessão, terminal embutido com SwiftTerm, troca rápida entre sessões, grade de sessões (seção 8.1).
- Atualização por Darwin notification, sem polling.
- Tela de configurações de agentes e providers, Keychain pela interface.
- Notificações nativas (`UserNotifications`) com clique abrindo a sessão.
- **Pronto quando:** dá para trabalhar o dia todo só pelo app, e o app com grade 2×2 e 5 sessões fica abaixo de 80 MB no Monitor de Atividade.

### Fase 3: relatórios e conforto (contínuo)
- Relatórios diário, semanal, mensal e por intervalo (seção 15), começando pelo resumo do período e pela visão por projeto.
- `bando report --from 2026-11-01 --to 2026-11-30 [--project x] [--csv]` no CLI.
- Diff do worktree e commit pelo app.
- Busca nos transcripts (FTS5 do SQLite).
- Custo e tokens por sessão, lendo os transcripts dos agentes que gravam uso.
- Prompts salvos, retomar sessão nativa, importar sessão aberta fora do Bando.
- Limpeza de worktrees antigos com as mesmas travas do apagar.
- Ícone na barra de menus.

## 12. Medição de desempenho

- `scripts/bench.sh`: abre o app, cria 5 sessões com `agents.shell`, espera 10 s e registra RSS do app e do tmux (`ps -o rss`) e CPU média em 30 s ociosos.
- Rodar ao fim de cada fase e anotar em `doc/medicoes.md`.
- Regra: nenhuma mudança entra se aumentar a RAM do app ociosa em mais de 10 MB sem justificativa escrita.

## 13. Riscos

| Risco | Como tratar |
|---|---|
| SwiftTerm renderizando mais lento que xterm.js em saída muito longa | o tmux limita o histórico (`history-limit`); medir com saída grande na fase 2; se preciso, desligar ligaduras e animações |
| Regex de estado quebram quando a CLI muda o texto | regex ficam no TOML do usuário, editáveis sem recompilar; preset atualizado a cada versão |
| Hooks de agentes mudam de formato | presets de hooks isolados por agente e versionados |
| Conflito com hooks já instalados (Xirp) | instalar hooks em modo de acréscimo, só agir com `BANDO_SESSION_ID`; nunca remover hooks de terceiros |
| Chave de provider vazando | segredos só no Keychain, nunca no TOML, no SQLite, no tmux ou em log |
| tmux ausente | checar na abertura e oferecer `brew install tmux` |
| Assinatura e notarização do .app | fase 0 usa assinatura ad hoc; Developer ID quando for distribuir |
| Keychain pede permissão a cada versão | com assinatura ad hoc cada build é outro app para o Keychain, que abre um aviso e trava a leitura até a resposta (visto em 09/11/2026). O supervisor marca a sessão como esperando com o motivo; a solução definitiva é assinar com Developer ID (identidade estável entre versões) |

## 14. Fora do escopo

Portal ou qualquer nuvem, telemetria, contas de usuário, navegador embutido, editor de arquivos completo, análise de repositório, Linux e Windows. (A retrospectiva semanal do Xirp foi substituída pelos relatórios da seção 15, que são locais.)

## 15. Relatórios e dashboards

Revisão diária, semanal, mensal ou de um intervalo escolhido no calendário, com filtro por projeto e por agente.

### O que mostrar

| Indicador | De onde vem |
|---|---|
| Tempo ativo por projeto e por sessão | tabela `events`: soma dos intervalos em `working`, mais `waiting` separado (tempo esperando você) |
| Tempo esperando resposta sua | intervalos em `waiting`; mostra onde o agente ficou parado |
| Sessões criadas, concluídas, com erro | tabela `sessions` |
| Tokens e custo por projeto, agente, provider e modelo | tabela `usage`, lida dos transcripts dos agentes que gravam uso (Claude Code, Codex) |
| Commits e linhas alteradas | `git log --numstat` nos branches das sessões do período |
| PRs abertos e mergeados | `gh pr list` dos branches das sessões (opcional, só se o `gh` estiver logado) |
| Horas do dia com mais atividade | mapa de calor por hora e dia da semana |

### Telas

- **Resumo do período:** cartões com tempo ativo, sessões, custo e commits, comparando com o período anterior.
- **Por projeto:** barras com tempo e custo de cada projeto; clicar abre as sessões do projeto naquele período.
- **Linha do tempo:** cada sessão como uma faixa no dia, colorida por estado.
- **Exportar:** CSV e Markdown do período (para mandar a um cliente ou registrar horas).

### Como calcular sem pesar

- Gráficos com Swift Charts (nativo, sem dependência).
- Agregação em SQL no SQLite. Os dados de um ano cabem em poucos MB.
- Leitura de uso dos transcripts é incremental (guarda o offset de cada arquivo), feita ao abrir o relatório ou no `bando hook` de fim de turno. Sem processo em segundo plano.
- A tela de relatórios só existe na memória enquanto está aberta.

### Tabelas extras

```
usage(id, session_id, agent, provider, model, input_tokens, output_tokens,
      cache_read, cache_write, cost_usd, at)
transcript_offsets(path, offset, updated_at)
```

Os custos são estimados com uma tabela de preços por modelo em `~/.config/bando/prices.toml`, editável, porque provider próprio pode ter preço diferente.

## 16. Importação do Xirp

Para quem vem do Xirp: `bando import xirp [--backup <arquivo>] [--dry-run]` lê o backup JSON local que o próprio Xirp grava e traz projetos, sessões (com o ID da conversa do agente, para retomar no Bando), custos e PRs. Sessões que estão rodando no Xirp podem ser **adotadas**: o Bando mostra e anexa a sessão tmux existente, sem reiniciar o agente.

- `--dry-run` mostra o que entraria, sem gravar.
- A importação pode rodar de novo: usa o ID original como chave e atualiza o que mudou.
- O Bando nunca escreve nos arquivos do Xirp.

## 17. Atualizações

Dois canais independentes. Nenhum deles toca nos arquivos do usuário.

### 17.1 App (binário): Sparkle + GitHub Releases

Você publica uma versão e, em até 1 hora, todo usuário com o app aberto recebe o aviso (ou instala sozinho, se ele ativou atualização automática).

```
você: git tag v0.3.0 && git push --tags
        │
        ▼
GitHub Actions (.github/workflows/release.yml, runner macOS)
  1. swift build -c release (arm64 + x86_64)
  2. scripts/build-app.sh → Bando.app com Sparkle.framework embutido
  3. assina (Developer ID) e notariza (notarytool), grampeia (stapler)
  4. gera Bando-0.3.0.zip e Bando-0.3.0.dmg
  5. generate_appcast assina o zip com a chave EdDSA (secret do repositório)
     e atualiza appcast.xml (com notas da versão tiradas do CHANGELOG.md)
  6. publica o Release no GitHub e o appcast.xml no GitHub Pages
        │
        ▼
app do usuário: Sparkle checa https://<usuario>.github.io/bando/appcast.xml
  a cada 1 h, compara CFBundleVersion, baixa, confere a assinatura EdDSA,
  troca o .app e reabre
```

Regras:

- **Versão:** `CFBundleShortVersionString` = semver da tag (`0.3.0`); `CFBundleVersion` = número que só cresce (contagem de commits no `main`). O Sparkle compara o `CFBundleVersion`.
- **Chave EdDSA:** gerada uma vez com `generate_keys`. A privada fica só no secret `SPARKLE_ED_PRIVATE_KEY` do GitHub e num backup seu; a pública vai no `Info.plist` (`SUPublicEDKey`). Se a privada vazar, alguém poderia publicar atualização falsa; se for perdida, os usuários teriam de reinstalar manualmente.
- **Feed assinado:** `SURequireSignedFeed = true`, então o próprio appcast é assinado e não pode ser trocado no meio do caminho.
- **Canal beta:** tags `v0.4.0-beta.1` saem no canal `beta` do appcast. Nas configurações o usuário escolhe "estável" ou "beta".
- **Configurações do usuário:** checar automaticamente (padrão sim), instalar automaticamente (padrão não), menu "Procurar atualizações…".
- **Sessões rodando não morrem na atualização:** os agentes estão no tmux, fora do app. O app fecha, troca e reabre já reconectando as sessões.
- **Migração do banco:** cada versão traz migrações GRDB numeradas. Antes de migrar, o app copia o `bando.sqlite` para `backups/bando-<versão-antiga>.sqlite` (mantém os 5 últimos).
- **CLI junto:** o `bando` vive dentro do `.app` e o link em `~/.local/bin/bando` aponta para ele, então atualiza junto com o app.
- **Homebrew (opcional):** cask `bando` num tap próprio, atualizado pelo mesmo workflow, para quem prefere `brew upgrade`.

Custo: assinar com Developer ID e notarizar exige conta Apple Developer (US$ 99/ano). Sem ela o app funciona e o Sparkle atualiza (a assinatura EdDSA continua valendo), mas na primeira instalação o macOS mostra o aviso de desenvolvedor não identificado e o usuário precisa liberar em Ajustes > Privacidade e Segurança.

### 17.2 Catálogo de agentes e providers (sem nova versão do app)

CLIs mudam flags e providers mudam endpoints com mais frequência que o app. Para corrigir um preset sem lançar versão:

- O repositório tem `catalog/agents.toml` e `catalog/providers.toml`. O workflow assina os dois (EdDSA, mesma chave) e publica no GitHub Pages com `catalog.json` (versão, data, hashes).
- O app baixa o catálogo ao abrir e a cada 6 h, confere a assinatura e guarda em `~/Library/Application Support/Bando/catalog/`.
- Ordem de mescla: **presets embutidos < catálogo baixado < arquivos do usuário**. O usuário sempre vence.
- **Proteção de chaves:** se o catálogo mudar `*_BASE_URL` (ou qualquer variável não secreta) de um provider que usa segredo do Keychain, a mudança fica pendente até o usuário aprovar na tela ("O provider OpenRouter mudou o endereço para X. Aplicar?"). Assim um catálogo adulterado não consegue desviar chaves para outro servidor.
- Catálogo com assinatura inválida é ignorado e vira aviso no `bando doctor`.
- Agentes e providers novos que chegam pelo catálogo aparecem com a marca "novo" na tela de configurações.

### 17.3 O que nunca acontece numa atualização

- O app não escreve em `~/.config/bando/agents.toml` nem `providers.toml` (só a tela de configurações, quando o usuário salva).
- Segredos do Keychain não são lidos, movidos nem apagados.
- Entradas do usuário que ficaram inválidas (preset removido, campo renomeado) são puladas com aviso, sem impedir o app de abrir.
- Campos desconhecidos nos arquivos do usuário são ignorados, então um arquivo escrito para uma versão nova não quebra uma versão antiga.

## 18. MCP centralizado

Servidores MCP cadastrados uma vez em `~/.config/bando/mcp.toml` e entregues a qualquer agente que suporte MCP, sem mexer nos arquivos de configuração deles.

| Agente | Como recebe | Onde vai a chave |
|---|---|---|
| Claude Code | `--mcp-config <json>` | `${BANDO_MCP_<ID>_<CHAVE>}` no JSON (o Claude expande) |
| Codex | `-c mcp_servers.<id>={...}` | `env_vars` (stdio) e `env_http_headers` (remoto) |
| OpenCode | `OPENCODE_CONFIG_CONTENT` | `{env:VAR}` |
| Gemini CLI | não suportado: as settings de sistema exigem arquivo do root (verificado na 0.64); além disso o Google encerrou o uso com conta pessoal | - |
| Antigravity | pendente de decisão: só lê `~/.gemini/config/mcp_config.json` (global); não expande `${VAR}`, mas repassa o próprio ambiente aos servidores | - |

- Chaves no Keychain (`keychain:...`); só chegam ao ambiente do processo do agente, nunca em argumentos ou arquivos. Verificado com servidor de teste no Claude Code, Codex e OpenCode: conectado, chave no ambiente do servidor e ausente dos argumentos.
- Filtros: `agents` (só alguns agentes) e `projects` (só alguns projetos); `enabled = false` desliga.
- Próximos passos: ligar/desligar por sessão na tela, presets de servidores comuns no catálogo, Qwen Code (fork do Gemini).

## 18.1 Compressão opcional

Compressor é um proxy local que encolhe o que o agente manda ao modelo. O catálogo (`catalog/compressors.toml`) traz o Headroom.

- **Opcional e por sessão.** A sessão guarda o ID do compressor (coluna `compressor`); vazio é o padrão. Liga em `bando new --compressor <id>` ou no campo Compressão da nova sessão. O app lembra a última escolha.
- **Sem daemon.** O `bando run` escolhe uma porta livre, inicia o proxy antes do agente e o encerra quando o agente sai. Se o tmux for encerrado, o supervisor recebe SIGHUP e leva o proxy junto (SIGTERM e, se ele não sair em 3 s, SIGKILL). A única espera é na subida, até a porta abrir (máximo 30 s).
- **Config, não código.** O catálogo diz, por agente, onde fica a URL do provider (`url_env` no Claude Code, `url_arg` no Codex). O Bando troca essa URL pela do proxy e passa a original ao proxy como destino. Sem provider, o proxy usa o destino padrão dele.
- **Segredos.** A chave do provider continua só no ambiente do agente e segue no pedido até o proxy em 127.0.0.1. O proxy não recebe chave por argumento nem por ambiente.
- **Medido em 13/11/2026** (Headroom 0.44.0, tarefa com trechos de log de 150 linhas): Codex 0.167 + Venice, 103.647 para 76.179 tokens no último pedido (27%); Claude Code 2.1 pela assinatura, 46.367 para 34.617 (25%). JSON cortado pelo Codex e a base fixa do agente não mudam.
- Pendente: `~/.config/bando/compressors.toml` do usuário, ligar e desligar numa sessão existente, mostrar a economia na tela de uso.

## 19. Custo: fonte de verdade

- O transcript do agente é a fonte de verdade. Registros importados de outras ferramentas só valem para sessões sem transcript e são removidos quando a resposta equivalente aparece num transcript (mesmo horário ±2 s e mesma saída). Verificado contra a soma direta dos transcripts: sem dupla contagem (resíduo de cerca de 0,1%).
- Valores são equivalentes ao preço da API. Com assinatura (por exemplo Claude Max), a cobrança real é fixa.
- Pendente: opção de contar todo o Claude Code da máquina (inclusive sessões abertas fora do Bando) e leitor de transcripts do Codex.

## 20. Decisões tomadas

| Tema | Decisão |
|---|---|
| Nome | Bando |
| Stack | SwiftUI + SwiftTerm, tmux, CLI em Swift |
| Worktrees | ao lado do repositório, agrupados: `<pasta do repo>/.bando-worktrees/<repo>/<slug>`. Fica no mesmo disco do projeto, o git cria o worktree sem copiar objetos, e o `.bando-worktrees` oculto não polui a pasta. Configurável por projeto |
| Importar do Xirp | sim, pelo backup JSON (seção 16) |
| Licença | código aberto, MIT |
| Relatórios | diário, semanal, mensal e intervalo livre (seção 15), na fase 3; os dados começam a ser gravados na fase 1 |
| Atualização | Sparkle + GitHub Releases + appcast no GitHub Pages; catálogo de presets assinado e baixado à parte (seção 17) |
| Agentes e providers do usuário | arquivos em `~/.config/bando/` nunca são sobrescritos; mescla campo a campo; `enabled = false` esconde preset |

## 21. Decisões em aberto

1. Bundle ID e organização no GitHub (proposta: `io.github.nerigleston.bando`).
2. Ícone.
3. Conta Apple Developer (US$ 99/ano) para assinar e notarizar. Sem ela tudo funciona, mas a primeira instalação mostra aviso do macOS.
