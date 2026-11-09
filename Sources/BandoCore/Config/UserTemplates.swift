/// Conteúdo inicial de `bando config init`. Só comentários e exemplos: um
/// arquivo vazio de entradas não muda nada nos presets.
public enum UserTemplates {
    public static let agents = #"""
    # Agentes do Bando: seus e personalizações dos presets.
    #
    # Este arquivo é seu. O app nunca o sobrescreve, nem em atualizações.
    # Cada campo aqui vence o preset; campos ausentes continuam vindo do preset
    # (e recebem as correções das versões novas).
    #
    # Ver os presets embutidos:   bando config presets agents
    # Validar este arquivo:        bando config check
    #
    # Campos:
    #   name        nome na tela
    #   cmd         comando (pode ter $VAR e palavras extras: "goose session")
    #   prompt      argumentos para a tarefa inicial, com {prompt}
    #   prompt_via  "args" (padrão se houver prompt) ou "keys" (digita no terminal)
    #   fresh       argumentos só ao abrir sessão nova (ex.: ["--new"])
    #   assign_id   argumentos para o Bando escolher o ID da conversa: {new_id}
    #   resume      retomar conversa por ID: {native_id}
    #   fork        bifurcar a conversa {native_id} numa nova (fork da sessão)
    #   continue    continuar a última conversa
    #   model       argumentos de modelo: {model}
    #   args        argumentos sempre passados
    #   env         variáveis sempre definidas
    #   status      "hooks" | "output" | "silence" | "none"
    #   busy        regex do texto na tela quando está trabalhando (status output)
    #   waiting     regex do texto quando pede permissão/resposta (status output)
    #   idle_after  segundos sem saída até checar o estado (padrão 4)
    #   version     argumentos para mostrar a versão (padrão ["--version"])
    #   install     comando de instalação mostrado quando falta a CLI
    #   enabled     false esconde o agente
    #
    # Placeholders: {prompt} {model} {native_id} {new_id} {session_id} {worktree} {branch}
    # Um grupo de argumentos com placeholder sem valor é omitido inteiro.

    # Exemplo: mudar só o modelo padrão do Claude Code
    # [agents.claude]
    # args = ["--model", "claude-opus-5-5"]

    # Exemplo: agente novo
    # [agents.minha-cli]
    # name    = "Minha CLI"
    # cmd     = "minha-cli"
    # prompt  = ["--message", "{prompt}"]
    # status  = "output"
    # busy    = 'esc to interrupt'
    # waiting = '\(y/n\)'

    # Exemplo: esconder um preset
    # [agents.pi]
    # enabled = false
    """#

    public static let providers = #"""
    # Providers do Bando: de onde vem o modelo de cada agente.
    #
    # Este arquivo é seu. O app nunca o sobrescreve, nem em atualizações.
    #
    # Ver os presets embutidos:   bando config presets providers
    # Cadastrar uma chave:         bando secret set bando/<id>
    #
    # Valores em env:
    #   "keychain:<serviço>/<conta>"  lido do Keychain na hora de iniciar
    #   "env:<VAR>"                    copiado do seu ambiente
    #   qualquer outro texto           usado como está
    #
    # Chaves nunca ficam neste arquivo.
    #
    # Campos:
    #   name     nome na tela
    #   env      variáveis para todos os agentes
    #   args     argumentos para todos os agentes
    #   models   sugestões de modelo na tela
    #   agents   agentes liberados (vazio e sem [for] = todos)
    #   enabled  false esconde o provider
    #   [providers.<id>.for.<agente>]  env/args só para aquele agente

    # Exemplo: servidor próprio compatível com a API da Anthropic
    # [providers.meu-proxy]
    # name   = "Meu proxy"
    # models = ["meu-modelo"]
    # [providers.meu-proxy.for.claude]
    # env = { ANTHROPIC_BASE_URL = "https://llm.minhaempresa.com", ANTHROPIC_AUTH_TOKEN = "keychain:bando/meu-proxy" }
    """#

    public static let themes = #"""
    # Temas do Bando: seus temas e ajustes dos temas que vêm com o app.
    #
    # Este arquivo é seu. O app nunca o sobrescreve, nem em atualizações.
    # Ver os temas embutidos:  bando themes   e   bando config presets themes
    #
    # Campos: name, appearance ("light"/"dark"), accent, background, foreground,
    # cursor, selection, ansi (16 cores #RRGGBB), enabled, base.
    # "base" herda de outro tema: só os campos que você escrever mudam.

    # Exemplo: Dracula com fundo mais escuro
    # [themes.meu-dracula]
    # base       = "dracula"
    # name       = "Meu Dracula"
    # background = "#1B1C24"
    """#

    public static let mcp = #"""
    # Servidores MCP do Bando: cadastre uma vez, use em qualquer agente.
    #
    # Este arquivo é seu. O app nunca o sobrescreve.
    # O Bando entrega os servidores a cada sessão sem mexer nos arquivos de
    # configuração dos agentes (Claude Code, Codex, OpenCode e Gemini CLI).
    # Chaves: "keychain:<serviço>/<conta>" (cadastre com bando secret set).
    # Elas só chegam ao ambiente do processo do agente.
    #
    # Campos:
    #   name       nome na tela
    #   command    comando do servidor local (stdio)
    #   args       argumentos
    #   env        variáveis do servidor (valores podem ser keychain:/env:)
    #   url        servidor remoto (http por padrão; transport = "sse" se for SSE)
    #   headers    headers do servidor remoto (ex.: Authorization)
    #   agents     só para estes agentes (vazio = todos que suportam MCP)
    #   projects   só nestes projetos, por nome ou caminho (vazio = todos)
    #   enabled    false desliga sem apagar

    # Exemplo: servidor local
    # [mcp.github]
    # name    = "GitHub"
    # command = "npx"
    # args    = ["-y", "@modelcontextprotocol/server-github"]
    # env     = { GITHUB_PERSONAL_ACCESS_TOKEN = "keychain:bando/mcp-github" }

    # Exemplo: servidor remoto com chave no header
    # [mcp.context7]
    # url     = "https://mcp.context7.com/mcp"
    # headers = { CONTEXT7_API_KEY = "keychain:bando/mcp-context7" }
    """#

    /// Pedido de resumo enviado ao agente atual antes de trocar de agente.
    /// {arquivo} vira o caminho do arquivo de repasse.
    public static let handoffDefault = """
    Vamos trocar de agente nesta sessão. Antes, escreva o arquivo {arquivo} em Markdown para o próximo agente continuar sem perder contexto. Inclua, de forma objetiva:
    1. Objetivo e estado atual do trabalho.
    2. Comandos mais usados (build, testes, execução, deploy), exatamente como usamos aqui.
    3. Particularidades e decisões combinadas nesta conversa (o que fazer e o que evitar).
    4. Comandos ou passos específicos deste projeto.
    5. O que falta fazer e os próximos passos.
    6. Arquivos e pastas importantes.
    Depois de escrever o arquivo, não faça mais nada.
    """

    public static let handoff = #"""
    # Pedido de resumo que o Bando envia ao agente atual antes de trocar de agente.
    # Edite à vontade. Linhas começando com "#" são ignoradas.
    # {arquivo} vira o caminho do arquivo de repasse (.bando/handoff.md).

    """# + handoffDefault + "\n"
}
