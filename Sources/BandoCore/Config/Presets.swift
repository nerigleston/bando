// Gerado por scripts/gen-presets.py a partir de catalog/. Não edite à mão.

/// Presets embutidos no binário. Os arquivos do usuário em `~/.config/bando/`
/// sobrescrevem campo a campo; um agente ou provider novo só precisa existir lá.
public enum Presets {
    public static let agents = ###"""
    # Catálogo de agentes do Bando.
    #
    # Fonte única: o binário embute este arquivo (scripts/gen-presets.py) e o
    # catálogo remoto assinado é publicado a partir dele. Personalizações do
    # usuário ficam em ~/.config/bando/agents.toml e vencem estas entradas.
    #
    # Campo extra do Bando além dos da pesquisa: fresh = argumentos usados só ao
    # abrir sessão nova (não em resume/continue).

    # Mapeamento de CLIs de agentes de código para o Bando
    # Pesquisado em 09/11/2026 (docs oficiais, READMEs, código-fonte no GitHub, --help local quando instalado).
    #
    # Convenções deste arquivo:
    # - Ordem do argv no Bando: cmd, args, args do provider, model, resume|continue, prompt.
    #   Por isso subcomandos fixos (goose session, kiro-cli chat, acli rovodev run) vão em `args`.
    # - status = "hooks" quando o agente tem evento de fim de turno documentado. O comentário diz
    #   se também há evento de permissão ("waiting"). Sem permissão, o Bando só sabe "terminou".
    # - status = "silence" quando não há hooks nem textos de tela confirmados em doc/código.
    # - Campos sem fonte confiável foram omitidos.

    # ---------------------------------------------------------------------------
    # Já conferidos localmente (09/11/2026): sem mudança nas flags.
    # ---------------------------------------------------------------------------

    # Fonte: claude --help (2.1.319) | verificado: sim
    # Hooks: ~/.claude/settings.json e .claude/settings(.local).json; Stop, Notification, PermissionRequest
    # Providers: login próprio; ANTHROPIC_API_KEY; ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN (OpenRouter, z.ai etc.); Bedrock/Vertex por env
    [agents.claude]
    name     = "Claude Code"
    cmd      = "claude"
    assign_id = ["--session-id", "{new_id}"]
    mcp       = "claude"
    fork      = ["--resume", "{native_id}", "--fork-session"]
    # Perguntas que os hooks não avisam (confiança na pasta de cada worktree novo).
    waiting  = 'trust this folder|Do you trust the files'
    idle_after = 2
    prompt   = ["{prompt}"]
    resume   = ["--resume", "{native_id}"]
    continue = ["--continue"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "claude"
    install  = "curl -fsSL https://claude.ai/install.sh | bash"
    update   = "claude update"

    # Fonte: codex --help (0.163.0) | verificado: sim
    # Hooks: já implementado no Bando como "codex"
    # Providers: login ChatGPT; OPENAI_API_KEY; model_providers em ~/.codex/config.toml
    # Atenção: o Bando monta `codex --model X resume <id>`. A flag -m também existe em `codex resume`;
    # conferir se o -m antes do subcomando é aplicado ao resume.
    # Título da sessão: pergunta única, sem ferramentas nem sessão salva, teto de gasto.
    title       = ["-p", "--output-format", "text", "--tools", "", "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config", "--max-budget-usd", "0.02", "--model", "{model}", "{prompt}"]
    title_model = "claude-haiku-4-5"

    [agents.codex]
    name     = "Codex"
    mcp      = "codex"
    cmd      = "codex"
    prompt   = ["{prompt}"]
    resume   = ["resume", "{native_id}"]
    continue = ["resume", "--last"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "codex"
    # Observado no Codex 0.163 (09/11/2026): pergunta de confiança e menus de escolha.
    waiting  = 'Trust this folder\?|enter continue · esc|enter confirm · esc|Update available'
    install  = "curl -fsSL https://chatgpt.com/codex/install.sh | sh"

    # Fonte: gemini --help (0.64.0; npm latest 0.67.0) | verificado: sim
    # Hooks: já implementado no Bando como "gemini"
    # Providers: login Google; GEMINI_API_KEY; Vertex (GOOGLE_API_KEY/GOOGLE_CLOUD_PROJECT)
    # Atenção: o --help só cita "latest" ou índice numérico em --resume; confirmar que aceita UUID.
    # Google anunciou em 05/2026 a transição do Gemini CLI para o Antigravity CLI (agy).
    # Título da sessão: `codex exec` só leitura; a resposta sai na última linha.
    title       = ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "-m", "{model}", "{prompt}"]

    [agents.gemini]
    name     = "Gemini CLI"
    cmd      = "gemini"
    prompt   = ["--prompt-interactive", "{prompt}"]
    resume   = ["--resume", "{native_id}"]
    continue = ["--resume", "latest"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "gemini"
    # Observado no Gemini CLI 0.64 (09/11/2026): pergunta de confiança e tela de login.
    # Desde 2026 o Google não aceita mais o Gemini CLI com conta pessoal no Code
    # Assist (pede migrar para o Antigravity): use chave de API ou Vertex AI.
    # Sem MCP pelo Bando: as settings de sistema que o Gemini aceitaria por
    # variável exigem arquivo e pasta do root.
    waiting  = 'Do you trust the files in this folder\?|\(Use Enter to select\)|\(y/n\)'
    install  = "npm i -g @google/gemini-cli"
    update   = "npm i -g @google/gemini-cli@latest"

    # Fonte: agy --help (1.5.3) + https://antigravity.google/docs/hooks?tab=cli | verificado: sim
    # Hooks: .agents/hooks.json (workspace) e ~/.gemini/config/hooks.json (global; ~/.gemini/antigravity-cli/settings.json NÃO é lido);
    #        eventos SessionStart, PreToolUse, PostToolUse, PreInvocation, PostInvocation, Stop. Sem evento de permissão.
    #        Relatos de hooks carregados que nunca disparam nas versões 1.2.1/1.2.2. Mantido em "output" por isso.
    # Providers: login Google
    # Título da sessão: modo não interativo.
    title       = ["-p", "{prompt}", "-m", "{model}"]

    [agents.agy]
    name       = "Antigravity"
    cmd        = "agy"
    prompt     = ["--prompt-interactive", "{prompt}"]
    resume     = ["--conversation", "{native_id}"]
    continue   = ["--continue"]
    model      = ["--model", "{model}"]
    status     = "output"
    # Observado no agy 1.5.3 (09/11/2026): pergunta de confiança e menus de escolha
    # terminam com "↑/↓ Navigate · enter Confirm".
    waiting    = 'Do you trust the contents|↑/↓ Navigate · enter Confirm|\(y/n\)'
    idle_after = 4

    # Fonte: opencode --help (v2.2.6) + https://opencode.ai/docs/build/plugins.md | verificado: sim (flags)
    # Hooks: v2 tem plugins TS em .opencode/plugins/ com API de permissões e eventos, mas não achei um evento
    #        simples de "turno terminou" documentado. O servidor local também expõe API (opencode api/serve).
    # Providers: `opencode auth`; opencode.json(c) "provider"; variáveis *_API_KEY de cada provider
    # Atenção: o pacote npm opencode-ai está em 1.19.5 (v1, flags diferentes, tinha --model). Instalar pelo script.
    [agents.opencode]
    name     = "OpenCode"
    mcp      = "opencode"
    cmd      = "opencode"
    prompt   = ["--prompt", "{prompt}"]
    resume   = ["--session", "{native_id}"]
    continue = ["--continue"]
    status   = "silence"
    install  = "curl -fsSL https://opencode.ai/install | bash"
    update   = "opencode upgrade"

    # Fonte: https://cursor.com/docs/cli/using + /docs/cli/reference/parameters + /docs/agent/hooks | verificado: sim
    # Hooks: ~/.cursor/hooks.json e .cursor/hooks.json; evento `stop` (status completed|aborted|error),
    #        beforeShellExecution/preToolUse podem pedir confirmação, mas não há evento "esperando permissão".
    #        Cursor também carrega hooks de terceiros (Claude Code) se habilitado.
    # Providers: só conta Cursor; --model escolhe entre os modelos da conta (`agent models`)
    # Atenção: --resume [chatId] tem valor opcional; se der problema, usar "--resume={native_id}".
    # Título da sessão: `opencode run`; a resposta sai na última linha.
    title       = ["run", "-m", "{model}", "{prompt}"]

    [agents.cursor]
    name     = "Cursor"
    cmd      = "agent"
    prompt   = ["{prompt}"]
    resume   = ["--resume", "{native_id}"]
    continue = ["--continue"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "cursor"
    install  = "curl https://cursor.com/install -fsS | bash"

    # Fonte: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/cli.md + extensions.md | verificado: sim
    # Hooks: extensões TS em ~/.pi/agent/extensions/*.ts ou .pi/extensions/ (projeto precisa ser confiável);
    #        eventos agent_end/turn_end (fim) e ui_prompt_start/ui_prompt_end ("waiting for user" de diálogos).
    #        O Pi não tem prompts de permissão próprios por padrão.
    # Providers: /login dentro do Pi; `pi auth login <provider>`; --provider, --api-key; models-configuration.md para custom
    # Mensagens posicionais com stdin/stdout em TTY abrem o TUI (não saem). --print força one-shot.
    [agents.pi]
    name     = "Pi"
    cmd      = "pi"
    prompt   = ["{prompt}"]
    resume   = ["--session", "{native_id}"]
    continue = ["--continue"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "pi"
    install  = "curl -fsSL https://pi.dev/install.sh | sh"

    # ---------------------------------------------------------------------------
    # Novos
    # ---------------------------------------------------------------------------

    # Fonte: https://github.com/QwenLM/qwen-code (packages/cli/src/config/top-level-options.ts, docs/users/features/hooks.md) | verificado: sim
    # Hooks: ~/.qwen/settings.json ou .qwen/settings.json ("hooks"); Stop, StopFailure, Notification
    #        (permission_prompt, idle_prompt), PermissionRequest. Hooks de projeto só rodam após aprovação ou folder trust.
    # Providers: /auth (Qwen account); modelProviders em settings.json com envKey (OPENAI_API_KEY, DASHSCOPE_API_KEY,
    #            ANTHROPIC/gemini/vertex); flags --auth-type, --openai-api-key, --openai-base-url
    [agents.qwen]
    name     = "Qwen Code"
    cmd      = "qwen"
    prompt   = ["--prompt-interactive", "{prompt}"]
    resume   = ["--resume", "{native_id}"]
    continue = ["--continue"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "qwen"
    install  = "npm install -g @qwen-code/qwen-code@latest"

    # Fonte: https://github.com/charmbracelet/crush (internal/cmd/root.go, docs/hooks/README.md) | verificado: sim
    # Hooks: crushrc/.crushrc (global ~/.config/crush/crushrc ou projeto) com `hook add <Evento> --command ...`;
    #        TurnStart, TurnEnd, Interrupt, StopFailure, PermissionRequest, PermissionResult. Payload JSON compatível
    #        com Claude (hook_event_name). Comando relativo resolve contra o cwd, não contra o arquivo.
    # Providers: Hyper (padrão); ANTHROPIC_API_KEY, OPENAI_API_KEY etc.; `provider add ... --type responses|completions|messages`
    #            no crushrc; crush.json "providers" (deprecado)
    # Sem prompt inicial interativo (`crush run` é headless) e sem flag de modelo (picker ctrl+l).
    [agents.crush]
    name       = "Crush"
    cmd        = "crush"
    prompt_via = "keys"
    resume     = ["--session", "{native_id}"]
    continue   = ["--continue"]
    status     = "hooks"
    hooks      = "crush"
    install    = "brew install charmbracelet/tap/crush"
    update   = "brew upgrade charmbracelet/tap/crush"

    # Fonte: https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference + hooks-configuration | verificado: sim
    # Hooks: ~/.copilot/hooks/*.json, ~/.copilot/settings.json ("hooks"), .github/hooks/*.json, .github/copilot/settings(.local).json;
    #        agentStop (fim de turno), notification (agent completion/idle, permission prompts), permissionRequest.
    #        Também lê .claude/settings.json e .claude/settings.local.json do repositório.
    # Providers: assinatura Copilot (COPILOT_GITHUB_TOKEN); BYOK por COPILOT_PROVIDERS_CONFIG, COPILOT_PROVIDER_API_KEY(_COMMAND),
    #            COPILOT_PROVIDER_HEADERS; COPILOT_MODEL
    # --resume tem valor opcional: usar a forma com "=".
    [agents.copilot]
    name     = "GitHub Copilot CLI"
    cmd      = "copilot"
    prompt   = ["-i", "{prompt}"]
    resume   = ["--resume={native_id}"]
    continue = ["--continue"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "copilot"
    install  = "brew install copilot-cli"
    update   = "brew upgrade copilot-cli"

    # Fonte: https://docs.factory.com/reference/cli-reference + /reference/hooks-reference | verificado: sim
    # Hooks: ~/.factory/hooks.json e .factory/hooks.json (ou "hooks" em settings.json); Stop, Notification
    #        (permission_prompt, idle_prompt, elicitation_dialog), SessionStart/End etc. Cancelamento gera Notification, não Stop.
    # Providers: conta Factory; BYOK em "Custom Models" (docs/model-independence/byok)
    # -m/--model aparece na tabela geral, mas o único exemplo é `droid exec`; não confirmado no modo interativo (omitido).
    [agents.droid]
    name     = "Factory Droid"
    cmd      = "droid"
    prompt   = ["{prompt}"]
    resume   = ["--resume", "{native_id}"]
    continue = ["--resume"]
    status   = "hooks"
    hooks    = "droid"
    install  = "curl -fsSL https://app.factory.ai/cli | sh"

    # Fonte: https://ampcode.com/docs/cli, /docs/threads, /docs/cli/settings, /docs/plugin-api | verificado: parcial
    # Hooks: plugins TS (executados com Bun) em ~/.config/amp/plugins/ ou .amp/plugins/; amp.on('agent.start'|'agent.end'|
    #        'tool.call'|'tool.result'|'session.start'). Sem evento de permissão. amp.notifications.enabled só toca som/bell.
    # Providers: só conta Amp (modelos roteados pelo Amp; modo Claude Code usa assinatura Claude vinculada)
    # Prompt inicial só por stdin (`echo x | amp`) ou digitado; --mode/--features só documentados com -x (execute).
    # Não achei forma documentada de "continuar a última thread".
    [agents.amp]
    name       = "Amp"
    cmd        = "amp"
    prompt_via = "keys"
    resume     = ["threads", "continue", "{native_id}"]
    status     = "hooks"
    hooks      = "amp"
    install    = "curl -fsSL https://ampcode.com/install.sh | bash"

    # Fonte: https://github.com/MoonshotAI/kimi-code docs/en/reference/kimi-command.md + customization/hooks.md | verificado: sim
    # Hooks: SÓ em ~/.kimi-code/config.toml ([[hooks]]) e plugins locais; não existe hook de projeto.
    #        Stop, StopFailure, Interrupt, PermissionRequest, PermissionResult, TurnStarted, Notification (tarefas de fundo).
    # Providers: [providers.<nome>] em config.toml, type kimi|anthropic|openai|openai-responses, api_key ou api_key_env
    #            (KIMI_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY). --model recebe um alias do config.
    # Kimi CLI (Python, `kimi-cli`) foi arquivado; este é o sucessor Kimi Code (mesmo binário `kimi`).
    # Sem prompt inicial interativo (-p/--prompt é não interativo).
    [agents.kimi]
    name       = "Kimi Code"
    cmd        = "kimi"
    prompt_via = "keys"
    resume     = ["--session", "{native_id}"]
    continue   = ["--continue"]
    model      = ["--model", "{model}"]
    status     = "hooks"
    hooks      = "kimi"
    install    = "curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash"

    # Fonte: https://kilo.ai/docs/code-with-ai/platforms/cli + Kilo-Org/kilocode packages/opencode/src/cli/cmd/tui.ts | verificado: sim (flags)
    # Hooks: fork do OpenCode com sistema de plugins; nenhum evento de fim de turno documentado na página da CLI.
    #        ~/.config/kilo/tui.jsonc tem "notifications" (só alerta visual/sonoro).
    # Providers: `kilo auth`; Kilo Gateway (500+ modelos); kilo.jsonc; --model provider/model
    # Doc: --continue "não pode ser usado com prompt". Evitar continuar + prompt no Bando.
    [agents.kilo]
    name     = "Kilo Code"
    cmd      = "kilo"
    prompt   = ["--prompt", "{prompt}"]
    resume   = ["--session", "{native_id}"]
    continue = ["--continue"]
    model    = ["--model", "{model}"]
    status   = "silence"
    install  = "npm install -g @kilocode/cli"
    update   = "npm install -g @kilocode/cli@latest"

    # Fonte: https://docs.cline.bot/cli/cli-reference.md + https://unpkg.com/cline@latest/README.md (3.0.74) + docs.cline.bot/sdk/plugins.md | verificado: sim (flags), parcial (hooks)
    # Hooks: plugins TS (~/.cline ou projeto) com beforeRun/afterRun/beforeTool/afterTool/onEvent; --hooks-dir (padrão
    #        ~/.cline/hooks) ou CLINE_HOOKS_DIR para hooks de script, mas a lista de eventos atual não está documentada.
    #        Sem evento de permissão confirmado.
    # Providers: `cline auth <provider>`; -P/--provider, -k/--key, -m/--model; OAuth cline/openai-codex/oca
    # ARMADILHA: `cline "prompt"` sem -i roda UM turno, com auto-approve ligado por padrão, e sai. Por isso -i fica em args.
    # Sem --continue na versão 3.x (só --id).
    [agents.cline]
    name     = "Cline"
    cmd      = "cline"
    args     = ["-i"]
    prompt   = ["{prompt}"]
    resume   = ["--id", "{native_id}"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "cline"
    install  = "npm install -g cline"
    update   = "npm install -g cline@latest"

    # Fonte: continuedev/continue extensions/cli/src/index.ts + shared-options.ts + README | verificado: sim
    # Hooks: nenhum encontrado.
    # Providers: config.yaml do Continue (--config <path>) ou Continue Hub (--org); --model recebe slug do Hub
    # Prompt posicional abre o TUI com a mensagem; -p/--print é headless. --resume retoma a última sessão
    # DESTE terminal; não há resume por ID (só --fork <id>, que cria sessão nova).
    [agents.cn]
    name     = "Continue CLI"
    cmd      = "cn"
    prompt   = ["{prompt}"]
    continue = ["--resume"]
    model    = ["--model", "{model}"]
    status   = "silence"
    install  = "npm i -g @continuedev/cli"
    update   = "npm i -g @continuedev/cli@latest"

    # Fonte: https://aider.chat/docs/config/options.html + aider/io.py, aider/waiting.py | verificado: sim
    # Hooks: não tem; mas --notifications-command "<cmd>" roda um comando quando a resposta fica pronta (fim de turno).
    #        Dá para usar como hook de "terminou" via args. Não avisa permissão.
    # Providers: --api-key provider=KEY, --openai-api-base, --set-env, AIDER_* env, .aider.conf.yml; LiteLLM por baixo
    # --message/-m roda um turno e sai; argumentos posicionais são arquivos. Último release no PyPI: 0.86.2 (12/02/2026).
    [agents.aider]
    name       = "Aider"
    cmd        = "aider"
    prompt_via = "keys"
    continue   = ["--restore-chat-history"]
    model      = ["--model", "{model}"]
    status     = "output"
    busy       = 'Waiting for'
    waiting    = '\(Y\)es/\(N\)o'
    idle_after = 4
    install    = "python -m pip install aider-install && aider-install"

    # Fonte: https://github.com/block/goose documentation/docs/guides/goose-cli-commands.md + crates/goose-cli/src/cli.rs
    #        + https://goose-docs.ai/docs/guides/context-engineering/hooks/ | verificado: sim
    # Hooks: plugins com hooks/hooks.json em ~/.agents/plugins/<nome>/ ou <projeto>/.agents/plugins/<nome>/;
    #        Stop, SessionStart/End, UserPromptSubmit, PreToolUse... Sem Notification nem PermissionRequest.
    # Providers: GOOSE_PROVIDER/GOOSE_MODEL, `goose configure`, --provider/--model em session e run
    # `goose session` não aceita prompt inicial; `goose run -s -t "<prompt>"` continua interativo, mas é outro subcomando.
    # Repositório migrou para aaif-goose/goose.
    [agents.goose]
    name       = "Goose"
    cmd        = "goose"
    args       = ["session"]
    prompt_via = "keys"
    resume     = ["--resume", "--session-id", "{native_id}"]
    continue   = ["--resume"]
    model      = ["--model", "{model}"]
    status     = "hooks"
    hooks      = "goose"
    install    = "brew install block-goose-cli"
    update   = "brew upgrade block-goose-cli"

    # Fonte: https://docs.augmentcode.com/cli/reference + /cli/hooks | verificado: sim
    # Hooks: ~/.augment/settings.json, .augment/settings.json, .augment/settings.local.json, /etc/augment/settings.json;
    #        Stop (fim, inclusive interrupção), Notification (info/warning/error), PromptSubmit, Pre/PostToolUse.
    #        Sem evento de permissão (PreToolUse só nega).
    # Providers: só conta Augment; --model "name[:effort]"
    # Resume por ID não documentado: --resume abre seletor, --session recebe caminho de arquivo.
    [agents.auggie]
    name     = "Augment (Auggie)"
    cmd      = "auggie"
    prompt   = ["{prompt}"]
    continue = ["--continue"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "auggie"
    install  = "npm install -g @augmentcode/auggie"
    update   = "npm install -g @augmentcode/auggie@latest"

    # Fonte: https://kiro.dev/docs/reference/cli-commands/ + https://kiro.dev/docs/hooks/ | verificado: sim
    # Hooks: .kiro/hooks/<id>.json (projeto) e ~/.kiro/hooks/ (global, só harness V3); trigger "Stop", PreToolUse,
    #        PostToolUse, gatilhos de arquivo. Sem evento de permissão encontrado.
    # Providers: conta Kiro/AWS (Builder ID ou IAM Identity Center); --model sobrescreve chat.defaultModel
    # Sucessor do Amazon Q Developer CLI. V2 e V3 têm formatos de hook diferentes.
    [agents.kiro]
    name     = "Kiro CLI"
    cmd      = "kiro-cli"
    args     = ["chat"]
    prompt   = ["{prompt}"]
    resume   = ["--resume-id", "{native_id}"]
    continue = ["--resume"]
    model    = ["--model", "{model}"]
    status   = "hooks"
    hooks    = "kiro"
    install  = "curl -fsSL https://cli.kiro.dev/install | bash"

    # Fonte: https://support.atlassian.com/rovo/docs/rovo-dev-cli-commands/ + blog "Streamlining your Rovo Dev CLI workflow with event hooks" | verificado: parcial
    # Hooks: configurados por /hooks, gravados em "eventHooks" de ~/.rovodev/config.yml. Evento confirmado: on_tool_permission.
    #        O blog cita também "terminou de gerar resposta" e "erro", mas sem o nome exato do evento.
    # Providers: só conta Atlassian (acli rovodev auth login)
    # `acli rovodev run "<instrução>"` é NÃO interativo; por isso keys.
    [agents.rovodev]
    name       = "Rovo Dev"
    cmd        = "acli"
    args       = ["rovodev", "run"]
    prompt_via = "keys"
    resume     = ["--restore", "{native_id}"]
    continue   = ["--restore"]
    status     = "hooks"
    hooks      = "rovodev"
    install    = "brew tap atlassian/homebrew-acli && brew install acli"
    update   = "brew upgrade acli"

    # Fonte: https://github.com/mistralai/mistral-vibe README (3.1.0, 04/11/2026) | verificado: sim
    # Hooks: ~/.vibe/hooks.toml e <projeto>/.vibe/hooks.toml ([[hooks]], type = pre_tool | post_tool | post_agent).
    #        post_agent = fim de turno sem tool calls pendentes. pre_tool roda ANTES do prompt de permissão, então não indica espera.
    # Providers: MISTRAL_API_KEY; [providers] em ~/.vibe/config.toml com api_key_env / api_key_env_var
    # --model ALIAS só está documentado no modo programático (-p) e para sessão nova; omitido.
    # --continue usa a "chave do terminal" (VIBE_TERMINAL_KEY); em panes novos do tmux cai na sessão mais recente da pasta.
    [agents.vibe]
    name     = "Mistral Vibe"
    cmd      = "vibe"
    prompt   = ["{prompt}"]
    resume   = ["--resume", "{native_id}"]
    continue = ["--continue"]
    status   = "hooks"
    hooks    = "vibe"
    install  = "curl -LsSf https://mistral.ai/vibe/install.sh | bash"

    # Fonte: https://docs.letta.com/platform/cli/reference/index.md + letta-ai/letta-code src/hooks/types.ts, loader.ts | verificado: sim
    # Hooks (compatíveis com Claude Code): ~/.letta/settings.json, .letta/settings.json, .letta/settings.local.json;
    #          Stop, Notification, PermissionRequest, UserPromptSubmit, SessionStart/End...
    # Providers: Letta Cloud ou servidor Letta; --model sonnet|auto|gpt-5-codex...; doc avisa que --model é instável ao retomar
    # ARMADILHA: `letta` sem flags RETOMA a conversa padrão do agente. Para sessões paralelas a doc manda usar --new.
    #            Com a ordem de argv do Bando não dá para pôr --new só no modo "novo"; avaliar suporte.
    [agents.letta]
    name       = "Letta Code"
    cmd        = "letta"
    fresh      = ["--new"]       # sem --new, letta retoma a conversa padrão do agente
    prompt_via = "keys"
    resume     = ["--conversation", "{native_id}"]
    model      = ["--model", "{model}"]
    status     = "hooks"
    hooks      = "letta"
    install    = "npm install -g @letta-ai/letta-code"
    update   = "npm install -g @letta-ai/letta-code@latest"

    # Fonte: https://docs.x.ai/build/cli/reference.md + /build/features/hooks.md | verificado: sim
    # Hooks: ~/.grok/hooks/*.json e <projeto>/.grok/hooks/*.json (projeto exige /hooks-trust ou --trust); também lê
    #        .claude/settings.json e .cursor/hooks.json. Stop, StopFailure, Notification, PermissionDenied (não há PermissionRequest).
    #        TOML: [[hooks.<Evento>]] em ~/.grok/config.toml.
    # Providers: assinatura SuperGrok/X Premium+ ou chave de API xAI; ~/.grok/config.toml
    # Prompt inicial interativo não documentado (-p é headless).
    # ARMADILHA: o grok-cli comunitário (superagent-ai) instala o mesmo binário `grok`.
    [agents.grok]
    name       = "Grok Build"
    cmd        = "grok"
    prompt_via = "keys"
    resume     = ["--resume", "{native_id}"]
    continue   = ["--continue"]
    model      = ["--model", "{model}"]
    status     = "hooks"
    hooks      = "grok"
    install    = "curl -fsSL https://x.ai/cli/install.sh | bash"

    # Fonte: https://junie.jetbrains.com/docs/parameters.html | verificado: sim (flags), parcial (install)
    # Hooks: não encontrados na doc oficial.
    # Providers: JUNIE_API_KEY (conta JetBrains) ou BYOK com --provider e --anthropic-api-key/--openai-api-key/
    #            --google-api-key/--grok-api-key/--openrouter-api-key/--litellm-url
    # --prompt abre o TUI e envia o prompt (sessão continua interativa); --task/posicional é outra coisa.
    [agents.junie]
    name     = "Junie"
    cmd      = "junie"
    prompt   = ["--prompt", "{prompt}"]
    resume   = ["--session-id", "{native_id}"]
    continue = ["--resume"]
    model    = ["--model", "{model}"]
    status   = "silence"
    install  = "curl -fsSL https://junie.jetbrains.com/install.sh | bash"

    # Fonte: https://docs.openhands.dev/openhands/usage/cli/command-reference + OpenHands-CLI README | verificado: sim
    # Hooks: não encontrados.
    # Providers: ~/.openhands/ (configurado no primeiro uso); LLM_API_KEY, LLM_MODEL, LLM_BASE_URL só valem com --override-with-envs
    # Sem flag de modelo. -t/--task semeia a conversa e continua interativo (headless só com --headless).
    # AVISO: o projeto diz "no longer actively maintained" e recomenda o Agent Canvas.
    [agents.openhands]
    name     = "OpenHands CLI"
    cmd      = "openhands"
    prompt   = ["--task", "{prompt}"]
    resume   = ["--resume", "{native_id}"]
    continue = ["--resume", "--last"]
    status   = "silence"
    install  = "uv tool install openhands --python 3.12"
    update   = "uv tool upgrade openhands"

    # Fonte: https://github.com/antinomyhq/forge README | verificado: sim
    # Hooks: não encontrados.
    # Providers: `forge provider login`; troca de modelo com :model dentro da sessão (sem flag)
    # -p/--prompt é one-shot. Não há "continuar última".
    # ARMADILHA: conflita com o `forge` do Foundry (nesta máquina: ~/.foundry/bin/forge).
    # Desativado por padrão: o binário "forge" do Foundry (Ethereum) tem o mesmo
    # nome e faria o Bando achar que o Forge Code está instalado. Para usar:
    #   [agents.forge]
    #   enabled = true
    [agents.forge]
    name       = "Forge Code"
    cmd        = "forge"
    enabled    = false
    prompt_via = "keys"
    resume     = ["--conversation-id", "{native_id}"]
    status     = "silence"
    install    = "curl -fsSL https://forgecode.dev/cli | sh"

    # Fonte: https://github.com/CodebuffAI/codebuff README (agora "Freebuff") | verificado: parcial
    # Hooks: não encontrados. Providers: catálogo próprio, sem chave (financiado por anúncios em texto).
    # Nenhuma flag documentada no README; só o binário e a instalação.
    [agents.freebuff]
    name       = "Freebuff (ex-Codebuff)"
    cmd        = "freebuff"
    prompt_via = "keys"
    status     = "silence"
    install    = "npm install -g freebuff"
    update   = "npm install -g freebuff@latest"

    # ---------------------------------------------------------------------------
    # Pesquisados e descartados
    # ---------------------------------------------------------------------------
    # - iFlow CLI: encerrado em 17/04/2026 (aviso no README do iflow-ai/iflow-cli).
    # - Kimi CLI (Python, MoonshotAI/kimi-cli): arquivado; substituído pelo Kimi Code (mapeado acima como `kimi`).
    # - Plandex: último push em 03/10/2025; Plandex Cloud encerrado; exige servidor próprio. REPL sem sessão por ID.
    # - Warp: o agente roda dentro do app Warp; o `oz` CLI é "legacy" e voltado a execução headless/nuvem (oz agent run/run-cloud).
    # - Trae: `traecli` oficial é só para TRAE Enterprise; o trae-agent open source (`trae-cli interactive`) é projeto de
    #   pesquisa sem push desde 05/02/2026.
    # - Google Jules (`jules`): tarefas assíncronas na nuvem, não roda o agente no terminal local.
    # - grok-cli comunitário (superagent-ai): tem hooks compatíveis com Claude (~/.grok/user-settings.json) e
    #   `grok -s <id>` / `--session latest`, mas usa o mesmo binário `grok` do Grok Build oficial. Preferido o oficial.
    # - Qodo Command (`qodo`): foco em agentes declarativos/webhook; flags interativas de sessão não confirmadas na doc.
    # - Hermes Agent (Nous Research): assistente geral (mensageria, automações), não CLI de código; fontes oficiais não conferidas.
    # - Roo Code: não achei CLI publicada (pacote npm @roo-code/cli inexistente).
    # - Oh My Pi (`omp`): fork do Pi citado em comparativos; não pesquisado a fundo.

    # Shell comum, para sessões sem agente.
    [agents.shell]
    name    = "Terminal"
    cmd     = "$SHELL"
    status  = "none"
    version = []
    """###

    public static let providers = ###"""
    # Catálogo de providers do Bando.
    #
    # Fonte única: o binário embute este arquivo (scripts/gen-presets.py) e o
    # catálogo remoto assinado é publicado a partir dele. Personalizações do
    # usuário ficam em ~/.config/bando/providers.toml e vencem estas entradas.
    #
    # Sem env: a CLI usa o login que já tem (assinatura ou chave própria).
    [providers.default]
    name = "Conta do agente"

    # =============================================================================
    # Bando: mapeamento de providers de modelo (pesquisa de 09/11/2026)
    # =============================================================================
    #
    # Regras gerais confirmadas na documentação atual (valem para todos os blocos):
    #
    # CLAUDE CODE (https://code.claude.com/docs/en/llm-gateway-connect)
    #   - ANTHROPIC_AUTH_TOKEN vai no header "Authorization: Bearer"; ANTHROPIC_API_KEY vai em "x-api-key".
    #   - ANTHROPIC_BASE_URL é a raiz, SEM "/v1": o cliente acrescenta /v1/messages sozinho.
    #   - ANTHROPIC_API_KEY = "" evita que uma chave Anthropic do ambiente tenha precedência
    #     (Vercel e OpenRouter pedem isso explicitamente). Com ANTHROPIC_API_KEY não vazio, o
    #     modo interativo pede aprovação uma vez.
    #   - Modelos: ANTHROPIC_MODEL, ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL,
    #     CLAUDE_CODE_SUBAGENT_MODEL. ANTHROPIC_SMALL_FAST_MODEL está obsoleto (use DEFAULT_HAIKU).
    #   - Sufixo "[1m]" no ID do modelo faz o Claude Code usar janela de 1M; sem ele assume 200K.
    #   - CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1 lista os modelos do gateway no /model.
    #   - Erros 400 por campos beta desconhecidos: CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1.
    #   - Rede restrita: CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1.
    #   - Anthropic diz que não dá suporte a Claude Code com modelos não-Claude via gateway;
    #     os providers abaixo documentam isso por conta própria.
    #
    # CODEX CLI (https://learn.chatgpt.com/docs/config-file/config-reference ; antigo
    #   developers.openai.com/codex/config-reference redireciona para lá)
    #   - wire_api: "`responses` is the only supported value, and it is the default when omitted."
    #     wire_api="chat" NÃO é mais aceito. Provider que só tem /chat/completions não serve
    #     para o Codex atual (por isso vários providers abaixo não têm bloco for.codex).
    #   - Campos: name, base_url, env_key, wire_api, query_params, http_headers,
    #     env_http_headers, requires_openai_auth.
    #   - IDs reservados (não podem ser redefinidos): openai, ollama, lmstudio.
    #     Também há built-ins "amazon-bedrock" (aws.profile, aws.region) e "gcp"
    #     (project_id, location, credential_file; lê GOOGLE_CLOUD_PROJECT / GOOGLE_CLOUD_LOCATION).
    #   - oss_provider = "lmstudio" | "ollama", usado com --oss.
    #   - Codex >= 0.134.0 não lê mais [profiles.<nome>] no config.toml (perfil vira arquivo
    #     ~/.codex/<nome>.config.toml). Não afeta o uso de -c.
    #   - Codex não expande variáveis de ambiente dentro de base_url.
    #
    # OPENCODE: as variáveis vêm do catálogo models.dev (https://models.dev/api.json), que é a
    #   fonte de providers do OpenCode. A página https://opencode.ai/docs/providers/ só documenta
    #   explicitamente OPENROUTER_API_KEY, AWS_*, GOOGLE_VERTEX_*, AZURE_RESOURCE_NAME e os locais.
    #   Por isso os blocos for.opencode de providers só presentes no models.dev ficam "parcial".
    #
    # QWEN CODE (https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/)
    #   - Protocolo OpenAI: OPENAI_API_KEY + OPENAI_BASE_URL + OPENAI_MODEL. Exportar
    #     OPENAI_API_KEY já seleciona a autenticação OpenAI-compatível.
    #   - Protocolo Anthropic: ANTHROPIC_API_KEY + ANTHROPIC_BASE_URL + ANTHROPIC_MODEL.
    #   - Gemini: GEMINI_API_KEY + GEMINI_MODEL.
    #
    # CRUSH (https://github.com/charmbracelet/crush README): só lê chaves por variável; base URL
    #   customizada exige config (crush.json), não variável. Só providers da tabela do README.
    #
    # AIDER (https://aider.chat/docs/llms.html): OpenAI-compatível = OPENAI_API_BASE +
    #   OPENAI_API_KEY e o modelo precisa do prefixo "openai/". Ollama usa prefixo "ollama_chat/",
    #   LM Studio "lm_studio/", OpenRouter "openrouter/". O Bando precisa aplicar o prefixo no -m.
    #
    # GOOSE (https://goose-docs.ai/docs/getting-started/providers): a página lista as variáveis,
    #   mas só mostra o ID de GOOSE_PROVIDER para zai_coding_plan. Os demais IDs (anthropic,
    #   openai, google, ollama, openrouter etc.) são de docs antigas: blocos for.goose = parcial.
    #
    # GEMINI CLI (https://geminicli.com/docs/get-started/authentication): GEMINI_API_KEY, ou
    #   Vertex com GOOGLE_CLOUD_PROJECT + GOOGLE_CLOUD_LOCATION (+ ADC/GOOGLE_APPLICATION_CREDENTIALS
    #   ou GOOGLE_API_KEY). Base customizada: GOOGLE_GEMINI_BASE_URL (doc da Cloudflare).
    #   Só fala o protocolo Gemini; não aponta para OpenAI/Anthropic.
    #
    # Convenções deste arquivo: segredo = "keychain:bando/<id>"; valor do usuário = "env:NOME";
    # "<...>" = valor que o usuário precisa preencher (o Codex não expande variáveis em base_url).
    # =============================================================================


    # =============================================================================
    # 1. LABORATÓRIOS / APIs DIRETAS
    # =============================================================================

    # Fonte: https://code.claude.com/docs/en/llm-gateway-connect ; https://models.dev/api.json ; https://github.com/charmbracelet/crush  | verificado: sim
    [providers.anthropic]
    name   = "Anthropic"
    models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]

    [providers.anthropic.for.claude]
    env = { ANTHROPIC_API_KEY = "keychain:bando/anthropic" }

    [providers.anthropic.for.opencode]
    env = { ANTHROPIC_API_KEY = "keychain:bando/anthropic" }

    [providers.anthropic.for.crush]
    env = { ANTHROPIC_API_KEY = "keychain:bando/anthropic" }

    # parcial: aider/goose pelas docs de provider de cada um (goose: ANTHROPIC_API_KEY confirmado; ID "anthropic" de doc antiga)
    [providers.anthropic.for.aider]
    env = { ANTHROPIC_API_KEY = "keychain:bando/anthropic" }

    [providers.anthropic.for.goose]
    env = { GOOSE_PROVIDER = "anthropic", ANTHROPIC_API_KEY = "keychain:bando/anthropic" }


    # Fonte: https://learn.chatgpt.com/docs/config-file/config-reference ; https://models.dev/api.json  | verificado: sim
    # Codex usa OpenAI nativamente (model_provider padrão = "openai"); basta a chave.
    [providers.openai]
    name   = "OpenAI"
    models = ["gpt-6.1-terra", "gpt-6.1-sol", "gpt-6-astra"]

    [providers.openai.for.codex]
    env = { OPENAI_API_KEY = "keychain:bando/openai" }

    [providers.openai.for.opencode]
    env = { OPENAI_API_KEY = "keychain:bando/openai" }

    [providers.openai.for.crush]
    env = { OPENAI_API_KEY = "keychain:bando/openai" }

    [providers.openai.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/openai", OPENAI_BASE_URL = "https://api.openai.com/v1" }

    [providers.openai.for.aider]
    env = { OPENAI_API_KEY = "keychain:bando/openai" }

    [providers.openai.for.goose]
    env = { GOOSE_PROVIDER = "openai", OPENAI_API_KEY = "keychain:bando/openai" }


    # Fonte: https://geminicli.com/docs/get-started/authentication ; https://aistudio.google.com/docs/openai ; https://models.dev/api.json  | verificado: sim
    # Endpoint OpenAI-compatível: https://generativelanguage.googleapis.com/v1beta/openai/ (só chat/completions; Responses não documentado => sem Codex).
    # Sem endpoint Anthropic => sem Claude Code.
    [providers.google-gemini]
    name   = "Google Gemini API"
    models = ["gemini-4-argon", "gemini-3.8-flash"]

    [providers.google-gemini.for.gemini]
    env = { GEMINI_API_KEY = "keychain:bando/google-gemini" }

    [providers.google-gemini.for.opencode]
    env = { GEMINI_API_KEY = "keychain:bando/google-gemini" }

    [providers.google-gemini.for.crush]
    env = { GEMINI_API_KEY = "keychain:bando/google-gemini" }

    [providers.google-gemini.for.qwen]
    env = { GEMINI_API_KEY = "keychain:bando/google-gemini" }

    [providers.google-gemini.for.aider]
    env = { GEMINI_API_KEY = "keychain:bando/google-gemini" }

    # parcial: goose lê GOOGLE_API_KEY (confirmado); ID "google" de doc antiga
    [providers.google-gemini.for.goose]
    env = { GOOSE_PROVIDER = "google", GOOGLE_API_KEY = "keychain:bando/google-gemini" }


    # Fonte: https://docs.x.ai/docs/api-reference ; https://models.dev/api.json  | verificado: parcial
    # Base https://api.x.ai/v1 com /v1/responses documentado. Não há guia oficial de Codex da xAI (parcial).
    # A camada compatível com Anthropic (/v1/messages) consta como descontinuada => sem Claude Code.
    [providers.xai]
    name   = "xAI (Grok)"
    models = ["grok-4.7", "grok-4.6"]

    [providers.xai.for.codex]
    env  = { XAI_API_KEY = "keychain:bando/xai" }
    args = ["-c", "model_provider=\"xai\"", "-c", "model_providers.xai.name=\"xAI\"", "-c", "model_providers.xai.base_url=\"https://api.x.ai/v1\"", "-c", "model_providers.xai.env_key=\"XAI_API_KEY\"", "-c", "model_providers.xai.wire_api=\"responses\""]

    [providers.xai.for.opencode]
    env = { XAI_API_KEY = "keychain:bando/xai" }

    [providers.xai.for.crush]
    env = { XAI_API_KEY = "keychain:bando/xai" }

    [providers.xai.for.aider]
    env = { XAI_API_KEY = "keychain:bando/xai" }

    [providers.xai.for.goose]
    env = { GOOSE_PROVIDER = "xai", XAI_API_KEY = "keychain:bando/xai" }


    # Fonte: https://docs.mistral.ai/api/endpoint/responses ; https://models.dev/api.json  | verificado: parcial
    # /v1/responses existe em public preview e é stateless; sem guia de Codex oficial. Sem endpoint Anthropic.
    [providers.mistral]
    name   = "Mistral AI"
    models = ["mistral-large-4", "devstral-latest"]

    [providers.mistral.for.codex]
    env  = { MISTRAL_API_KEY = "keychain:bando/mistral" }
    args = ["-c", "model_provider=\"mistral\"", "-c", "model_providers.mistral.name=\"Mistral\"", "-c", "model_providers.mistral.base_url=\"https://api.mistral.ai/v1\"", "-c", "model_providers.mistral.env_key=\"MISTRAL_API_KEY\"", "-c", "model_providers.mistral.wire_api=\"responses\""]

    [providers.mistral.for.opencode]
    env = { MISTRAL_API_KEY = "keychain:bando/mistral" }

    [providers.mistral.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/mistral", OPENAI_BASE_URL = "https://api.mistral.ai/v1" }

    [providers.mistral.for.goose]
    env = { GOOSE_PROVIDER = "mistral", MISTRAL_API_KEY = "keychain:bando/mistral" }


    # Fonte: https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code ; https://api-docs.deepseek.com/quick_start/agent_integrations/codex  | verificado: sim
    # Claude: doc recomenda mapear todos os slots. claude-opus* -> deepseek-v4-pro; claude-sonnet*/haiku* -> deepseek-flash.
    # Codex: a doc usa base_url "https://api.deepseek.com/" + wire_api="responses" + experimental_bearer_token
    #        (chave dentro do arquivo). Aqui troquei por env_key, que é o mecanismo padrão do Codex (parcial).
    #        A doc também usa model_catalog_json = "~/.codex/models.json" (opcional).
    [providers.deepseek]
    name   = "DeepSeek"
    models = ["deepseek-v4-pro", "deepseek-flash"]

    [providers.deepseek.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/deepseek", ANTHROPIC_API_KEY = "", ANTHROPIC_MODEL = "deepseek-flash[1m]", ANTHROPIC_DEFAULT_OPUS_MODEL = "deepseek-flash[1m]", ANTHROPIC_DEFAULT_SONNET_MODEL = "deepseek-flash[1m]", ANTHROPIC_DEFAULT_HAIKU_MODEL = "deepseek-flash", CLAUDE_CODE_SUBAGENT_MODEL = "deepseek-flash", CLAUDE_CODE_AUTO_COMPACT_WINDOW = "786432" }

    [providers.deepseek.for.codex]
    env  = { DEEPSEEK_API_KEY = "keychain:bando/deepseek" }
    args = ["-c", "model_provider=\"deepseek\"", "-c", "model_providers.deepseek.name=\"deepseek\"", "-c", "model_providers.deepseek.base_url=\"https://api.deepseek.com/\"", "-c", "model_providers.deepseek.env_key=\"DEEPSEEK_API_KEY\"", "-c", "model_providers.deepseek.wire_api=\"responses\""]

    [providers.deepseek.for.opencode]
    env = { DEEPSEEK_API_KEY = "keychain:bando/deepseek" }

    [providers.deepseek.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/deepseek", OPENAI_BASE_URL = "https://api.deepseek.com" }

    [providers.deepseek.for.aider]
    env = { DEEPSEEK_API_KEY = "keychain:bando/deepseek" }


    # Fonte: https://platform.kimi.ai/docs/guide/claude-code-kimi.md ; https://platform.kimi.ai/docs/guide/codex-kimi.md  | verificado: sim
    # platform.moonshot.ai agora redireciona para platform.kimi.ai. Base OpenAI: https://api.moonshot.ai/v1 (China: api.moonshot.cn).
    # Armadilha: kimi-k2.7-code exige thinking ligado ("only type=enabled is allowed for this model").
    # A doc do Codex usa env_key = "KIMI_API_KEY"; OpenCode/Crush leem MOONSHOT_API_KEY. Mesma chave, nomes diferentes.
    [providers.moonshot]
    name   = "Moonshot (Kimi)"
    models = ["kimi-k3.1-pro", "kimi-k3", "kimi-k2.7-code"]

    [providers.moonshot.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://api.moonshot.ai/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/moonshot", ANTHROPIC_API_KEY = "", ANTHROPIC_MODEL = "kimi-k3[1m]", ANTHROPIC_DEFAULT_OPUS_MODEL = "kimi-k3[1m]", ANTHROPIC_DEFAULT_SONNET_MODEL = "kimi-k3[1m]", ANTHROPIC_DEFAULT_HAIKU_MODEL = "kimi-k2.7-code", ANTHROPIC_DEFAULT_FABLE_MODEL = "kimi-k3[1m]", CLAUDE_CODE_SUBAGENT_MODEL = "kimi-k3[1m]", CLAUDE_CODE_AUTO_COMPACT_WINDOW = "1000000" }

    [providers.moonshot.for.codex]
    env  = { KIMI_API_KEY = "keychain:bando/moonshot" }
    args = ["-c", "model_provider=\"kimi\"", "-c", "model_providers.kimi.name=\"Kimi\"", "-c", "model_providers.kimi.base_url=\"https://api.moonshot.ai/v1\"", "-c", "model_providers.kimi.env_key=\"KIMI_API_KEY\"", "-c", "model_providers.kimi.wire_api=\"responses\""]

    [providers.moonshot.for.opencode]
    env = { MOONSHOT_API_KEY = "keychain:bando/moonshot" }

    [providers.moonshot.for.crush]
    env = { MOONSHOT_API_KEY = "keychain:bando/moonshot" }

    [providers.moonshot.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/moonshot", OPENAI_BASE_URL = "https://api.moonshot.ai/v1" }


    # Fonte: https://models.dev/api.json (provider kimi-code-plan-global)  | verificado: parcial
    # Plano de assinatura Kimi Code (chave própria, diferente da API Moonshot). Endpoint Anthropic do plano não confirmado.
    [providers.kimi-code]
    name   = "Kimi Code (plano)"
    models = ["kimi-for-coding", "k3.1-pro"]

    [providers.kimi-code.for.opencode]
    env = { KIMI_API_KEY = "keychain:bando/kimi-code" }


    # Fonte: https://docs.z.ai/devpack/tool/claude ; https://docs.z.ai/devpack/tool/codex.md  | verificado: sim
    # GLM Coding Plan (internacional). API_TIMEOUT_MS=3000000 é recomendado pela própria z.ai.
    # Codex: endpoint Responses dedicado https://api.z.ai/api/v1 (diferente do /api/coding/paas/v4 de chat).
    #        A doc usa experimental_bearer_token + model_catalog_json; env_key aqui é inferido (parcial).
    # OpenCode: provider "zai-coding-plan" lê ZHIPU_API_KEY (models.dev). Crush lê ZAI_API_KEY. Goose: ZAI_CODING_PLAN_API_KEY.
    [providers.zai]
    name   = "Z.ai (GLM Coding Plan)"
    models = ["glm-5.3", "glm-5.3-flash"]

    [providers.zai.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://api.z.ai/api/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/zai", ANTHROPIC_API_KEY = "", API_TIMEOUT_MS = "3000000", ANTHROPIC_DEFAULT_OPUS_MODEL = "glm-5.3[1m]", ANTHROPIC_DEFAULT_SONNET_MODEL = "glm-5.3[1m]", ANTHROPIC_DEFAULT_HAIKU_MODEL = "glm-5.3-flash[1m]", CLAUDE_CODE_AUTO_COMPACT_WINDOW = "1000000", CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1" }

    [providers.zai.for.codex]
    env  = { ZAI_API_KEY = "keychain:bando/zai" }
    args = ["-c", "model_provider=\"zai\"", "-c", "model_providers.zai.name=\"ZAI\"", "-c", "model_providers.zai.base_url=\"https://api.z.ai/api/v1\"", "-c", "model_providers.zai.env_key=\"ZAI_API_KEY\"", "-c", "model_providers.zai.wire_api=\"responses\""]

    [providers.zai.for.opencode]
    env = { ZHIPU_API_KEY = "keychain:bando/zai" }

    [providers.zai.for.crush]
    env = { ZAI_API_KEY = "keychain:bando/zai" }

    [providers.zai.for.goose]
    env = { GOOSE_PROVIDER = "zai_coding_plan", GOOSE_MODEL = "glm-5.3", ZAI_CODING_PLAN_API_KEY = "keychain:bando/zai" }

    [providers.zai.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/zai", OPENAI_BASE_URL = "https://api.z.ai/api/coding/paas/v4" }


    # Fonte: https://models.dev/api.json (zhipuai-coding-plan) ; https://docs.bigmodel.cn/cn/coding-plan/tool/codex.md  | verificado: parcial
    # Versão China (bigmodel.cn). Endpoint Anthropic https://open.bigmodel.cn/api/anthropic não foi aberto nesta pesquisa.
    [providers.zhipu-cn]
    name   = "Zhipu BigModel (China)"
    models = ["glm-5.3"]

    [providers.zhipu-cn.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://open.bigmodel.cn/api/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/zhipu-cn", ANTHROPIC_API_KEY = "", API_TIMEOUT_MS = "3000000" }

    [providers.zhipu-cn.for.opencode]
    env = { ZHIPU_API_KEY = "keychain:bando/zhipu-cn" }


    # Fonte: https://platform.minimax.io/docs/coding-plan/claude-code ; https://platform.minimax.io/docs/token-plan/codex  | verificado: sim
    # A doc pede para remover ANTHROPIC_AUTH_TOKEN/ANTHROPIC_BASE_URL exportados no shell (sobrescrevem o settings).
    # China: https://api.minimaxi.com/anthropic e https://api.minimaxi.com/v1.
    # Codex: página atual usa wire_api="responses" (a antiga usava "chat" e pedia Codex 0.57.0). Vi só trechos: parcial no Codex.
    [providers.minimax]
    name   = "MiniMax"
    models = ["MiniMax-M3.1-Flash", "MiniMax-M3"]

    [providers.minimax.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://api.minimax.io/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/minimax", ANTHROPIC_API_KEY = "", ANTHROPIC_MODEL = "MiniMax-M3.1-Flash[1m]", ANTHROPIC_DEFAULT_OPUS_MODEL = "MiniMax-M3.1-Flash[1m]", ANTHROPIC_DEFAULT_SONNET_MODEL = "MiniMax-M3.1-Flash[1m]", ANTHROPIC_DEFAULT_HAIKU_MODEL = "MiniMax-M3.1-Flash[1m]", CLAUDE_CODE_AUTO_COMPACT_WINDOW = "524288" }

    [providers.minimax.for.codex]
    env  = { MINIMAX_API_KEY = "keychain:bando/minimax" }
    args = ["-c", "model_provider=\"minimax\"", "-c", "model_providers.minimax.name=\"MiniMax\"", "-c", "model_providers.minimax.base_url=\"https://api.minimax.io/v1\"", "-c", "model_providers.minimax.env_key=\"MINIMAX_API_KEY\"", "-c", "model_providers.minimax.wire_api=\"responses\""]

    [providers.minimax.for.opencode]
    env = { MINIMAX_API_KEY = "keychain:bando/minimax" }

    [providers.minimax.for.crush]
    env = { MINIMAX_API_KEY = "keychain:bando/minimax" }


    # Fonte: https://www.alibabacloud.com/help/en/model-studio/claude-code ; https://www.alibabacloud.com/help/en/model-studio/codex ; https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/  | verificado: sim
    # Pay-as-you-go internacional (Singapura). A seção de setup usa URL com workspace:
    #   https://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/apps/anthropic
    # e o FAQ usa https://dashscope-intl.aliyuncs.com/apps/anthropic (sem workspace). Usei a do FAQ.
    # Codex: Responses só para qwen3.7-max/plus, qwen3.6-plus/flash; outros modelos (ex.: glm-5) só por chat => não funcionam no Codex atual.
    # Crush lê ALIBABA_SINGAPORE_API_KEY (ou ALIBABA_US_API_KEY).
    [providers.dashscope]
    name   = "Alibaba Model Studio (DashScope)"
    models = ["qwen3.7-max", "qwen3.8-max", "qwen3.6-flash"]

    [providers.dashscope.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://dashscope-intl.aliyuncs.com/apps/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/dashscope", ANTHROPIC_API_KEY = "", ANTHROPIC_MODEL = "qwen3.7-max", ANTHROPIC_DEFAULT_OPUS_MODEL = "qwen3.7-max", ANTHROPIC_DEFAULT_SONNET_MODEL = "qwen3.7-max", ANTHROPIC_DEFAULT_HAIKU_MODEL = "qwen3.6-flash", CLAUDE_CODE_SUBAGENT_MODEL = "qwen3.7-max" }

    [providers.dashscope.for.codex]
    env  = { DASHSCOPE_API_KEY = "keychain:bando/dashscope" }
    args = ["-c", "model_provider=\"dashscope\"", "-c", "model_providers.dashscope.name=\"Alibaba Model Studio\"", "-c", "model_providers.dashscope.base_url=\"https://dashscope-intl.aliyuncs.com/compatible-mode/v1\"", "-c", "model_providers.dashscope.env_key=\"DASHSCOPE_API_KEY\"", "-c", "model_providers.dashscope.wire_api=\"responses\""]

    [providers.dashscope.for.opencode]
    env = { DASHSCOPE_API_KEY = "keychain:bando/dashscope" }

    [providers.dashscope.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/dashscope", OPENAI_BASE_URL = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1" }

    [providers.dashscope.for.crush]
    env = { ALIBABA_SINGAPORE_API_KEY = "keychain:bando/dashscope" }


    # Fonte: https://www.alibabacloud.com/help/en/model-studio/claude-code ; https://www.alibabacloud.com/help/en/model-studio/codex-coding-plan ; https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/  | verificado: sim
    # Coding Plan usa chave própria (chave errada => 401 invalid_api_key).
    # Codex: a Alibaba diz que o Coding Plan NÃO funciona via Responses (exige wire_api="chat" e Codex 0.80.0) => sem Codex.
    [providers.dashscope-coding]
    name   = "Alibaba Coding Plan"
    models = ["qwen3.7-plus", "qwen3-coder-next"]

    [providers.dashscope-coding.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/dashscope-coding", ANTHROPIC_API_KEY = "", ANTHROPIC_MODEL = "qwen3.7-plus", ANTHROPIC_DEFAULT_OPUS_MODEL = "qwen3.7-plus", ANTHROPIC_DEFAULT_SONNET_MODEL = "qwen3.7-plus", ANTHROPIC_DEFAULT_HAIKU_MODEL = "qwen3.7-plus", CLAUDE_CODE_SUBAGENT_MODEL = "qwen3.7-plus" }

    [providers.dashscope-coding.for.opencode]
    env = { ALIBABA_CODING_PLAN_API_KEY = "keychain:bando/dashscope-coding" }

    [providers.dashscope-coding.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/dashscope-coding", OPENAI_BASE_URL = "https://coding-intl.dashscope.aliyuncs.com/v1" }


    # Fonte: https://docs.cohere.com/docs/compatibility-api ; https://models.dev/api.json  | verificado: parcial
    # Compatibility API só tem chat/completions, embeddings e transcrição => sem Codex; sem Anthropic.
    [providers.cohere]
    name   = "Cohere"
    models = ["command-a-plus-05-2026", "north-mini-code-1-0"]

    [providers.cohere.for.opencode]
    env = { COHERE_API_KEY = "keychain:bando/cohere" }

    [providers.cohere.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/cohere", OPENAI_BASE_URL = "https://api.cohere.ai/compatibility/v1" }

    [providers.cohere.for.aider]
    env = { COHERE_API_KEY = "keychain:bando/cohere" }


    # Fonte: https://models.dev/api.json (xiaomi)  | verificado: parcial
    [providers.xiaomi-mimo]
    name   = "Xiaomi MiMo"
    models = ["mimo-v2.6-pro", "mimo-v2.6-flash"]

    [providers.xiaomi-mimo.for.opencode]
    env = { XIAOMI_API_KEY = "keychain:bando/xiaomi-mimo" }

    [providers.xiaomi-mimo.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/xiaomi-mimo", OPENAI_BASE_URL = "https://api.xiaomimimo.com/v1" }


    # Fonte: https://models.dev/api.json (stepfun)  | verificado: parcial
    [providers.stepfun]
    name   = "StepFun"
    models = ["step-5-preview", "step-3.7-flash"]

    [providers.stepfun.for.opencode]
    env = { STEPFUN_API_KEY = "keychain:bando/stepfun" }

    [providers.stepfun.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/stepfun", OPENAI_BASE_URL = "https://api.stepfun.com/v1" }


    # Fonte: https://models.dev/api.json (volcengine)  | verificado: parcial
    [providers.volcengine]
    name   = "Volcengine Ark (ByteDance)"
    models = ["doubao-seed-2-1-turbo-260628", "glm-5-3-flash-260828"]

    [providers.volcengine.for.opencode]
    env = { ARK_API_KEY = "keychain:bando/volcengine" }

    [providers.volcengine.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/volcengine", OPENAI_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3" }


    # =============================================================================
    # 2. AGREGADORES E INFERÊNCIA
    # =============================================================================

    # Fonte: https://openrouter.ai/docs/guides/guides/claude-code-integration ; https://openrouter.ai/docs/guides/guides/codex-cli ; https://opencode.ai/docs/providers/  | verificado: sim
    # Claude: ANTHROPIC_API_KEY precisa ser "" (doc explícita). Recomenda Anthropic como provider prioritário.
    # Codex: a doc recomenda bloco auth com comando (echo $OPENROUTER_API_KEY); com env_key funciona,
    #        mas "Codex won't fetch the OpenRouter model catalog in that mode". Responses API é stateless
    #        (store:true ou previous_response_id => 400).
    # Aliases "~provider/familia-latest" sempre apontam para a versão mais nova.
    [providers.openrouter]
    name   = "OpenRouter"
    models = ["~anthropic/claude-sonnet-latest", "~anthropic/claude-opus-latest", "~openai/gpt-sol-latest", "z-ai/glm-5.3"]

    [providers.openrouter.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://openrouter.ai/api", ANTHROPIC_AUTH_TOKEN = "keychain:bando/openrouter", ANTHROPIC_API_KEY = "", CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1" }

    [providers.openrouter.for.codex]
    env  = { OPENROUTER_API_KEY = "keychain:bando/openrouter" }
    args = ["-c", "model_provider=\"openrouter\"", "-c", "model_providers.openrouter.name=\"OpenRouter\"", "-c", "model_providers.openrouter.base_url=\"https://openrouter.ai/api/v1\"", "-c", "model_providers.openrouter.env_key=\"OPENROUTER_API_KEY\"", "-c", "model_providers.openrouter.wire_api=\"responses\""]

    [providers.openrouter.for.opencode]
    env = { OPENROUTER_API_KEY = "keychain:bando/openrouter" }

    [providers.openrouter.for.crush]
    env = { OPENROUTER_API_KEY = "keychain:bando/openrouter" }

    [providers.openrouter.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/openrouter", OPENAI_BASE_URL = "https://openrouter.ai/api/v1" }

    # aider: modelo com prefixo "openrouter/"
    [providers.openrouter.for.aider]
    env = { OPENROUTER_API_KEY = "keychain:bando/openrouter" }

    [providers.openrouter.for.goose]
    env = { GOOSE_PROVIDER = "openrouter", OPENROUTER_API_KEY = "keychain:bando/openrouter" }


    # Fonte: https://vercel.com/docs/ai-gateway/coding-agents/claude-code ; https://vercel.com/docs/ai-gateway/coding-agents/openai-codex  | verificado: sim
    # Claude: endpoint dedicado /claude-code (sem /v1). Modelos aparecem como "claude-code/<provider>/<modelo>".
    #         Roteando para Bedrock/Vertex: CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1.
    # Codex: endpoint dedicado /codex/v1 (serve /codex/v1/models no formato que o Codex lê).
    # Crush lê VERCEL_API_KEY (nome diferente de AI_GATEWAY_API_KEY).
    [providers.vercel-ai-gateway]
    name   = "Vercel AI Gateway"
    models = ["anthropic/claude-sonnet-5", "anthropic/claude-opus-5-5", "openai/gpt-6-astra"]

    [providers.vercel-ai-gateway.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://ai-gateway.vercel.sh/claude-code", ANTHROPIC_AUTH_TOKEN = "keychain:bando/vercel-ai-gateway", ANTHROPIC_API_KEY = "", CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1" }

    [providers.vercel-ai-gateway.for.codex]
    env  = { AI_GATEWAY_API_KEY = "keychain:bando/vercel-ai-gateway" }
    args = ["-c", "model_provider=\"vercel\"", "-c", "model_providers.vercel.name=\"Vercel AI Gateway\"", "-c", "model_providers.vercel.base_url=\"https://ai-gateway.vercel.sh/codex/v1\"", "-c", "model_providers.vercel.env_key=\"AI_GATEWAY_API_KEY\"", "-c", "model_providers.vercel.wire_api=\"responses\""]

    [providers.vercel-ai-gateway.for.opencode]
    env = { AI_GATEWAY_API_KEY = "keychain:bando/vercel-ai-gateway" }

    [providers.vercel-ai-gateway.for.crush]
    env = { VERCEL_API_KEY = "keychain:bando/vercel-ai-gateway" }


    # Fonte: https://developers.cloudflare.com/ai-gateway/integrations/coding-agents/claude-code/ ; https://developers.cloudflare.com/ai-gateway/integrations/coding-agents/openai-codex/ ; https://developers.cloudflare.com/ai-gateway/integrations/coding-agents/gemini-cli/  | verificado: sim
    # URLs exigem <ACCOUNT_ID> e <GATEWAY_ID> literais (o Codex não expande variáveis em base_url).
    # Claude: o token do gateway vai no header cf-aig-authorization via ANTHROPIC_CUSTOM_HEADERS; aqui o
    #         keychain guarda a LINHA INTEIRA "cf-aig-authorization: Bearer <token>". ANTHROPIC_API_KEY é
    #         obrigatório (pode ser o mesmo token; é ignorado com Unified Billing/BYOK). Token precisa de permissão Run.
    # Codex: só modelos OpenAI com Responses API passam por esse caminho.
    # Gemini CLI: a doc da Cloudflare usa domínio próprio + Cloudflare Access; aqui o formato padrão do gateway (parcial).
    [providers.cloudflare-ai-gateway]
    name   = "Cloudflare AI Gateway"
    models = ["claude-sonnet-5", "gpt-5.5"]

    [providers.cloudflare-ai-gateway.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://gateway.ai.cloudflare.com/v1/<ACCOUNT_ID>/<GATEWAY_ID>/anthropic", ANTHROPIC_API_KEY = "keychain:bando/cloudflare-ai-gateway", ANTHROPIC_CUSTOM_HEADERS = "keychain:bando/cloudflare-ai-gateway-header" }

    [providers.cloudflare-ai-gateway.for.codex]
    env  = { CLOUDFLARE_API_KEY = "keychain:bando/cloudflare-ai-gateway" }
    args = ["-c", "model_provider=\"cloudflare\"", "-c", "model_providers.cloudflare.name=\"Cloudflare AI Gateway\"", "-c", "model_providers.cloudflare.base_url=\"https://gateway.ai.cloudflare.com/v1/<ACCOUNT_ID>/<GATEWAY_ID>/openai\"", "-c", "model_providers.cloudflare.env_key=\"CLOUDFLARE_API_KEY\"", "-c", "model_providers.cloudflare.wire_api=\"responses\""]

    [providers.cloudflare-ai-gateway.for.opencode]
    env = { CLOUDFLARE_API_TOKEN = "keychain:bando/cloudflare-ai-gateway", CLOUDFLARE_ACCOUNT_ID = "env:CLOUDFLARE_ACCOUNT_ID", CLOUDFLARE_GATEWAY_ID = "env:CLOUDFLARE_GATEWAY_ID" }

    [providers.cloudflare-ai-gateway.for.gemini]
    env = { GOOGLE_GEMINI_BASE_URL = "https://gateway.ai.cloudflare.com/v1/<ACCOUNT_ID>/<GATEWAY_ID>/google-ai-studio", GEMINI_API_KEY = "keychain:bando/cloudflare-ai-gateway" }


    # Fonte: https://models.dev/api.json (cloudflare-workers-ai)  | verificado: parcial
    # Endpoint OpenAI-compatível com o account id no caminho.
    [providers.cloudflare-workers-ai]
    name   = "Cloudflare Workers AI"
    models = ["@cf/zai-org/glm-5.3", "@cf/qwen/qwen3.8-27b"]

    [providers.cloudflare-workers-ai.for.opencode]
    env = { CLOUDFLARE_API_KEY = "keychain:bando/cloudflare-workers-ai", CLOUDFLARE_ACCOUNT_ID = "env:CLOUDFLARE_ACCOUNT_ID" }

    [providers.cloudflare-workers-ai.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/cloudflare-workers-ai", OPENAI_BASE_URL = "https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/ai/v1" }


    # Fonte: https://huggingface.co/docs/inference-providers/integrations/claude-code ; https://huggingface.co/docs/inference-providers/integrations/codex  | verificado: sim
    # Claude: a doc define o MESMO token em ANTHROPIC_AUTH_TOKEN e ANTHROPIC_API_KEY.
    # Sufixos no ID: ":fastest" (padrão), ":cheapest", ":preferred" ou ":<provider>" (ex.: ":groq").
    # Cobrança para organização: ANTHROPIC_CUSTOM_HEADERS="X-HF-Bill-To: <org>" (Claude) / http_headers (Codex).
    [providers.huggingface]
    name   = "Hugging Face Inference Providers"
    models = ["zai-org/GLM-5.1", "openai/gpt-oss-120b", "MiniMaxAI/MiniMax-M2.7"]

    [providers.huggingface.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://router.huggingface.co", ANTHROPIC_AUTH_TOKEN = "keychain:bando/huggingface", ANTHROPIC_API_KEY = "keychain:bando/huggingface", ANTHROPIC_DEFAULT_OPUS_MODEL = "zai-org/GLM-5.1", ANTHROPIC_DEFAULT_SONNET_MODEL = "zai-org/GLM-5.1", ANTHROPIC_DEFAULT_HAIKU_MODEL = "zai-org/GLM-5.1", CLAUDE_CODE_SUBAGENT_MODEL = "zai-org/GLM-5.1" }

    [providers.huggingface.for.codex]
    env  = { HF_TOKEN = "keychain:bando/huggingface" }
    args = ["-c", "model_provider=\"huggingface\"", "-c", "model_providers.huggingface.name=\"Hugging Face\"", "-c", "model_providers.huggingface.base_url=\"https://router.huggingface.co/v1\"", "-c", "model_providers.huggingface.env_key=\"HF_TOKEN\"", "-c", "model_providers.huggingface.wire_api=\"responses\""]

    [providers.huggingface.for.opencode]
    env = { HF_TOKEN = "keychain:bando/huggingface" }

    [providers.huggingface.for.crush]
    env = { HF_TOKEN = "keychain:bando/huggingface" }

    [providers.huggingface.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/huggingface", OPENAI_BASE_URL = "https://router.huggingface.co/v1" }


    # Fonte: https://docs.requesty.ai/integrations/claude-code ; https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/  | verificado: sim
    # Responses API da Requesty não confirmada => sem Codex.
    [providers.requesty]
    name   = "Requesty"
    models = ["kimi-k3.1-pro", "minimax-m3.1-flash"]

    [providers.requesty.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://router.requesty.ai", ANTHROPIC_AUTH_TOKEN = "keychain:bando/requesty", ANTHROPIC_API_KEY = "" }

    [providers.requesty.for.opencode]
    env = { REQUESTY_API_KEY = "keychain:bando/requesty" }

    [providers.requesty.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/requesty", OPENAI_BASE_URL = "https://router.requesty.ai/v1" }


    # Fonte: https://docs.venice.ai/guides/integrations/codex-cli ; https://docs.venice.ai/guides/integrations/claude-code ; https://models.dev/api.json ; https://goose-docs.ai/docs/getting-started/providers  | verificado: parcial
    # Codex: a doc usa experimental_bearer_token no config.toml; aqui env_key, para a chave sair do Keychain.
    #        Responses API em alpha (POST /api/v1/responses responde 402 sem crédito, a rota existe).
    # Sem endpoint Anthropic (POST /api/v1/messages = 404, 11/11/2026): a doc manda usar claude-code-router => sem Claude Code.
    # Crush e Aider não listam a Venice. Goose lista VENICE_API_KEY; o ID "venice" de GOOSE_PROVIDER não aparece na página.
    [providers.venice]
    name   = "Venice AI"
    models = ["z-ai-glm-5-3", "kimi-k3", "deepseek-v4-pro", "openai-gpt-6-astra"]

    [providers.venice.for.codex]
    env  = { VENICE_API_KEY = "keychain:bando/venice" }
    args = ["-c", "model_provider=\"venice\"", "-c", "model_providers.venice.name=\"Venice\"", "-c", "model_providers.venice.base_url=\"https://api.venice.ai/api/v1\"", "-c", "model_providers.venice.env_key=\"VENICE_API_KEY\"", "-c", "model_providers.venice.wire_api=\"responses\""]

    [providers.venice.for.opencode]
    env = { VENICE_API_KEY = "keychain:bando/venice" }

    [providers.venice.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/venice", OPENAI_BASE_URL = "https://api.venice.ai/api/v1" }

    [providers.venice.for.goose]
    env = { GOOSE_PROVIDER = "venice", VENICE_API_KEY = "keychain:bando/venice" }


    # Fonte: https://console.groq.com/docs/responses-api ; https://console.groq.com/docs/coding-with-groq  | verificado: parcial
    # Responses API em beta em https://api.groq.com/openai/v1 ("all models support the Responses API").
    # Groq não documenta Codex (parcial). Sem endpoint Anthropic (há pedido aberto na comunidade).
    [providers.groq]
    name   = "Groq"
    models = ["openai/gpt-oss-120b", "qwen/qwen3.8-27b"]

    [providers.groq.for.codex]
    env  = { GROQ_API_KEY = "keychain:bando/groq" }
    args = ["-c", "model_provider=\"groq\"", "-c", "model_providers.groq.name=\"Groq\"", "-c", "model_providers.groq.base_url=\"https://api.groq.com/openai/v1\"", "-c", "model_providers.groq.env_key=\"GROQ_API_KEY\"", "-c", "model_providers.groq.wire_api=\"responses\""]

    [providers.groq.for.opencode]
    env = { GROQ_API_KEY = "keychain:bando/groq" }

    [providers.groq.for.crush]
    env = { GROQ_API_KEY = "keychain:bando/groq" }

    [providers.groq.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/groq", OPENAI_BASE_URL = "https://api.groq.com/openai/v1" }

    [providers.groq.for.aider]
    env = { GROQ_API_KEY = "keychain:bando/groq" }

    [providers.groq.for.goose]
    env = { GOOSE_PROVIDER = "groq", GROQ_API_KEY = "keychain:bando/groq" }


    # Fonte: https://models.dev/api.json ; https://github.com/charmbracelet/crush ; https://goose-docs.ai/docs/getting-started/providers  | verificado: parcial
    # Sem endpoint Anthropic nem Responses documentados pela Cerebras. Base OpenAI de fontes secundárias.
    [providers.cerebras]
    name   = "Cerebras"
    models = ["qwen-3.8-27b", "gpt-oss-120b"]

    [providers.cerebras.for.opencode]
    env = { CEREBRAS_API_KEY = "keychain:bando/cerebras" }

    [providers.cerebras.for.crush]
    env = { CEREBRAS_API_KEY = "keychain:bando/cerebras" }

    [providers.cerebras.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/cerebras", OPENAI_BASE_URL = "https://api.cerebras.ai/v1" }

    [providers.cerebras.for.goose]
    env = { GOOSE_PROVIDER = "cerebras", CEREBRAS_API_KEY = "keychain:bando/cerebras" }


    # Fonte: https://docs.together.ai/docs/how-to-use-togetherlink ; https://models.dev/api.json  | verificado: parcial
    # Claude Code/Codex só pelo wrapper "togetherlink claude|codex" (gateway hospedado sem URL documentada)
    # ou via LiteLLM local. Por isso não há for.claude/for.codex.
    [providers.together]
    name   = "Together AI"
    models = ["moonshotai/Kimi-K3.1-Pro", "zai-org/GLM-5.3-Flash", "deepseek-ai/DeepSeek-V4.1-Flash"]

    [providers.together.for.opencode]
    env = { TOGETHER_API_KEY = "keychain:bando/together" }

    [providers.together.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/together", OPENAI_BASE_URL = "https://api.together.xyz/v1" }


    # Fonte: https://docs.fireworks.ai/tools-sdks/anthropic-compatibility  | verificado: sim
    # Claude: usar ANTHROPIC_AUTH_TOKEN; chave Fireworks em ANTHROPIC_API_KEY causa "Not logged in".
    # Região só-EUA: https://us.api.fireworks.ai/inference. count_tokens retorna 404 (fonte secundária).
    [providers.fireworks]
    name   = "Fireworks AI"
    models = ["accounts/fireworks/models/kimi-k3p1-pro", "accounts/fireworks/models/minimax-m3p1-flash", "accounts/fireworks/models/kimi-k2p5"]

    [providers.fireworks.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://api.fireworks.ai/inference", ANTHROPIC_AUTH_TOKEN = "keychain:bando/fireworks", ANTHROPIC_API_KEY = "" }

    [providers.fireworks.for.opencode]
    env = { FIREWORKS_API_KEY = "keychain:bando/fireworks" }

    [providers.fireworks.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/fireworks", OPENAI_BASE_URL = "https://api.fireworks.ai/inference/v1" }


    # Fonte: https://docs.deepinfra.com/integrations/anthropic  | verificado: sim
    # Aceita Bearer ou x-api-key; suporta /v1/messages/count_tokens.
    [providers.deepinfra]
    name   = "DeepInfra"
    models = ["deepseek-ai/DeepSeek-V4.1-Flash-1017", "moonshotai/Kimi-K3", "zai-org/GLM-5.3"]

    [providers.deepinfra.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://api.deepinfra.com/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/deepinfra", ANTHROPIC_API_KEY = "", ANTHROPIC_DEFAULT_OPUS_MODEL = "deepseek-ai/DeepSeek-V4-Pro-0813[1m]", ANTHROPIC_DEFAULT_SONNET_MODEL = "deepseek-ai/DeepSeek-V4.1-Flash-1017[1m]", ANTHROPIC_DEFAULT_HAIKU_MODEL = "inclusionAI/Ling-3.0-flash" }

    [providers.deepinfra.for.opencode]
    env = { DEEPINFRA_API_KEY = "keychain:bando/deepinfra" }

    # parcial: base OpenAI da DeepInfra de memória/docs antigas
    [providers.deepinfra.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/deepinfra", OPENAI_BASE_URL = "https://api.deepinfra.com/v1/openai" }


    # Fonte: https://docs.novita.ai/guides/claude-code ; https://models.dev/api.json  | verificado: sim
    # A doc ainda usa ANTHROPIC_SMALL_FAST_MODEL (obsoleto no Claude Code); troquei por ANTHROPIC_DEFAULT_HAIKU_MODEL.
    # O exemplo oficial (moonshotai/kimi-k2-instruct) está desatualizado; models abaixo vêm do catálogo.
    [providers.novita]
    name   = "Novita AI"
    models = ["moonshotai/kimi-k3.1-pro", "minimax/minimax-m3.1-flash", "deepseek/deepseek-v4.1-flash-1017"]

    [providers.novita.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://api.novita.ai/anthropic", ANTHROPIC_AUTH_TOKEN = "keychain:bando/novita", ANTHROPIC_API_KEY = "" }

    [providers.novita.for.opencode]
    env = { NOVITA_API_KEY = "keychain:bando/novita" }

    [providers.novita.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/novita", OPENAI_BASE_URL = "https://api.novita.ai/openai" }

    [providers.novita.for.goose]
    env = { GOOSE_PROVIDER = "novita", NOVITA_API_KEY = "keychain:bando/novita" }


    # Fonte: https://docs.siliconflow.com/en/usercases/use-siliconcloud-in-ClaudeCode  | verificado: sim
    # Doc oficial usa ANTHROPIC_API_KEY; blog da própria SiliconFlow diz que o endpoint documenta Bearer (AUTH_TOKEN).
    # Sem /v1 na base (com /v1 vira /v1/v1/messages). China: https://api.siliconflow.cn
    [providers.siliconflow]
    name   = "SiliconFlow"
    models = ["zai-org/GLM-5.3", "deepseek-ai/DeepSeek-V4-Pro-0813"]

    [providers.siliconflow.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://api.siliconflow.com", ANTHROPIC_API_KEY = "keychain:bando/siliconflow" }

    [providers.siliconflow.for.opencode]
    env = { SILICONFLOW_API_KEY = "keychain:bando/siliconflow" }

    [providers.siliconflow.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/siliconflow", OPENAI_BASE_URL = "https://api.siliconflow.com/v1" }


    # Fonte: https://sambanova.ai/blog/sambacloud-now-supports-the-anthropic-messages-api ; https://models.dev/api.json  | verificado: parcial
    # Claude: doc da SambaNova usa ANTHROPIC_API_KEY. Sem tools server-side, PDF e imagens por URL.
    [providers.sambanova]
    name   = "SambaNova Cloud"
    models = ["MiniMax-M3", "DeepSeek-V3.2", "gpt-oss-120b"]

    [providers.sambanova.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://api.sambanova.ai", ANTHROPIC_API_KEY = "keychain:bando/sambanova", ANTHROPIC_MODEL = "MiniMax-M3" }

    [providers.sambanova.for.opencode]
    env = { SAMBANOVA_API_KEY = "keychain:bando/sambanova" }

    [providers.sambanova.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/sambanova", OPENAI_BASE_URL = "https://api.sambanova.ai/v1" }


    # Fonte: https://models.dev/api.json (nebius)  | verificado: parcial
    # Nebius AI Studio virou "Token Factory": base mudou para api.tokenfactory.nebius.com.
    [providers.nebius]
    name   = "Nebius Token Factory"
    models = ["MiniMaxAI/MiniMax-M3.1-Flash", "deepseek-ai/DeepSeek-V4.1-Flash-1017"]

    [providers.nebius.for.opencode]
    env = { NEBIUS_API_KEY = "keychain:bando/nebius" }

    [providers.nebius.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/nebius", OPENAI_BASE_URL = "https://api.tokenfactory.nebius.com/v1" }


    # Fonte: https://docs.hyperbolic.xyz (não aberto; base de memória)  | verificado: parcial
    # Ausente do models.dev => OpenCode só via provider customizado.
    [providers.hyperbolic]
    name   = "Hyperbolic"
    models = []

    [providers.hyperbolic.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/hyperbolic", OPENAI_BASE_URL = "https://api.hyperbolic.xyz/v1" }


    # Fonte: https://models.dev/api.json (baseten)  | verificado: parcial
    [providers.baseten]
    name   = "Baseten"
    models = ["moonshotai/Kimi-K3.1-Pro", "deepseek-ai/DeepSeek-V4.1-Flash-1017"]

    [providers.baseten.for.opencode]
    env = { BASETEN_API_KEY = "keychain:bando/baseten" }

    [providers.baseten.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/baseten", OPENAI_BASE_URL = "https://inference.baseten.co/v1" }


    # Fonte: https://models.dev/api.json (chutes)  | verificado: parcial
    [providers.chutes]
    name   = "Chutes"
    models = ["zai-org/GLM-5.3", "moonshotai/Kimi-K2.7-Code"]

    [providers.chutes.for.opencode]
    env = { CHUTES_API_KEY = "keychain:bando/chutes" }

    [providers.chutes.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/chutes", OPENAI_BASE_URL = "https://llm.chutes.ai/v1" }


    # Fonte: https://models.dev/api.json (nvidia)  | verificado: parcial
    # NVIDIA também documenta Claude Code com NIM self-hosted (docs.nvidia.com/nim/.../claude-code.html), não com a API hospedada.
    [providers.nvidia]
    name   = "NVIDIA NIM (build.nvidia.com)"
    models = ["z-ai/glm-5.3", "minimaxai/minimax-m3.1-flash"]

    [providers.nvidia.for.opencode]
    env = { NVIDIA_API_KEY = "keychain:bando/nvidia" }

    [providers.nvidia.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/nvidia", OPENAI_BASE_URL = "https://integrate.api.nvidia.com/v1" }


    # Fonte: https://models.dev/api.json (synthetic) ; https://github.com/charmbracelet/crush  | verificado: parcial
    [providers.synthetic]
    name   = "Synthetic"
    models = ["hf:zai-org/GLM-5.3", "hf:moonshotai/Kimi-K3"]

    [providers.synthetic.for.opencode]
    env = { SYNTHETIC_API_KEY = "keychain:bando/synthetic" }

    [providers.synthetic.for.crush]
    env = { SYNTHETIC_API_KEY = "keychain:bando/synthetic" }

    [providers.synthetic.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/synthetic", OPENAI_BASE_URL = "https://api.synthetic.new/openai/v1" }


    # Fonte: https://models.dev/api.json (zenmux) ; https://docs.zenmux.ai/best-practices/claude-code (não aberto)  | verificado: parcial
    [providers.zenmux]
    name   = "ZenMux"
    models = []

    [providers.zenmux.for.opencode]
    env = { ZENMUX_API_KEY = "keychain:bando/zenmux" }

    [providers.zenmux.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/zenmux", OPENAI_BASE_URL = "https://zenmux.ai/api/v1" }


    # Fonte: https://models.dev/api.json (opencode, opencode-go) ; https://github.com/charmbracelet/crush  | verificado: parcial
    # Zen e Go usam a mesma variável; Go usa base https://opencode.ai/inference/go/openai/v1.
    [providers.opencode-zen]
    name   = "OpenCode Zen / Go"
    models = []

    [providers.opencode-zen.for.opencode]
    env = { OPENCODE_API_KEY = "keychain:bando/opencode-zen" }

    [providers.opencode-zen.for.crush]
    env = { OPENCODE_API_KEY = "keychain:bando/opencode-zen" }


    # Fonte: https://docs.litellm.ai/docs/tutorials/claude_responses_api ; https://docs.litellm.ai/docs/proxy/client_setup/codex_cli ; https://goose-docs.ai/docs/getting-started/providers  | verificado: sim
    # Proxy local, porta padrão 4000. Para pass-through Anthropic puro: ANTHROPIC_BASE_URL=http://localhost:4000/anthropic.
    # OpenCode: sem provider nativo (usar provider customizado @ai-sdk/openai-compatible).
    [providers.litellm]
    name   = "LiteLLM Proxy"
    models = ["claude-sonnet-5"]

    [providers.litellm.for.claude]
    env = { ANTHROPIC_BASE_URL = "http://localhost:4000", ANTHROPIC_AUTH_TOKEN = "keychain:bando/litellm", ANTHROPIC_API_KEY = "" }

    [providers.litellm.for.codex]
    env  = { LITELLM_API_KEY = "keychain:bando/litellm" }
    args = ["-c", "model_provider=\"litellm\"", "-c", "model_providers.litellm.name=\"LiteLLM\"", "-c", "model_providers.litellm.base_url=\"http://localhost:4000/v1\"", "-c", "model_providers.litellm.env_key=\"LITELLM_API_KEY\"", "-c", "model_providers.litellm.wire_api=\"responses\""]

    [providers.litellm.for.qwen]
    env = { OPENAI_API_KEY = "keychain:bando/litellm", OPENAI_BASE_URL = "http://localhost:4000/v1" }

    [providers.litellm.for.goose]
    env = { GOOSE_PROVIDER = "litellm", LITELLM_HOST = "http://localhost:4000", LITELLM_API_KEY = "keychain:bando/litellm" }


    # =============================================================================
    # 3. NUVENS
    # =============================================================================

    # Fonte: https://code.claude.com/docs/en/amazon-bedrock ; https://learn.chatgpt.com/docs/config-file/config-reference ; https://opencode.ai/docs/providers/ ; https://github.com/charmbracelet/crush  | verificado: sim
    # Claude: credenciais pela cadeia padrão do SDK AWS (AWS_PROFILE, chaves, SSO) ou AWS_BEARER_TOKEN_BEDROCK.
    #   Região: AWS_REGION > AWS_DEFAULT_REGION > região do perfil > us-east-1.
    #   Sem pin, "opus" resolve para Opus 5.5 (preço Opus). Para pinar: ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL
    #   com IDs de inference profile (prefixo us./eu./apac./global.). ANTHROPIC_BEDROCK_REGION_PREFIX muda só o prefixo.
    #   WebSearch não existe no Bedrock. Endpoint Mantle (API Anthropic nativa): CLAUDE_CODE_USE_MANTLE=1.
    # Codex: provider built-in "amazon-bedrock" (aws.profile / aws.region no config). Leitura de AWS_REGION do ambiente não confirmada (parcial).
    [providers.aws-bedrock]
    name   = "Amazon Bedrock"
    models = ["us.anthropic.claude-opus-5-5", "us.anthropic.claude-sonnet-4-6", "us.anthropic.claude-haiku-4-5-20251001-v1:0"]

    [providers.aws-bedrock.for.claude]
    env = { CLAUDE_CODE_USE_BEDROCK = "1", AWS_REGION = "env:AWS_REGION", AWS_PROFILE = "env:AWS_PROFILE" }

    [providers.aws-bedrock.for.codex]
    env  = { AWS_REGION = "env:AWS_REGION", AWS_PROFILE = "env:AWS_PROFILE" }
    args = ["-c", "model_provider=\"amazon-bedrock\""]

    [providers.aws-bedrock.for.opencode]
    env = { AWS_REGION = "env:AWS_REGION", AWS_PROFILE = "env:AWS_PROFILE" }

    [providers.aws-bedrock.for.crush]
    env = { AWS_REGION = "env:AWS_REGION", AWS_PROFILE = "env:AWS_PROFILE" }

    [providers.aws-bedrock.for.goose]
    env = { GOOSE_PROVIDER = "aws_bedrock", AWS_REGION = "env:AWS_REGION", AWS_PROFILE = "env:AWS_PROFILE" }


    # Fonte: https://code.claude.com/docs/en/amazon-bedrock (seção API key)  | verificado: sim
    # Variante com chave de API do Bedrock (bearer). Com ela setada, o Claude Code ignora a cadeia de credenciais.
    [providers.aws-bedrock-apikey]
    name   = "Amazon Bedrock (API key)"
    models = ["us.anthropic.claude-opus-5-5", "us.anthropic.claude-sonnet-4-6"]

    [providers.aws-bedrock-apikey.for.claude]
    env = { CLAUDE_CODE_USE_BEDROCK = "1", AWS_REGION = "env:AWS_REGION", AWS_BEARER_TOKEN_BEDROCK = "keychain:bando/aws-bedrock-apikey" }

    [providers.aws-bedrock-apikey.for.opencode]
    env = { AWS_REGION = "env:AWS_REGION", AWS_BEARER_TOKEN_BEDROCK = "keychain:bando/aws-bedrock-apikey" }

    [providers.aws-bedrock-apikey.for.crush]
    env = { AWS_REGION = "env:AWS_REGION", AWS_BEARER_TOKEN_BEDROCK = "keychain:bando/aws-bedrock-apikey" }


    # Fonte: https://code.claude.com/docs/en/google-vertex-ai ; https://geminicli.com/docs/get-started/authentication ; https://opencode.ai/docs/providers/ ; https://learn.chatgpt.com/docs/config-file/config-reference  | verificado: sim
    # Vertex AI agora se chama "Google Cloud's Agent Platform" na doc do Claude Code (variáveis continuam iguais).
    # Claude: CLOUD_ML_REGION aceita "global", multi-região ("us", "eu") ou região. Fallback: us-east5.
    #   Modelos sem endpoint global: VERTEX_REGION_CLAUDE_<MODELO>=<região> (ex.: VERTEX_REGION_CLAUDE_HAIKU_4_5).
    #   ANTHROPIC_VERTEX_PROJECT_ID tem precedência sobre GOOGLE_CLOUD_PROJECT. Autenticação via ADC (gcloud).
    # Gemini CLI: GOOGLE_GENAI_USE_VERTEXAI=true não aparece na página atual de auth (vem do Qwen Code e de docs antigas): parcial.
    # OpenCode: ID "google-vertex" (o antigo "google-vertex-anthropic" foi aposentado).
    # Codex: provider built-in "gcp" (project_id/location; lê GOOGLE_CLOUD_PROJECT/GOOGLE_CLOUD_LOCATION, padrão "global"): parcial.
    # Crush: VERTEXAI_PROJECT/VERTEXAI_LOCATION (só Gemini).
    [providers.google-vertex]
    name   = "Google Vertex AI (Agent Platform)"
    models = ["claude-opus-5-5", "claude-sonnet-5", "claude-haiku-4-5@20251001", "gemini-4-argon"]

    [providers.google-vertex.for.claude]
    env = { CLAUDE_CODE_USE_VERTEX = "1", CLOUD_ML_REGION = "global", ANTHROPIC_VERTEX_PROJECT_ID = "env:GOOGLE_CLOUD_PROJECT" }

    [providers.google-vertex.for.gemini]
    env = { GOOGLE_GENAI_USE_VERTEXAI = "true", GOOGLE_CLOUD_PROJECT = "env:GOOGLE_CLOUD_PROJECT", GOOGLE_CLOUD_LOCATION = "env:GOOGLE_CLOUD_LOCATION" }

    [providers.google-vertex.for.opencode]
    env = { GOOGLE_VERTEX_PROJECT = "env:GOOGLE_CLOUD_PROJECT", GOOGLE_VERTEX_LOCATION = "env:GOOGLE_CLOUD_LOCATION" }

    [providers.google-vertex.for.codex]
    env  = { GOOGLE_CLOUD_PROJECT = "env:GOOGLE_CLOUD_PROJECT", GOOGLE_CLOUD_LOCATION = "env:GOOGLE_CLOUD_LOCATION" }
    args = ["-c", "model_provider=\"gcp\""]

    [providers.google-vertex.for.crush]
    env = { VERTEXAI_PROJECT = "env:GOOGLE_CLOUD_PROJECT", VERTEXAI_LOCATION = "env:GOOGLE_CLOUD_LOCATION" }

    [providers.google-vertex.for.goose]
    env = { GOOSE_PROVIDER = "gcp_vertex_ai", GCP_PROJECT_ID = "env:GOOGLE_CLOUD_PROJECT", GCP_LOCATION = "env:GOOGLE_CLOUD_LOCATION" }


    # Fonte: https://code.claude.com/docs/en/microsoft-foundry  | verificado: sim
    # Claude no Azure (Microsoft Foundry). ANTHROPIC_FOUNDRY_RESOURCE é só o NOME do recurso (URL é recusada).
    # Alternativa: ANTHROPIC_FOUNDRY_BASE_URL=https://{resource}.services.ai.azure.com/anthropic.
    # Sem chave => usa Entra ID (az login). Foundry não tem checagem de modelo na inicialização: sem pin, falha se o default
    # (Opus 4.6) não existir. Os IDs de modelo são os NOMES DOS DEPLOYMENTS.
    [providers.azure-foundry]
    name   = "Microsoft Foundry (Claude)"
    models = ["claude-opus-4-8", "claude-sonnet-5", "claude-haiku-4-5"]

    [providers.azure-foundry.for.claude]
    env = { CLAUDE_CODE_USE_FOUNDRY = "1", ANTHROPIC_FOUNDRY_RESOURCE = "env:ANTHROPIC_FOUNDRY_RESOURCE", ANTHROPIC_FOUNDRY_API_KEY = "keychain:bando/azure-foundry" }


    # Fonte: https://opencode.ai/docs/providers/ ; https://github.com/charmbracelet/crush ; https://goose-docs.ai/docs/getting-started/providers  | verificado: parcial
    # Azure OpenAI. Codex: base https://<recurso>.openai.azure.com/openai/v1 com wire_api="responses" vem de guias
    # de terceiros (parcial). Modelos = nomes de deployment.
    [providers.azure-openai]
    name   = "Azure OpenAI"
    models = ["gpt-6.1-terra", "gpt-6.1-sol"]

    [providers.azure-openai.for.codex]
    env  = { AZURE_OPENAI_API_KEY = "keychain:bando/azure-openai" }
    args = ["-c", "model_provider=\"azure\"", "-c", "model_providers.azure.name=\"Azure OpenAI\"", "-c", "model_providers.azure.base_url=\"https://<RECURSO>.openai.azure.com/openai/v1\"", "-c", "model_providers.azure.env_key=\"AZURE_OPENAI_API_KEY\"", "-c", "model_providers.azure.wire_api=\"responses\""]

    [providers.azure-openai.for.opencode]
    env = { AZURE_RESOURCE_NAME = "env:AZURE_RESOURCE_NAME", AZURE_API_KEY = "keychain:bando/azure-openai" }

    [providers.azure-openai.for.crush]
    env = { AZURE_OPENAI_API_ENDPOINT = "env:AZURE_OPENAI_API_ENDPOINT", AZURE_OPENAI_API_KEY = "keychain:bando/azure-openai", AZURE_OPENAI_API_VERSION = "env:AZURE_OPENAI_API_VERSION" }

    [providers.azure-openai.for.goose]
    env = { GOOSE_PROVIDER = "azure_openai", AZURE_OPENAI_ENDPOINT = "env:AZURE_OPENAI_ENDPOINT", AZURE_OPENAI_DEPLOYMENT_NAME = "env:AZURE_OPENAI_DEPLOYMENT_NAME", AZURE_OPENAI_API_KEY = "keychain:bando/azure-openai" }


    # =============================================================================
    # 4. LOCAIS
    # =============================================================================

    # Fonte: https://docs.ollama.com/integrations/claude-code ; https://docs.ollama.com/integrations/codex ; https://docs.ollama.com/api/openai-compatibility ; https://opencode.ai/docs/providers/ ; https://aider.chat/docs/llms/ollama.html  | verificado: sim
    # Claude: token "ollama" é ignorado pelo servidor local, mas obrigatório no cliente. /v1/messages não suporta tool_choice/metadata.
    #   Atalho oficial: "ollama launch claude".
    # Codex: "codex --oss" com oss_provider=ollama; /v1/responses só stateless. Contexto mínimo 64k.
    # OpenCode: autodescoberta em http://127.0.0.1:11434 (sem env).
    # Aider: prefixo "ollama_chat/"; janela padrão do Ollama (2k) corta contexto em silêncio.
    [providers.ollama]
    name   = "Ollama (local)"
    models = ["qwen3.5", "gpt-oss:120b", "gpt-oss:20b"]

    [providers.ollama.for.claude]
    env = { ANTHROPIC_BASE_URL = "http://localhost:11434", ANTHROPIC_AUTH_TOKEN = "ollama", ANTHROPIC_API_KEY = "" }

    [providers.ollama.for.codex]
    args = ["--oss", "-c", "oss_provider=\"ollama\""]

    [providers.ollama.for.opencode]
    env = {}

    [providers.ollama.for.qwen]
    env = { OPENAI_API_KEY = "ollama", OPENAI_BASE_URL = "http://localhost:11434/v1" }

    [providers.ollama.for.aider]
    env = { OLLAMA_API_BASE = "http://127.0.0.1:11434" }

    [providers.ollama.for.goose]
    env = { GOOSE_PROVIDER = "ollama", OLLAMA_HOST = "localhost:11434" }


    # Fonte: https://docs.ollama.com/integrations/claude-code ; https://docs.ollama.com/api/anthropic-compatibility ; https://docs.ollama.com/api/openai-compatibility  | verificado: sim
    # Ollama Cloud direto: Anthropic exige Bearer (x-api-key sozinho é recusado); Responses sem estado e sem web search.
    # Goose usa OLLAMA_CLOUD_API_KEY (nome diferente).
    [providers.ollama-cloud]
    name   = "Ollama Cloud"
    models = ["glm-5.3-flash", "kimi-k2.7-code:cloud", "gpt-oss:120b-cloud"]

    [providers.ollama-cloud.for.claude]
    env = { ANTHROPIC_BASE_URL = "https://ollama.com", ANTHROPIC_AUTH_TOKEN = "keychain:bando/ollama-cloud", ANTHROPIC_API_KEY = "" }

    [providers.ollama-cloud.for.codex]
    env  = { OLLAMA_API_KEY = "keychain:bando/ollama-cloud" }
    args = ["-c", "model_provider=\"ollama-cloud\"", "-c", "model_providers.ollama-cloud.name=\"Ollama Cloud\"", "-c", "model_providers.ollama-cloud.base_url=\"https://ollama.com/v1\"", "-c", "model_providers.ollama-cloud.env_key=\"OLLAMA_API_KEY\"", "-c", "model_providers.ollama-cloud.wire_api=\"responses\""]

    [providers.ollama-cloud.for.opencode]
    env = { OLLAMA_API_KEY = "keychain:bando/ollama-cloud" }

    [providers.ollama-cloud.for.goose]
    env = { GOOSE_PROVIDER = "ollama_cloud", OLLAMA_CLOUD_API_KEY = "keychain:bando/ollama-cloud" }


    # Fonte: https://lmstudio.ai/docs/integrations/claude-code ; https://lmstudio.ai/docs/integrations/codex ; https://aider.chat/docs/llms/lm-studio.html  | verificado: sim
    # Claude: a doc pede CLAUDE_CODE_ATTRIBUTION_HEADER=0. Contexto > ~25k. Com "Require Authentication", trocar o token.
    # Codex: "--oss" usa POST /v1/responses; sem -m baixa openai/gpt-oss-20b.
    # Aider: LM_STUDIO_API_KEY obrigatório mesmo sem auth; prefixo "lm_studio/".
    [providers.lmstudio]
    name   = "LM Studio"
    models = ["openai/gpt-oss-20b", "ibm/granite-4-micro"]

    [providers.lmstudio.for.claude]
    env = { ANTHROPIC_BASE_URL = "http://localhost:1234", ANTHROPIC_AUTH_TOKEN = "lmstudio", ANTHROPIC_API_KEY = "", CLAUDE_CODE_ATTRIBUTION_HEADER = "0" }

    [providers.lmstudio.for.codex]
    args = ["--oss", "-c", "oss_provider=\"lmstudio\""]

    [providers.lmstudio.for.opencode]
    env = {}

    [providers.lmstudio.for.qwen]
    env = { OPENAI_API_KEY = "lmstudio", OPENAI_BASE_URL = "http://localhost:1234/v1" }

    [providers.lmstudio.for.aider]
    env = { LM_STUDIO_API_BASE = "http://localhost:1234/v1", LM_STUDIO_API_KEY = "dummy-api-key" }

    [providers.lmstudio.for.goose]
    env = { GOOSE_PROVIDER = "lmstudio" }


    # Fonte: https://docs.vllm.ai/en/latest/serving/integrations/claude_code/ ; https://opencode.ai/docs/providers/  | verificado: sim
    # Servidor: vllm serve <modelo> --served-model-name my-model --enable-auto-tool-choice --tool-call-parser <parser>.
    # IDs com "/" (ID cru do HF) não funcionam no Claude Code: usar o --served-model-name.
    # OpenCode: autodescoberta em 127.0.0.1:8000, mas com tools desligadas por padrão.
    [providers.vllm]
    name   = "vLLM"
    models = ["my-model"]

    [providers.vllm.for.claude]
    env = { ANTHROPIC_BASE_URL = "http://localhost:8000", ANTHROPIC_AUTH_TOKEN = "dummy", ANTHROPIC_API_KEY = "dummy", ANTHROPIC_DEFAULT_OPUS_MODEL = "my-model", ANTHROPIC_DEFAULT_SONNET_MODEL = "my-model", ANTHROPIC_DEFAULT_HAIKU_MODEL = "my-model" }

    [providers.vllm.for.opencode]
    env = {}

    [providers.vllm.for.qwen]
    env = { OPENAI_API_KEY = "dummy", OPENAI_BASE_URL = "http://localhost:8000/v1" }


    # Fonte: https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp ; https://github.com/ggml-org/llama.cpp/pull/17570  | verificado: parcial
    # llama-server tem /v1/messages desde jan/2026 (traduz para o pipeline OpenAI interno). Porta padrão 8080.
    # Token precisa ser não vazio no cliente. OpenCode: sem provider nativo (usar openai-compatible). Responses não confirmado.
    [providers.llamacpp]
    name   = "llama.cpp server"
    models = []

    [providers.llamacpp.for.claude]
    env = { ANTHROPIC_BASE_URL = "http://127.0.0.1:8080", ANTHROPIC_AUTH_TOKEN = "llamacpp", ANTHROPIC_API_KEY = "" }

    [providers.llamacpp.for.qwen]
    env = { OPENAI_API_KEY = "llamacpp", OPENAI_BASE_URL = "http://127.0.0.1:8080/v1" }


    # Fonte: https://www.jan.ai/docs/desktop/api-preference ; https://www.jan.ai/docs/desktop/agents  | verificado: parcial
    # Servidor local em http://127.0.0.1:1337 com /v1/messages compatível com Anthropic. Atalho oficial: "jan launch claude" (Jan >= 0.7.8).
    # Configuração manual do ANTHROPIC_BASE_URL não está documentada pela Jan. Porta é configurável.
    [providers.jan]
    name   = "Jan"
    models = []

    [providers.jan.for.claude]
    env = { ANTHROPIC_BASE_URL = "http://127.0.0.1:1337", ANTHROPIC_AUTH_TOKEN = "jan", ANTHROPIC_API_KEY = "" }

    [providers.jan.for.qwen]
    env = { OPENAI_API_KEY = "jan", OPENAI_BASE_URL = "http://127.0.0.1:1337/v1" }


    # Fonte: https://localai.io/blog/what-landed-in-localai-3-10/ (só o título lido)  | verificado: parcial
    # LocalAI 3.10 anunciou APIs Anthropic e Responses; rota /v1/messages vista em espelho do repositório. Porta padrão 8080.
    [providers.localai]
    name   = "LocalAI"
    models = []

    [providers.localai.for.claude]
    env = { ANTHROPIC_BASE_URL = "http://localhost:8080", ANTHROPIC_AUTH_TOKEN = "localai", ANTHROPIC_API_KEY = "" }

    [providers.localai.for.qwen]
    env = { OPENAI_API_KEY = "localai", OPENAI_BASE_URL = "http://localhost:8080/v1" }


    # =============================================================================
    # PESQUISADOS E DESCARTADOS
    # =============================================================================
    #
    # - GitHub Models: "As of July 30, 2026, GitHub Models has been fully retired" (docs.github.com/en/github-models/quickstart).
    #   Inferência, catálogo e BYOK desligados. Não mapear models.github.ai.
    # - xAI no Claude Code: a camada Anthropic (/v1/messages) consta como descontinuada; a referência atual só lista
    #   /v1/responses. Mantido só para Codex/OpenCode/Crush/Aider/Goose.
    # - Together, Cerebras, Groq, Nebius, Cohere, Mistral no Claude Code: nenhum endpoint Anthropic oficial encontrado.
    #   Together oferece só o wrapper "togetherlink" (gateway sem URL documentada) ou LiteLLM local.
    # - Google Gemini e Cohere no Codex: só chat/completions documentado; Codex atual exige Responses.
    # - Alibaba Coding Plan no Codex: a própria Alibaba diz que só funciona com wire_api="chat" + Codex 0.80.0.
    # - Qualquer config com wire_api="chat" (guias antigos de MiniMax, z.ai, Ollama, DashScope): removido do Codex atual
    #   ("wire_api = chat is no longer supported").
    # - Fireworks/DeepInfra/Novita/SiliconFlow/Requesty no Codex: Responses API não confirmada nas docs abertas.
    # - Claude Platform on AWS (CLAUDE_CODE_USE_ANTHROPIC_AWS + ANTHROPIC_AWS_WORKSPACE_ID): vi só o bloco de gateway;
    #   não mapeado por falta da página principal (code.claude.com/docs/en/claude-platform-on-aws).
    # - Perplexity (Sonar): modelos de busca, não de código.
    # - Hyperbolic: sem entrada no models.dev e doc não aberta; ficou só com Qwen (parcial). Candidato a remoção.
    # - mistral.rs, SGLang, Docker Model Runner, NVIDIA NIM self-hosted, Lemonade, Atomic Chat: também expõem
    #   /v1/messages ou OpenAI, mas ficaram fora do escopo pedido.
    # - Dezenas de revendas/roteadores do models.dev (302ai, aihubmix, poe, helicone, llmgateway, fastrouter,
    #   io-net, scaleway, ovhcloud, venice, wandb etc.): existem no catálogo do OpenCode com env própria
    #   (ex.: POE_API_KEY, HELICONE_API_KEY); não verificados individualmente.
    """###

    public static let themes = ###"""
    # Catálogo de temas do Bando.
    #
    # Fonte única: o binário embute este arquivo (scripts/gen-presets.py).
    # Temas do usuário ficam em ~/.config/bando/themes.toml e vencem estes.
    #
    # Campos:
    #   name        nome na tela
    #   appearance  "light" ou "dark" (define a cor do logo: preto no claro, branco no escuro)
    #   accent      cor de destaque da interface
    #   background, foreground, cursor, selection  cores do terminal
    #   ansi        16 cores: preto, vermelho, verde, amarelo, azul, magenta, ciano,
    #               branco, e as 8 versões claras na mesma ordem
    #
    # As cores de estado das sessões (esperando, pronto, erro...) seguem as cores
    # do sistema e não mudam com o tema, para manter o contraste e o significado.

    [themes.bando-escuro]
    name       = "Bando Escuro"
    appearance = "dark"
    accent     = "#E6E6E9"
    background = "#0B0B0D"
    foreground = "#E6E6E9"
    cursor     = "#FFFFFF"
    selection  = "#2A2A31"
    ansi = ["#1C1C21", "#FF6B6B", "#5AD17A", "#F2C94C", "#5B9DFF", "#C38BFF", "#4FD1D9", "#D7D7DC",
            "#55555F", "#FF8787", "#7BE495", "#FFD966", "#82B4FF", "#D4A5FF", "#76E0E6", "#FFFFFF"]

    [themes.bando-claro]
    name       = "Bando Claro"
    appearance = "light"
    accent     = "#111113"
    background = "#FFFFFF"
    foreground = "#111113"
    cursor     = "#111113"
    selection  = "#DADAE0"
    ansi = ["#111113", "#D1242F", "#1A7F37", "#9A6700", "#0969DA", "#8250DF", "#1B7C83", "#6E6E78",
            "#57575F", "#E5534B", "#2DA44E", "#BF8700", "#218BFF", "#A475F9", "#3192AA", "#A0A0A8"]

    [themes.dracula]
    name       = "Dracula"
    appearance = "dark"
    accent     = "#BD93F9"
    background = "#282A36"
    foreground = "#F8F8F2"
    cursor     = "#F8F8F2"
    selection  = "#44475A"
    ansi = ["#21222C", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
            "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5", "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF"]

    [themes.nord]
    name       = "Nord"
    appearance = "dark"
    accent     = "#88C0D0"
    background = "#2E3440"
    foreground = "#D8DEE9"
    cursor     = "#D8DEE9"
    selection  = "#434C5E"
    ansi = ["#3B4252", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#88C0D0", "#E5E9F0",
            "#4C566A", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#8FBCBB", "#ECEFF4"]

    [themes.gruvbox-escuro]
    name       = "Gruvbox Escuro"
    appearance = "dark"
    accent     = "#FABD2F"
    background = "#282828"
    foreground = "#EBDBB2"
    cursor     = "#EBDBB2"
    selection  = "#504945"
    ansi = ["#282828", "#CC241D", "#98971A", "#D79921", "#458588", "#B16286", "#689D6A", "#A89984",
            "#928374", "#FB4934", "#B8BB26", "#FABD2F", "#83A598", "#D3869B", "#8EC07C", "#EBDBB2"]

    [themes.gruvbox-claro]
    name       = "Gruvbox Claro"
    appearance = "light"
    accent     = "#076678"
    background = "#FBF1C7"
    foreground = "#3C3836"
    cursor     = "#3C3836"
    selection  = "#D5C4A1"
    ansi = ["#FBF1C7", "#CC241D", "#98971A", "#D79921", "#458588", "#B16286", "#689D6A", "#7C6F64",
            "#928374", "#9D0006", "#79740E", "#B57614", "#076678", "#8F3F71", "#427B58", "#3C3836"]

    [themes.solarized-escuro]
    name       = "Solarized Escuro"
    appearance = "dark"
    accent     = "#268BD2"
    background = "#002B36"
    foreground = "#839496"
    cursor     = "#93A1A1"
    selection  = "#073642"
    ansi = ["#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
            "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"]

    [themes.solarized-claro]
    name       = "Solarized Claro"
    appearance = "light"
    accent     = "#268BD2"
    background = "#FDF6E3"
    foreground = "#657B83"
    cursor     = "#586E75"
    selection  = "#EEE8D5"
    ansi = ["#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
            "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"]

    [themes.catppuccin-mocha]
    name       = "Catppuccin Mocha"
    appearance = "dark"
    accent     = "#CBA6F7"
    background = "#1E1E2E"
    foreground = "#CDD6F4"
    cursor     = "#F5E0DC"
    selection  = "#585B70"
    ansi = ["#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#BAC2DE",
            "#585B70", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#A6ADC8"]

    [themes.catppuccin-latte]
    name       = "Catppuccin Latte"
    appearance = "light"
    accent     = "#8839EF"
    background = "#EFF1F5"
    foreground = "#4C4F69"
    cursor     = "#DC8A78"
    selection  = "#ACB0BE"
    ansi = ["#5C5F77", "#D20F39", "#40A02B", "#DF8E1D", "#1E66F5", "#EA76CB", "#179299", "#ACB0BE",
            "#6C6F85", "#D20F39", "#40A02B", "#DF8E1D", "#1E66F5", "#EA76CB", "#179299", "#BCC0CC"]

    [themes.tokyo-night]
    name       = "Tokyo Night"
    appearance = "dark"
    accent     = "#7AA2F7"
    background = "#1A1B26"
    foreground = "#C0CAF5"
    cursor     = "#C0CAF5"
    selection  = "#283457"
    ansi = ["#15161E", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
            "#414868", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5"]

    [themes.one-dark]
    name       = "One Dark"
    appearance = "dark"
    accent     = "#61AFEF"
    background = "#282C34"
    foreground = "#ABB2BF"
    cursor     = "#528BFF"
    selection  = "#3E4451"
    ansi = ["#282C34", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#ABB2BF",
            "#5C6370", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#FFFFFF"]

    [themes.github-escuro]
    name       = "GitHub Escuro"
    appearance = "dark"
    accent     = "#58A6FF"
    background = "#0D1117"
    foreground = "#E6EDF3"
    cursor     = "#E6EDF3"
    selection  = "#1F3A5F"
    ansi = ["#484F58", "#FF7B72", "#3FB950", "#D29922", "#58A6FF", "#BC8CFF", "#39C5CF", "#B1BAC4",
            "#6E7681", "#FFA198", "#56D364", "#E3B341", "#79C0FF", "#D2A8FF", "#56D4DD", "#FFFFFF"]

    [themes.github-claro]
    name       = "GitHub Claro"
    appearance = "light"
    accent     = "#0969DA"
    background = "#FFFFFF"
    foreground = "#1F2328"
    cursor     = "#1F2328"
    selection  = "#B6E3FF"
    ansi = ["#24292F", "#CF222E", "#116329", "#4D2D00", "#0969DA", "#8250DF", "#1B7C83", "#6E7781",
            "#57606A", "#A40E26", "#1A7F37", "#633C01", "#218BFF", "#A475F9", "#3192AA", "#8C959F"]

    [themes.monokai]
    name       = "Monokai"
    appearance = "dark"
    accent     = "#A6E22E"
    background = "#272822"
    foreground = "#F8F8F2"
    cursor     = "#F8F8F0"
    selection  = "#49483E"
    ansi = ["#272822", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F8F8F2",
            "#75715E", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F9F8F5"]
    """###

    public static let prices = ###"""
    # Preços dos modelos, em US$ por milhão de tokens, e janela de contexto.
    #
    # Fonte: tabela de modelos atuais da Anthropic (consultada em 06/10/2026).
    # Cache: escrita 5 min = 1,25× a entrada, escrita 1 h = 2× a entrada, leitura
    # conforme a tabela oficial de cada modelo (ou 0,1× a entrada quando não informada).
    #
    # O nome do modelo no transcript é comparado pelo prefixo mais longo
    # ("claude-opus-5-5" vale para "claude-opus-5-5[1m]" e afins).
    # Ajuste ou acrescente modelos em ~/.config/bando/prices.toml (vence este arquivo).
    # Providers com preço próprio (OpenRouter, Bedrock...) podem ter valores diferentes.

    [models."claude-fable-5-1"]
    input = 10.0
    output = 50.0
    cache_write_5m = 12.5
    cache_write_1h = 20.0
    cache_read = 0.25
    context = 1000000

    [models."claude-fable-5"]
    input = 10.0
    output = 50.0
    cache_write_5m = 12.5
    cache_write_1h = 20.0
    cache_read = 1.0
    context = 1000000

    [models."claude-mythos-5"]
    input = 10.0
    output = 50.0
    cache_write_5m = 12.5
    cache_write_1h = 20.0
    cache_read = 1.0
    context = 1000000

    [models."claude-opus-5-5"]
    input = 4.0
    output = 20.0
    cache_write_5m = 5.0
    cache_write_1h = 8.0
    cache_read = 0.2
    context = 1000000

    [models."claude-opus-5"]
    input = 5.0
    output = 25.0
    cache_write_5m = 6.25
    cache_write_1h = 10.0
    cache_read = 0.5
    context = 1000000

    [models."claude-opus-4-8"]
    input = 5.0
    output = 25.0
    cache_write_5m = 6.25
    cache_write_1h = 10.0
    cache_read = 0.5
    context = 1000000

    [models."claude-opus-4-7"]
    input = 5.0
    output = 25.0
    cache_write_5m = 6.25
    cache_write_1h = 10.0
    cache_read = 0.5
    context = 1000000

    [models."claude-opus-4-6"]
    input = 5.0
    output = 25.0
    cache_write_5m = 6.25
    cache_write_1h = 10.0
    cache_read = 0.5
    context = 1000000

    [models."claude-opus-4-5"]
    input = 5.0
    output = 25.0
    cache_write_5m = 6.25
    cache_write_1h = 10.0
    cache_read = 0.5
    context = 200000

    [models."claude-opus-4"]
    input = 15.0
    output = 75.0
    cache_write_5m = 18.75
    cache_write_1h = 30.0
    cache_read = 1.5
    context = 200000

    [models."claude-sonnet-5-5"]
    input = 2.0
    output = 10.0
    cache_write_5m = 2.5
    cache_write_1h = 4.0
    cache_read = 0.2
    context = 1000000

    [models."claude-sonnet-5"]
    input = 2.0
    output = 10.0
    cache_write_5m = 2.5
    cache_write_1h = 4.0
    cache_read = 0.2
    context = 1000000

    [models."claude-sonnet-4-6"]
    input = 3.0
    output = 15.0
    cache_write_5m = 3.75
    cache_write_1h = 6.0
    cache_read = 0.3
    context = 1000000

    [models."claude-sonnet-4"]
    input = 3.0
    output = 15.0
    cache_write_5m = 3.75
    cache_write_1h = 6.0
    cache_read = 0.3
    context = 200000

    [models."claude-haiku-5-5"]
    input = 0.1
    output = 0.5
    cache_write_5m = 0.125
    cache_write_1h = 0.2
    cache_read = 0.01
    context = 1000000

    [models."claude-haiku-4-5"]
    input = 1.0
    output = 5.0
    cache_write_5m = 1.25
    cache_write_1h = 2.0
    cache_read = 0.1
    context = 200000
    """###
}
