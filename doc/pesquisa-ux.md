# Pesquisa de UI/UX: orquestradores de agentes de código

Data da pesquisa: 09/11/2026. Base para desenhar a interface do Bando (app nativo macOS, SwiftUI + SwiftTerm, sessões em tmux + git worktree).

## Como ler este documento

- **Fato:** vem de documentação oficial, README, changelog, discussão pública ou artigo, com link ao lado.
- **Inferência:** conclusão minha a partir dos fatos. Sempre marcada com a palavra "Inferência".
- Várias fontes são páginas de terceiros ou de concorrentes (por exemplo, páginas de comparação do Superset). Quando a única fonte é uma dessas, isso está dito.
- Não abri os apps. Tudo o que é visual vem de documentação e relatos, sem captura de tela própria.

---

## 1. Tabela comparativa

| Ferramenta | Tecnologia | Layout | Estado do agente | Revisão | Diferencial |
|---|---|---|---|---|---|
| Conductor | App Mac (stack não confirmado) | Repositórios e workspaces na lateral, chat/terminal no centro, abas Diff e Checks | Não documentado em detalhe | Diff com comentário por linha, aba Checks (CI, comentários do GitHub, todos), criar PR ⌘⇧P | Aba Checks que bloqueia merge com pendência |
| Claude Squad | TUI em Go + tmux | Lista de sessões, abas Preview/Diff | Pausada/ativa | Aba Diff, `s` commit+push | Leve, só teclado |
| Crystal (descontinuado) / Nimbalyst | Electron | Nimbalyst: kanban de sessões | Coluna muda sozinha: rodando, esperando, revisão | Diff, rebase/squash | Card que muda de coluna pelo estado |
| Sculptor (Imbue) | Electron + backend Python, Docker | Workspaces, chat, terminal | Não documentado | Merge Review, Pairing Mode | Pairing Mode: traz o branch do agente para o checkout local |
| Vibe Kanban (encerrando) | Rust + web local | Kanban de tarefas, workspace por tarefa | Coluna do board | Diff com comentário inline, PR | Kanban como entrada de trabalho |
| Emdash | Desktop (stack não confirmado), Mac/Win/Linux | Tarefas, diff, editor, navegador | Via hooks do agente | Diff lado a lado entre agentes, PR, CI | 34 CLIs, issues do Linear/Jira, SSH |
| Superset / Paradev | Electron + xterm.js + node-pty | Workspaces na lateral, terminais em abas, painéis Changes e PR | Trabalhando, pronto, esperando você; som e badge no Dock | Diff com comentário, PR, checks, merge | Paleta de comandos, atalhos remapeáveis, portas por worktree |
| Terragon (encerrado) | Web + nuvem | Dashboard de tarefas | Por tarefa | PR automático | Agentes na nuvem |
| Jean | Tauri 2 + React + Rust | Projetos, worktrees, sessões | Não documentado | Diff unificado e lado a lado | Leve em relação a Electron, modo headless |
| Uzi | CLI Go + tmux | Terminal | `uzi ls` | `uzi checkpoint` | N agentes de modelos diferentes num só comando |
| Catnip (W&B) | Go + SPA web, container | Web e app iOS | Não documentado | Não documentado | Controle pelo celular |
| Container Use (Dagger) | Servidor MCP + CLI | Sem UI própria | `cu watch` | `cu diff`, `cu merge` | Container por agente |
| Codex app (OpenAI) | Electron | Projetos e threads na lateral, review pane | Não documentado | Staged/unstaged, branch vs main, "última rodada", comentário no diff | Automations com fila de revisão |
| Cursor 3 Agents Window | Electron (fork do VS Code) | Janela própria de agentes, lateral de sessões | Não documentado | Diff, Bugbot | Local, worktree, nuvem e SSH no mesmo lugar; `/best-of-n` |
| Claude Code desktop | Electron | Sessões na lateral, painéis arrastáveis (chat, diff, terminal, navegador) | Notificação ao terminar | Comentário por linha, ⌘Enter envia tudo, card de PR com CI, auto-fix, merge quando pronto | Painéis livres, split com ⌥-clique |
| Claude Code Agent View | TUI (CLI) | Lista agrupada por estado + campo de despacho | Trabalhando, precisa de você (amarelo), ocioso, concluído (verde), falhou (vermelho), parado (cinza) | Rótulo de PR colorido | Grupos ordenados pelo que precisa de você |
| GitHub Agent HQ | Web, VS Code, CLI, mobile | Lista de tarefas + logs | Logs em tempo real | PR | Vários fornecedores de agente |
| Google Jules | Web | Feed de atividade + diff à direita | Plano aguardando aprovação | Diff, publicar branch/PR | Plano aprovado antes de codar |
| Google Antigravity | Fork do VS Code | 3 colunas: workspaces, inbox, conversa | Idle, Running, Blocked | Artefatos com comentário | Inbox estilo e-mail |
| Warp | Nativo (Rust) | Abas verticais, painel de agentes | Ícone por aba, badge de não lido, caixa de notificações | Diff do agente | Toasts e caixa de notificação |
| Zed | Nativo (Rust, GPUI) | Threads Sidebar agrupada por projeto | Ferramentas em uso durante a resposta | Multibuffer com aceitar/rejeitar por hunk | Terminal threads para CLIs externas |
| Factory | Desktop Mac/Win | Sessões na lateral | Status, logs | Não documentado | Computer use |
| Devin | Web/desktop, nuvem | Lateral com pastas, até 8 sessões lado a lado | Não documentado | IDE na nuvem | Grade de sessões |
| Amp | CLI (editor removido) | Painel de threads, Thread Map | Não documentado | Não documentado | Mapa de threads |
| cmux | Nativo Swift + AppKit + libghostty | Abas verticais com branch, pasta, portas e texto da notificação | Anel colorido no painel, badge, popover | Não tem | Notificação por OSC 9/99/777 |
| Supacode | Nativo (TCA + libghostty) | Lateral com branch, arquivo, PR | Ocupado, esperando, ocioso | Não documentado | Sessão no daemon zmx; quem precisa sobe para o topo |
| crystl | Nativo, Metal | Rail de projetos, barra de "shards" | Badges ↑N commits, ⚑N arquivos fora do worktree | Merge com um clique | Alerta de arquivo tocado fora do worktree |
| Xirp (Spotify) | Electron (medido localmente, ver PLANO.md) | Lateral de projetos e sessões, grade 2x1/2x2/3x3 | Via hooks | Aba Git | Dependência entre sessões, grade |

---

## 2. Achados por ferramenta

### Conductor (conductor.build)

- Cada tarefa vira um workspace com "branch, arquivos, terminal, diff e caminho de revisão" próprios. Roda Claude Code, Codex, Cursor e OpenCode. Só Mac. [docs](https://www.conductor.build/docs)
- Nova sessão: ⌘⇧N ou o botão `...` ao lado de "New workspace"; pode partir de branch, PR, issue do GitHub ou do Linear. ⌘N também cria workspace. [workflow](https://www.conductor.build/docs/concepts/workflow), [atalhos via changelog](https://www.conductor.build/changelog/0.14.0-command-palette)
- Nome do workspace é uma cidade (`warsaw`, `tokyo`, `warsaw-v2`); o branch nasce genérico e o agente o renomeia conforme o primeiro chat. [workspaces](https://www.conductor.build/docs/concepts/workspaces-and-branches)
- Revisão: ⌘⇧D abre o Diff Viewer; lista de arquivos, diff unificado, filtro por commit, comentário por linha que vira anexo para o agente. Ação "Review" roda uma revisão por agente. ⌘⇧P cria PR. [diff viewer](https://www.conductor.build/docs/reference/diff-viewer)
- Aba Checks: status do git, metadados do PR, CI, deploys, comentários do GitHub, todos. Pode bloquear ou desaconselhar o merge com todo aberto ou check falhando. [checks](https://www.conductor.build/docs/reference/checks)
- Arquivar workspace tira da lateral; histórico fica num painel History. [workflow](https://www.conductor.build/docs/concepts/workflow)
- Atalhos: ⌘K paleta (desde 0.14.0, out/2025), ⌘, configurações, ⌘/ lista de atalhos. [atalhos](https://conductor.build/docs/reference/keyboard-shortcuts)
- Elogios: interface "limpa e relativamente direta", "a experiência mais polida". Reclamações: worktree novo vem sem `.env` e `node_modules`, custo de tokens multiplicado, binário fechado com acesso amplo ao GitHub ("You are INSANE to authorise this app on anything other than throwaway code", comentário no HN citado). [madewithlove](https://madewithlove.com/blog/conductor-running-multiple-ai-coding-agents-in-parallel/)
- Só Mac e só GitHub. [codepick](https://codepick.dev/en/guides/conductor-build-intro/)
- Tecnologia: não achei fonte que diga qual framework usa.

### Claude Squad

- TUI em Go, tmux por sessão, git worktree por sessão, AGPL-3.0. [README](https://github.com/smtg-ai/claude-squad)
- Atalhos: `n` nova, `N` nova com prompt, `D` apagar, `↵/o` entrar, `ctrl-q` sair, `s` commit e push, `c` commit e pausa, `r` retomar, `tab` alterna Preview/Diff, `?` ajuda.
- Escolha do agente por flag `-p` ou `default_program`; perfis aparecem num seletor na criação quando há mais de um.
- Inferência: é o modelo mental mais próximo do Bando (tmux + worktree), só que em terminal. A troca Preview/Diff com uma tecla é um padrão bom para copiar.

### Crystal (Stravu) e Nimbalyst

- Crystal foi descontinuado em fev/2026; a última versão aponta para o Nimbalyst. [repo](https://github.com/stravu/crystal), [Superset vs Crystal](https://superset.sh/compare/superset-vs-crystal) (página de concorrente)
- Nimbalyst mostra sessões como cards num kanban que mudam de coluna sozinhos: em andamento, esperando (quando pergunta algo), revisão (quando termina). Fonte secundária. [rywalker](https://rywalker.com/research/nimbalyst), [aiidelist](https://aiidelist.com/ide/nimbalyst.md)
- Crítica de usuário (autor ligado à Stravu) ao Claude Code desktop: falta busca de sessões antigas ("e a sessão cinquenta?"). [dev.to](https://dev.to/stravukarl/claude-code-desktop-after-the-redesign-what-anthropic-shipped-and-what-power-users-still-miss-150h)

### Sculptor (Imbue)

- Electron com frontend React e backend Python; cada agente num container Docker. [Show HN](https://hn.svelte.dev/item/45427697)
- Pairing Mode troca o checkout local para o branch do agente e sincroniza nos dois sentidos; Merge Review escolhe o que manter. [imbue.com](https://imbue.com/sculptor/)
- ⌘K para buscar e navegar. Hoje é "research preview experimental". [repo](https://github.com/imbue-ai/sculptor)
- Reclamações no HN: "sculptor_backend consome muita CPU e memória parado" (bni, sugeriu trocar Electron por Tauri); Docker pesado para laptop (_1tem); "a sobrecarga cognitiva é real" (penlu). [Show HN](https://hn.svelte.dev/item/45427697)

### Vibe Kanban (Bloop)

- Kanban para planejar; cada issue vira workspace com branch, terminal e dev server; diff com comentário inline que volta para o agente; PR com descrição gerada. Backend em Rust. [README](https://github.com/BloopAI/vibe-kanban)
- O README diz "Vibe Kanban is sunsetting". A empresa encerrou em abr/2026 segundo [aiidelist](https://aiidelist.com/ide/vibe-kanban.md).

### Emdash

- App desktop open source (YC W26), Mac/Win/Linux, 34 CLIs detectadas automaticamente. "Add Task" cria um ou mais worktrees; dá para mandar a mesma tarefa para vários agentes e comparar os diffs lado a lado. [docs](https://emdash.com/docs), [repo](https://github.com/generalaction/emdash)
- Issues do Linear, Jira, GitHub, GitLab, Asana viram tarefa; PR, CI e merge dentro do app; sessões em tmux sobrevivem a reconexão; SSH remoto com credencial no Keychain.
- Estado e notificações vêm de hooks do ciclo de vida do agente.

### Superset, agora Paradev

- Renomeado para Paradev em out/2026. [techbytes](https://techbytes.app/posts/paradev-one-workspace-for-claude-code-codex-and-any-coding/), [openalternative](https://openalternative.co/paradev)
- Electron, React, xterm.js, node-pty. Worktree por tarefa criado em cerca de 2 s, scripts de setup e teardown por projeto, visualização das portas usadas por worktree. [Show HN](https://hn.svelte.dev/item/46368739), [README](https://github.com/superset-sh/superset)
- Lateral mostra se cada agente está trabalhando, pronto ou esperando você; "som de conclusão e badge no Dock". Paleta de comandos para ir a qualquer workspace, ação ou configuração. ⌘I abre editor de prompt; todo atalho é remapeável (⌘/). Configuração por agente: comando de lançamento, templates de prompt, modelo. [README](https://github.com/superset-sh/superset)
- Reclamações no HN: terminal não aguenta saída grande (limite do xterm.js, ahmadyan); "ainda não entendo o que está acontecendo" (xmonkee). [Show HN](https://hn.svelte.dev/item/46368739)

### Terragon

- Rodava Claude Code e outras CLIs na nuvem, abria PR sozinho, dashboard de tarefas. Encerrou e liberou o código (Apache-2.0). Fonte secundária. [vibed-lab](https://vibed-lab-agents.pages.dev/agent/terragon-labs-terragon-oss)

### Jean (coolLabs)

- Tauri 2, React 19, Rust. Projetos, worktrees e sessões com Claude CLI, Codex CLI e OpenCode; diff unificado e lado a lado; modo headless que serve a UI por HTTP. [mintlify](https://mintlify.com/coollabsio/jean/introduction)

### Chorus

- Não achei um produto único com esse nome. Há um app de chat multimodelo nativo e um IDE "até 6 sessões em paralelo" numa URL de desenvolvimento, sem release confirmado. [chorus.sh](https://chorus.sh/). Fora da análise.

### Uzi

- CLI Go: `uzi prompt --agents claude:3,codex:2 "..."` sobe 5 agentes, cada um com worktree e tmux; `uzi run` roda um comando em todos; gerencia portas de dev server. [docs](https://www.mintlify.com/devflowinc/uzi/introduction)
- Inferência: o "N agentes de uma vez com a mesma tarefa" aparece em Uzi, Emdash, Cursor (`/best-of-n`) e Agent HQ. Vale como recurso de V2 no Bando.

### Catnip (Weights & Biases)

- Binário Go com SPA embutida, roda em container, cria worktrees; web e app iOS para controlar agentes de longe. Foco em Claude Code. [README](https://raw.githubusercontent.com/wandb/catnip/main/README.md)

### Container Use (Dagger)

- Servidor MCP: cada agente ganha um container. Sem UI gráfica; `cu watch` é "um git log ao vivo", `cu log`, `cu diff`, `cu terminal`. [blog Dagger](https://dagger.io/blog/agent-container-use), [InfoQ](https://www.infoq.com/news/2025/08/container-use)

### OpenAI Codex app e Codex cloud

- Lançado em 02/02/2026 para macOS; threads agrupadas por projeto na lateral; worktree embutido; comentário no diff; abrir no editor. [9to5mac](https://9to5mac.com/2026/02/02/openai-launches-codex-app-for-macos-here-are-the-details)
- Review pane alterna staged/unstaged, compara branch com main e tem a visão "Last turn changes" (só a última rodada do agente). [troubleshooting](https://developers.openai.com/codex/app/troubleshooting)
- Automations rodam em worktree de fundo e o resultado cai numa fila de revisão. [9to5mac](https://9to5mac.com/2026/02/02/openai-launches-codex-app-for-macos-here-are-the-details)
- OpenAI escolheu Electron para ter Windows e Linux depois. [devclass](https://www.devclass.com/development/2026/02/05/traditional-ides-not-the-right-tool-for-development-with-agentic-ai-openai-claims/4090132)
- Reclamações: app-server chegando a 4,4 GB num Mac de 16 GB com threads longas; lista de threads e lateral ficam lentas com histórico grande; tópico "The new Codex App UI redesign is INSANELY LAGGY". [issue #21134](https://upd.dev/openai/codex/issues/21134), [fórum OpenAI](https://community.openai.com/t/the-new-codex-app-ui-redesign-is-insanely-laggy/1401335)
- Um guia de terceiros (jul/2026) diz que o app virou um modo do ChatGPT desktop. Não confirmei em fonte oficial, mas a documentação do Codex hoje redireciona para learn.chatgpt.com.

### Cursor 3 (Agents Window)

- Lançado em 02/04/2026: janela própria para muitos agentes "localmente, em worktrees, na nuvem e em SSH remoto". Abre pela paleta (⌘⇧P → Agents Window). [changelog 3.0](https://cursor.com/changelog/3-0)
- `/best-of-n` roda a mesma tarefa em vários modelos, cada um num worktree, e compara. Design Mode: ⌘⇧D, ⌘L adiciona elemento ao chat. [changelog 3.0](https://cursor.com/changelog/3-0)
- 3.2 (24/04/2026): `/multitask` divide o pedido em subagentes paralelos. [doolpa](https://doolpa.com/news/cursor-3-2-multitask-worktrees-multi-root-workspaces-april-24-2026)

### Claude Code desktop (aba Code)

- Redesenhado em 14/04/2026 para sessões paralelas. [blog Anthropic](https://claude.com/blog/claude-code-desktop-redesign?via=toools), [MacRumors](https://macrumors.com/2026/04/15/anthropic-rebuilds-claude-code-desktop-app)
- Nova sessão: linha de controles abaixo do prompt com ambiente (Local, SSH, Cloud), pasta do projeto, modo de permissão (Manual, Accept edits, Plan, Auto, Bypass), modelo e worktree (desligado por padrão). [docs](https://code.claude.com/docs/en/desktop)
- Painéis arrastáveis: chat, diff, navegador, terminal, arquivos, plano, tarefas. ⌥-clique numa sessão abre lado a lado. Painel de detalhes da sessão com cards (ambiente, mudanças, tarefas de fundo, uso de contexto).
- Diff: clicar em `+12 -1` no card Changes; `+` ao lado da linha para comentar; ⌘Enter envia todos os comentários de uma vez. PR aparece no card com status do CI; menu com "Auto-fix" e "Merge when ready" (auto-merge do GitHub). Precisa do `gh`.
- Atalhos: ⌘/ lista, ⌘N nova sessão, ⌃Tab / ⌃⇧Tab troca sessão, Esc para a resposta, ⌘⇧D diff, ⌘⇧B navegador, ⌃\` terminal, ⌘⇧M modo de permissão, ⌘⇧I modelo, ⌘\\ fecha painel.
- Notificação do sistema "quando uma sessão termina e você não está olhando para ela". Arquivar automático após merge do PR (opção).
- Reclamações de desempenho (Electron): renderer a 68% de CPU parado no macOS, 2,4 GB e 70% de CPU num MacBook Air M3, 1,18 GB com 9 processos sem conversa aberta no Windows. [claudeissues 77560](https://claudeissues.com/issue/77560-bug-claude-desktop-v1-20186-9-consumes-70-cpu-and-2-4gb-ram-on-a-macbook-air-m3), [claudeissues 40633](https://claudeissues.com/issue/40633-bug-claude-desktop-windows-9-processes-consuming-1-18-gb-ram-with-no-conversatio), [claudeissues 32012](https://claudeissues.com/issue/32012-claude-desktop-app-renderer-process-consumes-80-of-total-cpu-even-when-idle)
- O desktop não vê sessões criadas pela CLI nem na nuvem. [busca, docs](https://code.claude.com/docs/en/desktop)

### Claude Code Agent View (`claude agents`)

- Uma tela de terminal para todas as sessões de fundo. Cabeçalho conta "esperando você · trabalhando · concluídas"; o título da aba do terminal mostra "2 awaiting input". Lista agrupada: Pinned, Ready for review, Needs input, Working, Completed. Cada linha: ícone, nome, status ou pergunta atual, idade, `#N` do PR. Campo de despacho embaixo: cada Enter cria uma sessão nova. [docs](https://code.claude.com/docs/en/agent-view)
- Estados: Working (animado), Needs input (amarelo), Idle (esmaecido), Completed (verde), Failed (vermelho), Stopped (cinza). A forma do ícone diz se o processo está vivo. Rótulo do PR: amarelo (checks/revisão pendente ou falhando), verde (checks ok), roxo (merged), cinza (rascunho/fechado).
- Espaço abre "peek" com a última saída ou a pergunta pendente, e dá para responder sem entrar na sessão. Enter entra; ao entrar, mostra um resumo do que aconteceu na ausência.
- Notifica quando a sessão passa a precisar de você, termina ou falha.
- Inferência: é a melhor referência de estados e de ordenação por urgência que encontrei. O Bando pode usar quase a mesma tabela de estados.

### Claude Code on the web

- Sessões na nuvem; diff com estatísticas, comentários inline, "Create PR" no topo do diff (PR, rascunho ou página de composição do GitHub); `--teleport` traz a sessão para o terminal local. [quickstart](https://code.claude.com/docs/en/web-quickstart), [fast.io](https://fast.io/resources/claude-code-web-interface-guide/)

### GitHub Copilot coding agent / Agent HQ

- Mission control em github.com/copilot/agents: atribuir tarefas em vários repositórios, escolher agente customizado, logs em tempo real ("mostram o raciocínio, não só as ações"), pausar/refinar/reiniciar, ir direto ao PR. Recomenda revisar logs, depois arquivos, depois checks. [GitHub blog](https://github.blog/ai-and-ml/github-copilot/how-to-orchestrate-agents-using-mission-control/)
- Mesma interface na web, VS Code, mobile e CLI. [GitHub blog](https://github.blog/news-insights/product-news/welcome-home-agents/)

### Google Jules

- Plano listando arquivos afetados, botão "Approve plan"; feed de atividade com "mini diff" no meio; diff em tela cheia à direita só com arquivos alterados; resumo final (arquivos, tempo, linhas, branch, mensagem de commit); "Publish branch" ou "Publish PR". [docs](https://jules.google/docs/code/)
- Um relato diz que o plano é aprovado sozinho depois de 5 minutos sem resposta. [machinelearningmastery](https://machinelearningmastery.com/practical-agentic-coding-with-google-jules/)

### Google Antigravity (Agent Manager)

- Três colunas: workspaces e "Playground" à esquerda, Inbox no meio (cada tarefa é uma conversa, como e-mail), área de trabalho à direita. Estados: Idle, Running, Blocked ("Blocked significa que precisa de você"). Política de revisão: Always Proceed, Agent Decides, Request Review. [betterstack](https://betterstack.com/community/guides/ai/antigravity-ai-ide/)
- Artefatos (lista de tarefas, plano, walkthrough, diffs, screenshots) com comentário direto neles. [codelab](https://codelabs.developers.google.com/getting-started-google-antigravity?hl=en)
- Reclamações: "parece inacabado", desempenho piora com o tempo e gasta bateria, limite de uso agressivo. [betterstack](https://betterstack.com/community/guides/ai/antigravity-ai-ide/)

### Warp

- Notificações em três tipos: Complete, Request (bloqueado esperando você), Error. Aparecem como toast (no máximo dois por vez, clique leva à sessão), caixa de notificações no sino com filtros All/Unread/Errors, ícone de estado em cada aba, badge de não lido, notificação do sistema quando o app está em segundo plano. Marca como lido ao abrir a aba. [docs](https://docs.warp.dev/agents/capabilities/agent-notifications/)
- Claude Code e OpenCode precisam de plugin; Codex por configuração nativa.

### Zed

- Threads Sidebar (⌘⌥J) agrupada por projeto; seletor de worktree na barra de título que também cria worktree; "terminal threads" para CLIs externas, cada uma como item da lateral. ⌃Tab alterna threads recentes, ⇧⌫ arquiva. [docs](https://zed.dev/docs/ai/agent-panel)
- Revisão num multibuffer com aceitar/rejeitar por hunk (⌃⇧R). Notificação e som quando o agente termina com o Zed em segundo plano, configuráveis.

### Factory

- App desktop (abr/2026, Mac e Windows): cada sessão na lateral com contexto, progresso e histórico; status, logs e configuração no mesmo lugar. [factory.ai](https://factory.ai/news/factory-desktop)

### Devin

- Lateral com sessões não arquivadas, pastas recolhíveis, sessões em lote indentadas sob a sessão mãe; arrastar uma sessão sobre outra mostra até 8 lado a lado. [release notes](https://releasebot.io/updates/devin/devin-desktop), [docs](https://docs.devin.ai/release-notes/2026)

### Amp

- Painel de threads ativas com atalhos (jan/2026), Thread Map para ver a relação entre threads; extensão de editor removida em fev/2026. [tessl](https://tessl.io/blog/amp-launches-thread-map-to-help-navigate-ai-coding-agent-work/), [chronicle](https://ampcode.com/chronicle)

### cmux

- Terminal nativo Swift + AppKit com libghostty, "sem Electron". Abas verticais mostram branch, pasta, portas e o texto da última notificação. Quando um agente precisa de atenção: anel no painel, badge na lateral, popover, notificação do macOS. Dispara por sequências OSC 9/99/777 ou CLI/hooks. Lê a configuração do Ghostty. [cmux.com](https://cmux.com/)

### Supacode

- Nativo macOS (The Composable Architecture + libghostty, macOS 26+). Sessões num daemon (zmx) separado do app: fechar e abrir reconecta com scrollback. Lateral mostra branch, arquivo e PR; worktrees que precisam de atenção sobem para o topo; fixar, arquivar, apagar automático após N dias. Badge por painel: ocupado, esperando, ocioso. ⌃1 a ⌃9 pulam para worktrees; paleta de comandos; CLI e deeplink `supacode://`. [README](https://github.com/supabitapp/supacode)
- Inferência: é o concorrente mais parecido com o Bando em tecnologia. Diferença do Bando: providers configuráveis, relatórios e tmux em vez de zmx.

### crystl

- Nativo, renderização com Metal. Badges sob cada aba: ↑N commits prontos para merge, ⚑N arquivos tocados fora do worktree (e leitura de credenciais). Painel de atividade: "quem está trabalhando, quem está ocioso e para onde vão os tokens". Cards flutuantes para aprovações. Merge com um clique (rebase, fast-forward, limpa o worktree). ⌘K. [crystl.dev](https://crystl.dev/features/parallel-sessions/)

### Xirp (Spotify)

- App macOS da Spotify, beta público desde 10/08/2026, worktree por tarefa, Claude Code, Codex, Gemini, Pi e Cursor. [Backstage docs](https://backstage.spotify.com/docs/xirp), [getting started](https://backstage.spotify.com/docs/xirp/getting-started)
- Home com prompt "What are we shipping?"; visão de projetos com branch atual e contagem de sessões; centro do projeto com prompt, cards das sessões ativas e abas Git, Files, Skills, Rules; sessão com terminal ao vivo e lateral de projetos; grade 2x1, 2x2 ou 3x3 com arrastar da lateral. Dependência entre sessões definida na criação. [betterstack](https://betterstack.com/community/guides/ai/xirp-agent/)
- Nova sessão: objetivo, agente, checkout principal ou worktree novo. Modelo, credenciais e permissões ficam na configuração nativa de cada agente. Status depende de hooks (Configurações > Notificações). Central de notificações no sino com adiar e dispensar. [getting started](https://backstage.spotify.com/docs/xirp/getting-started)
- Tecnologia: nenhuma fonte web cita o framework. A medição local do PLANO.md (5 processos Electron, cerca de 1 GB) é a evidência.

---

## 3. Padrões do mercado (o usuário vai esperar isso)

Fatos, observados em pelo menos cinco ferramentas cada:

1. **Lateral com projetos e sessões, conteúdo no centro.** Conductor, Codex app, Claude Code desktop, Paradev, Zed, Factory, Devin, Supacode, Xirp.
2. **Uma sessão = um worktree + um branch.** Todas as ferramentas locais. Claude Code desktop deixa o worktree desligado por padrão; os demais ligam.
3. **Três estados mínimos: trabalhando, esperando você, pronto/ocioso.** Agent View, Antigravity (Running/Blocked/Idle), Warp, Paradev, Supacode, Nimbalyst. "Esperando você" sempre tem a cor mais chamativa (amarelo ou laranja no Agent View).
4. **Notificação do sistema só quando você não está olhando para a sessão.** Claude Code desktop, Zed, Warp, cmux.
5. **Diff com comentário por linha que volta para o agente.** Conductor, Codex app, Claude Code desktop, Paradev, Vibe Kanban, Antigravity.
6. **PR e status de CI dentro do app.** Conductor (Checks), Claude Code desktop (card de PR), Paradev (painel PR), Emdash, Agent View (rótulo colorido do PR).
7. **⌘K para paleta e ⌘N para nova sessão; ⌘/ lista os atalhos.** Conductor, Sculptor, crystl, Supacode, Paradev, Claude Code desktop.
8. **⌘⇧D abre o diff.** Conductor e Claude Code desktop usam a mesma tecla.
9. **Arquivar em vez de apagar, com histórico recuperável.** Conductor, Claude Code desktop, Zed, Supacode, Devin.
10. **Script de setup por projeto** para copiar `.env`, instalar dependências e separar portas. Conductor (`CONDUCTOR_PORT`), Paradev, Uzi.

---

## 4. Diferenciais que valem copiar e erros a evitar

### Copiar

| Ideia | De onde | Por quê (inferência) |
|---|---|---|
| Ordenar a lista pelo que precisa de você (grupos "Esperando você", "Pronto para revisar", "Trabalhando") | Claude Code Agent View; Supacode sobe para o topo | Com 5 sessões, achar quem travou é o trabalho principal |
| Mostrar na linha a pergunta pendente ou a última ação, além do nome | Agent View, cmux (texto da notificação na aba) | Decide se precisa entrar sem abrir |
| Peek: responder sem trocar de sessão | Agent View (Espaço) | Permissões simples resolvem em 2 s |
| Resumo do que aconteceu enquanto você estava fora | Agent View | Reduz a sobrecarga cognitiva citada no HN |
| "Só a última rodada" no diff | Codex app | Revisar incremental em vez de tudo de novo |
| Comentários em lote enviados com ⌘Enter | Claude Code desktop | Uma rodada de correção em vez de várias |
| Aba Checks que segura o merge com pendência | Conductor | Evita merge com CI vermelho |
| Rótulo de PR com cor própria (pendente, ok, merged, rascunho) | Agent View | Separa estado do agente do estado do PR |
| Badge de arquivos tocados fora do worktree | crystl | Detecta agente vazando para o checkout principal |
| Toasts limitados a dois, caixa de notificações com Não lidas/Erros, lido ao abrir | Warp | Evita enxurrada |
| Sessão sobrevive ao fechamento do app | Supacode (zmx), Emdash (tmux), Claude Squad | O Bando já tem isso com tmux; mostrar na UI |
| Nome de workspace legível e branch renomeado depois | Conductor | Branch útil sem obrigar o usuário a nomear antes |
| Grade de sessões lado a lado | Xirp (2x2, 3x3), Devin (até 8), Claude Code (⌥-clique) | Acompanhar 2 a 4 agentes ao mesmo tempo |
| Atalhos remapeáveis e lista em ⌘/ | Paradev, Conductor | Usuário de terminal espera isso |

### Evitar

| Erro | Fonte |
|---|---|
| App de orquestração pesado parado (CPU e RAM altos em idle) | Sculptor no HN (bni), Claude desktop (68% CPU parado, 2,4 GB), Codex app (4,4 GB) |
| Lista de threads que fica lenta com histórico grande | Codex app, [issue](https://upd.dev/openai/codex/issues/25779) |
| Terminal que engasga com saída grande | Superset/xterm.js, [Show HN](https://hn.svelte.dev/item/46368739) |
| Pedir acesso amplo ao GitHub | Conductor, [madewithlove](https://madewithlove.com/blog/conductor-running-multiple-ai-coding-agents-in-parallel/) |
| Worktree novo sem `.env` e dependências | Conductor, mesma fonte |
| Aprovar plano sozinho por tempo | Jules, [relato](https://machinelearningmastery.com/practical-agentic-coding-with-google-jules/) |
| Sessões criadas fora do app invisíveis | Claude Code desktop não vê sessões da CLI ([docs](https://code.claude.com/docs/en/desktop)) |
| Navegar sessões antigas sem busca | crítica ao Claude Code desktop ([dev.to](https://dev.to/stravukarl/claude-code-desktop-after-the-redesign-what-anthropic-shipped-and-what-power-users-still-miss-150h)) |
| Esconder o custo de rodar vários agentes | madewithlove, codepick (Pro estoura limite) |
| Interface que não explica o que está acontecendo | "ainda não entendo o que está acontecendo" (Superset, HN) |
| Notificação de agente de terceiro que some sem aviso | Warp, [issue](https://gh.r-mj.com/warpdotdev/claude-code-warp/issues/62) |

---

## 5. Proposta de UI/UX para o Bando

Tudo nesta seção é inferência minha a partir dos achados acima e das Human Interface Guidelines.

### 5.1 Estrutura da janela

`NavigationSplitView` com três colunas no padrão macOS:

- **Sidebar (esquerda):** projetos e sessões. Recolhe com ⌃⌘S (padrão do sistema).
- **Conteúdo (centro):** terminal da sessão (SwiftTerm em `tmux attach`). Uma barra de abas fina no topo do centro: Terminal, Diff, Checks.
- **Inspector (direita, `.inspector`):** detalhes da sessão. Abre com ⌥⌘I (padrão do sistema). Fechado por padrão.
- **Toolbar:** título da sessão, branch, botões Diff, Commit, PR, Parar, e o botão "+" de nova sessão.
- **Configurações:** janela `Settings` separada (⌘,), com abas.
- **Relatórios:** janela própria (`Window`), aberta pelo menu Janela ou ⌘⇧R.

### 5.2 Janela principal

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●   [≡]   pagamentos / corrige-webhook   ⑂ bando/corrige-webhook   [+] [Diff] [PR] │
├──────────────────────────┬────────────────────────────────────────────┬───────────────┤
│ [Buscar sessões]     ⌘F  │ Terminal │ Diff +42 −7 │ Checks ●           │ SESSÃO        │
│                          ├────────────────────────────────────────────┤ Agente  Claude│
│ ESPERANDO VOCÊ (2)       │ $ claude --model sonnet                    │ Provider Anth.│
│ ◆ corrige-webhook   2m   │                                            │ Modelo sonnet │
│   "Posso rodar           │ ● Preciso rodar `pnpm test` para validar.  │ Branch ...    │
│    pnpm test?"           │                                            │ Worktree ...  │
│ ◆ migra-prisma      5m   │   1. Sim                                   │ Depende de: — │
│   permissão: Edit        │   2. Sim, e não perguntar de novo          │               │
│                          │   3. Não                                   │ MUDANÇAS      │
│ PRONTO PARA REVISAR (1)  │                                            │ 4 arquivos    │
│ ✓ tela-login     #128 ●  │                                            │ +42 −7        │
│                          │                                            │ ↑2 commits    │
│ TRABALHANDO (2)          │                                            │               │
│ ◌ refatora-api   12m     │                                            │ CUSTO         │
│   Editando src/api.ts    │                                            │ US$ 0,84      │
│ ◌ docs-readme     1m     │                                            │ 128k tokens   │
│                          │                                            │               │
│ PROJETOS                 │                                            │ TEMPO         │
│ ▸ pagamentos         3   │                                            │ ativo 18 min  │
│ ▸ site-institucional 1   │                                            │               │
│ ▸ agroway            0   │                                            │               │
│                          │                                            │               │
│ [+ Nova sessão  ⌘N]      │                                            │               │
├──────────────────────────┴────────────────────────────────────────────┴───────────────┤
│ 2 esperando · 2 trabalhando · 1 pronta        hoje: 3h12 · US$ 4,10 · 7 commits       │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

Decisões:

- A lateral tem dois modos, alternados por um seletor no topo ou ⌘⇧G: **por estado** (padrão, igual ao Agent View) e **por projeto** (árvore projeto > sessões). Os dois modos existem no Agent View (`Ctrl+S`).
- Cada linha: símbolo de estado, nome, idade, e uma segunda linha em cinza com a pergunta pendente ou a última ação. Número do PR com bolinha colorida quando existe.
- Barra de status embaixo da janela com contadores e o resumo do dia. Some quando a janela fica estreita.
- O terminal é o centro. Nada de chat próprio: o Bando mostra a CLI do agente como ela é. Isso mantém qualquer agente compatível sem adaptação de UI.
- Só a sessão visível tem um SwiftTerm anexado. Ao trocar de sessão, o terminal anterior é desanexado (regra do CLAUDE.md). O estado na lateral vem dos hooks e do tmux, sem depender do terminal estar aberto. Por isso a grade de vários terminais fica para depois: cada célula custa um terminal vivo.

### 5.3 Nova sessão (sheet, ⌘N)

```
┌──────────────────────────── Nova sessão ────────────────────────────┐
│ Projeto     [ pagamentos                              ▾ ]           │
│                                                                     │
│ O que fazer                                                         │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ Corrigir o webhook do Stripe que duplica pedidos quando...      │ │
│ │                                                                 │ │
│ └─────────────────────────────────────────────────────────────────┘ │
│   ⌘Enter inicia   ·   @ menciona arquivo   ·   [Prompts salvos ▾]   │
│                                                                     │
│ Agente      [ Claude Code ▾ ]   Provider [ Anthropic ▾ ]            │
│ Modelo      [ sonnet ▾ ]        Permissão [ padrão do agente ▾ ]    │
│                                                                     │
│ ▸ Avançado                                                          │
│   Branch base   [ main ▾ ]   Nome do branch [ bando/corrige-webhook ]│
│   Worktree      (•) novo   ( ) checkout principal                   │
│   Depende de    [ nenhuma ▾ ]   (começa quando a escolhida terminar)│
│   Quantidade    [ 1 ]  (V2: mesma tarefa em N agentes)              │
│                                                                     │
│ Setup: copia .env, roda pnpm install  (definido no projeto)  [editar]│
│                                                                     │
│                                   [Cancelar]   [Iniciar  ⌘Enter]    │
└─────────────────────────────────────────────────────────────────────┘
```

Regras:

- O sheet lembra a última combinação de agente, provider e modelo por projeto.
- O nome do branch é gerado a partir do prompt e pode ser editado. O worktree ganha um nome curto e legível.
- Se o agente escolhido não está instalado, o campo mostra o aviso e um botão "Como instalar" com a dica de instalação do `agents.toml`.
- Também dá para criar sem o sheet: o campo de busca da lateral aceita texto livre e Enter cria uma sessão no projeto selecionado com os padrões (como o campo de despacho do Agent View).

### 5.4 Revisão e diff (aba Diff, ⌘⇧D)

```
┌──────────────────────────┬─────────────────────────────────────────────────────────────┐
│ ARQUIVOS (4)   +42 −7    │ Mostrar: (•) Tudo vs main  ( ) Última rodada  ( ) Não commit.│
│ ☑ src/webhook.ts +30 −5  │ Exibição: [Unificado | Lado a lado]                          │
│ ☑ src/order.ts   +8  −2  │─────────────────────────────────────────────────────────────│
│ ☑ test/webhook.. +4      │ src/webhook.ts                                               │
│ ☐ package.json   +0  −0  │  41   if (event.type === "checkout.completed") {             │
│                          │  42 −   await createOrder(event)                             │
│ COMENTÁRIOS (2)          │  42 +   if (await alreadyProcessed(event.id)) return         │
│ • webhook.ts:42          │  43 +   await createOrder(event)                             │
│ • order.ts:17            │     ┌───────────────────────────────────────────────────┐    │
│                          │     │ Use a chave de idempotência do Stripe aqui.        │    │
│                          │     └───────────────────────────────────────────────────┘    │
│                          │                                                              │
├──────────────────────────┴─────────────────────────────────────────────────────────────┤
│ [Enviar 2 comentários ao agente ⌘Enter]   [Commit…]   [Abrir PR ⌘⇧P]   [Abrir no editor]│
└────────────────────────────────────────────────────────────────────────────────────────┘
```

- Comentário por linha (clique no número da linha ou `c`). "Enviar ao agente" junta todos os comentários num texto e manda para a sessão tmux com `send-keys`.
- "Última rodada" compara com o commit/snapshot do último momento em que a sessão ficou ociosa.
- Commit abre um popover com mensagem sugerida. PR usa `gh pr create`.
- Aba **Checks** (V1 simples): estado do branch (à frente/atrás), PR (rascunho, aberto, merged), CI via `gh pr checks`. O botão Merge fica cinza com o motivo quando há check falhando.

### 5.5 Relatórios (janela própria, ⌘⇧R)

```
┌──────────────────────────────── Relatórios ─────────────────────────────────┐
│ [ Dia | Semana | Mês ]     ◀  03/11 a 09/11/2026  ▶        [Exportar CSV]    │
├──────────────────────────────────────────────────────────────────────────────┤
│  Tempo ativo        Custo estimado       Commits        Sessões             │
│  14h 20min          US$ 38,70            46             23                   │
├──────────────────────────────────────────────────────────────────────────────┤
│ POR PROJETO                 tempo     custo     commits   sessões           │
│ pagamentos       ███████    6h10      US$ 18,20   21        9               │
│ agroway          ████       3h40      US$ 11,05   14        7               │
│ site-institucion ██         2h05      US$  4,90    6        4               │
├──────────────────────────────────────────────────────────────────────────────┤
│ POR AGENTE / MODELO         Claude sonnet 62% · Codex 25% · Gemini 13%      │
├──────────────────────────────────────────────────────────────────────────────┤
│ TEMPO POR DIA   seg ▇▇▇  ter ▇▇▇▇▇  qua ▇▇  qui ▇▇▇▇  sex ▇▇▇  sáb ▇  dom  │
└──────────────────────────────────────────────────────────────────────────────┘
```

- Gráficos com Swift Charts. Clicar numa linha filtra a lista de sessões daquele projeto e período.
- "Tempo ativo" conta só o tempo em que a sessão estava em "trabalhando" ou "esperando você". Mostrar a regra num tooltip, porque o número gera dúvida.
- Custo vem do transcript do agente quando ele informa; quando não informa, a célula fica "—" com tooltip "o agente não informa custo". Não inventar estimativa.

### 5.6 Configurações (janela Settings, ⌘,)

Abas na toolbar da janela, padrão macOS: Geral, Agentes, Providers, Projetos, Notificações, Atalhos.

```
┌──────────────────────────────── Agentes ────────────────────────────────────┐
│ [Geral] [Agentes] [Providers] [Projetos] [Notificações] [Atalhos]           │
├───────────────────────┬─────────────────────────────────────────────────────┤
│ ✓ Claude Code         │ Nome           [ Antigravity            ]          │
│ ✓ Codex               │ Comando        [ agy                    ]          │
│ ✓ Gemini CLI          │ Argumentos     [ --model {model}        ]          │
│ ✓ OpenCode            │ Retomar        [ --resume {session_id}  ]          │
│ ⚠ Antigravity         │ Detecção de estado (•) hooks  ( ) leitura da tela   │
│   não encontrado      │ Teclas p/ encerrar [ C-c C-c ]                      │
│                       │ Providers aceitos  ☑ Google  ☐ OpenRouter  ☐ Local │
│ [+] [−]   [Abrir      │ Modelos sugeridos  [ gemini-3-pro, gemini-3-flash ] │
│  agents.toml]         │                                                     │
│                       │ Status: comando não está no PATH  [Como instalar]   │
│                       │                         [Testar: abre um terminal]  │
└───────────────────────┴─────────────────────────────────────────────────────┘
```

- Providers: lista à esquerda, à direita nome, tipo (Anthropic, OpenAI-compatível, OpenRouter, local), URL base, chave (guardada no Keychain, campo com "Mostrar"), variáveis de ambiente injetadas, botão "Testar conexão".
- "Abrir agents.toml" mostra o arquivo no Finder. A tela e o arquivo editam a mesma coisa; o app recarrega ao detectar mudança no arquivo.
- Projetos: pasta, branch base, script de setup, pasta dos worktrees, prefixo de branch, apagar worktree ao arquivar (com trava se houver mudança não commitada ou push pendente).

### 5.7 Fluxo principal

1. ⌘N, escolhe projeto, escreve o prompt, ⌘Enter.
2. O Bando cria worktree e branch, roda o setup, sobe a sessão tmux com a CLI do agente e o provider. A sessão aparece em "Trabalhando".
3. O usuário cria mais sessões ou volta ao que estava fazendo.
4. Uma sessão pede permissão: ela sobe para "Esperando você", o Dock ganha badge, sai notificação se o usuário não estiver olhando para ela.
5. ⌘J leva à próxima sessão esperando. O usuário responde no terminal (ou pelo peek com Espaço).
6. A sessão termina: vai para "Pronto para revisar". ⌘⇧D abre o diff, comenta, manda de volta ou faz commit e PR.
7. Checks verde, merge. Arquivar a sessão (⌘⌫) apaga o worktree se estiver limpo.

### 5.8 Estados, símbolos e cores

Cor sempre acompanhada de forma diferente, para quem não distingue cores (HIG de acessibilidade). Cores do sistema (`Color.orange` etc.), que se ajustam a claro, escuro e alto contraste.

| Estado | Símbolo (SF Symbol sugerido) | Cor | Quando |
|---|---|---|---|
| Trabalhando | círculo girando (`ProgressView` pequeno) ou `circle.dotted` animado | azul do sistema (accent) | hook de início de turno ou saída na tela |
| Esperando você | `exclamationmark.circle.fill` ou losango cheio | laranja | hook de permissão ou notificação |
| Pronto para revisar | `checkmark.circle.fill` | verde | turno terminou e há mudanças não revisadas |
| Ocioso | `circle` vazio | cinza secundário | turno terminou sem mudança nova |
| Erro | `xmark.octagon.fill` | vermelho | processo saiu com erro |
| Parado | `stop.circle` | cinza terciário | tmux vivo sem o agente, ou parado pelo usuário |
| Na fila (dependência) | `clock` | cinza secundário | esperando outra sessão |

PR, numa bolinha separada ao lado do número: amarelo (checks rodando ou revisão pendente), verde (ok), vermelho (falhou), roxo (merged), cinza (rascunho). Mesmo esquema do Agent View.

### 5.9 Atalhos de teclado

Seguem os atalhos do sistema onde existem e repetem os do mercado onde há consenso.

| Atalho | Ação | Origem |
|---|---|---|
| ⌘N | Nova sessão | Conductor, Claude Code desktop, Zed |
| ⌘⇧N | Novo projeto | inferência |
| ⌘K | Paleta de comandos | Conductor, Sculptor, crystl |
| ⌘J | Próxima sessão esperando você | inferência (não achei padrão) |
| ⌘1 a ⌘9 | Ir para a sessão N da lista | Supacode usa ⌃1-9 |
| ⌃Tab / ⌃⇧Tab | Sessão anterior/seguinte por uso recente | Claude Code desktop, Zed |
| ⌘⇧D | Diff | Conductor, Claude Code desktop |
| ⌘⇧P | Abrir PR | Conductor |
| ⌘⇧K | Commit | inferência |
| ⌘⇧R | Relatórios | inferência |
| ⌘F | Buscar sessões | sistema |
| ⌃⌘S | Mostrar/ocultar lateral | sistema |
| ⌥⌘I | Mostrar/ocultar inspector | sistema |
| ⌘, | Configurações | sistema |
| ⌘/ | Lista de atalhos | Conductor, Claude Code desktop |
| ⌘. | Interromper o agente (envia as teclas de parada configuradas) | convenção macOS de "cancelar" |
| ⌘⌫ | Arquivar sessão | inferência |
| Espaço (com foco na lista) | Peek da sessão | Agent View, Quick Look |
| ⌘Enter | Enviar (nova sessão, comentários do diff) | Claude Code desktop |

Cuidado: com o foco no terminal, toda tecla sem ⌘ vai para o agente. Atalhos do app usam ⌘ para não brigar com as CLIs (que usam ⌃ e Esc).

### 5.10 Paleta de comandos (⌘K)

- Uma lista só com busca difusa: sessões (pelo nome, branch e prompt), projetos, ações ("Nova sessão em pagamentos", "Abrir PR", "Parar todas as sessões ociosas"), configurações.
- Prefixos: `>` só ações, `@` só sessões, `#` projetos.
- Mostra o atalho de cada ação à direita, para ensinar.
- Texto que não casa com nada vira a opção "Nova sessão com este prompt".

### 5.11 Notificações

- `UNUserNotificationCenter`, com ações na própria notificação: "Abrir", e para permissão simples "Permitir" e "Negar" (V2, depende de mapear a resposta para teclas da CLI).
- Dispara só quando a sessão não está visível ou o app está em segundo plano (regra do Claude Code desktop).
- Três tipos, como no Warp: precisa de você, terminou, erro. Cada tipo liga/desliga separadamente, com som opcional.
- Agrupar por projeto (`threadIdentifier`) para não encher a Central de Notificações.
- Badge no Dock com o número de sessões esperando você (Paradev faz isso).
- "Não incomodar por 1 hora" no menu do app.
- MenuBarExtra (V2): ícone na barra de menus com os contadores e a lista de quem espera, para quem trabalha com a janela fechada.

### 5.12 Primeira versão e depois

**V1**

- Janela principal com lateral (modos por estado e por projeto), terminal, inspector, barra de status.
- Nova sessão em sheet com projeto, prompt, agente, provider, modelo, branch, worktree, dependência.
- Estados com hooks (Claude, Codex, Gemini) e leitura de tela como alternativa; tabela de estados da seção 5.8.
- Diff com lista de arquivos, unificado e lado a lado, "tudo vs main" e "não commitado"; comentário por linha enviado ao agente; commit; abrir PR com `gh`.
- Notificações do sistema e badge no Dock.
- Paleta ⌘K, atalhos da tabela, ⌘/ com a lista.
- Settings com Agentes, Providers (chave no Keychain), Projetos (setup), Notificações.
- Relatórios dia/semana/mês com tempo, custo (quando o agente informa) e commits por projeto.
- Busca de sessões, incluindo arquivadas.
- Importar sessões tmux existentes do Bando ao abrir (o app pode fechar e as sessões continuam).

**Depois**

- "Última rodada" no diff (precisa de snapshot por turno).
- Aba Checks completa com comentários do GitHub e bloqueio de merge.
- Peek com resposta rápida e ações de permissão na notificação.
- Grade de 2 a 4 terminais lado a lado.
- Mesma tarefa em N agentes com comparação de diffs (Emdash, Cursor, Uzi).
- Badge de arquivo tocado fora do worktree (crystl).
- Resumo do que aconteceu na ausência (Agent View).
- MenuBarExtra.
- Integração com Linear/GitHub Issues como origem da sessão.
- Atalhos remapeáveis.
- Sessões remotas por SSH.
