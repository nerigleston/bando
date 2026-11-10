# Como contribuir

Obrigado por querer ajudar. Issues e PRs são bem-vindos, em português ou inglês.

## Antes de começar

- Para mudança grande (recurso novo, troca de arquitetura), abra uma issue primeiro para conversar. Correções pequenas podem ir direto em PR.
- Leia o [CLAUDE.md](CLAUDE.md): ele tem as regras de arquitetura (sem daemon, sem polling, segredos só no Keychain, `BandoCore` sem UI) que valem para qualquer contribuição, feita por pessoa ou por agente.
- O plano e as decisões estão em [doc/PLANO.md](doc/PLANO.md).

## Montar e testar

Requisitos: macOS 14+, Swift 6.2+ (Xcode 26 ou Command Line Tools), tmux 3.3+ e git.

```bash
swift build
scripts/test.sh              # testes (Swift Testing); use este, não `swift test`
scripts/build-app.sh         # gera build/Bando.app
open build/Bando.app
```

Para não misturar com o seu Bando de uso diário, rode a cópia de desenvolvimento com pastas próprias:

```bash
BANDO_STATE_DIR=/tmp/bando-dev/state BANDO_CONFIG_DIR=/tmp/bando-dev/cfg open -n build/Bando.app
```

## Agente ou provider novo

A forma mais simples de contribuir. Não precisa escrever Swift:

1. Edite `catalog/agents.toml` ou `catalog/providers.toml`, seguindo as entradas que já existem.
2. Rode `python3 -I scripts/gen-presets.py` (gera `Sources/BandoCore/Config/Presets.swift`; nunca edite esse arquivo à mão).
3. Diga no PR como testou: qual versão da CLI, se o estado (trabalhando, esperando, pronto) aparece certo e se retomar funciona.

## O que um PR precisa ter

- `scripts/test.sh` passando e `python3 -I scripts/gen-presets.py --check` sem diferença (o CI confere os dois).
- Teste novo quando a mudança é em `BandoCore`.
- Textos de interface, documentação e mensagens de commit em português do Brasil, com acentuação. Identificadores de código em inglês.
- Commits no imperativo e curtos ("Adiciona leitura do providers.toml").
- Mudança visível na interface: uma captura de tela no PR.
- Dependência nova: diga quanto ela soma no tamanho do app e na memória.
- Nada de dados pessoais no repositório (caminhos, nomes de projetos, sessões, chaves).

## Estilo de escrita

Frases curtas e concretas, números em vez de adjetivos. Sem travessão no meio da frase, sem "não é X, é Y" e sem palavras infladas (robusto, poderoso, incrível).

## Segurança

Falha de segurança não vai em issue pública. Veja [SECURITY.md](SECURITY.md).

## Licença

Ao enviar um PR, você concorda que a contribuição seja distribuída sob a [licença MIT](LICENSE) do projeto.
