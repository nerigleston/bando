# CLAUDE.md

Instruções para o Claude Code trabalhar neste repositório.

## O projeto

Bando é um orquestrador de agentes de código para macOS: app nativo (SwiftUI + SwiftTerm) e CLI (`bando`) que criam sessões em git worktree + tmux e rodam qualquer agente configurado em TOML, com providers configuráveis.

Leia `doc/PLANO.md` antes de qualquer mudança de arquitetura. Ele tem as metas, as fases e as decisões tomadas.

## Idioma

- Respostas, documentação, mensagens de commit e textos de interface em português do Brasil, com acentuação correta.
- Identificadores de código, nomes de arquivos e chaves de configuração em inglês.

## Stack

- Swift 6, Swift Package Manager, macOS 14+.
- Targets: `BandoCore` (biblioteca, sem dependência de UI), `BandoApp` (app SwiftUI; o executável vira `Bando` dentro do .app), `bando` (CLI). O target do app não se chama `Bando` porque colidiria com `bando` no disco do macOS, que não diferencia maiúsculas.
- SwiftTerm para o terminal embutido, TOMLKit para config, Sparkle para atualização, swift-argument-parser no CLI. GRDB (SQLite) entra na fase 1.
- tmux externo, sempre com servidor próprio: `tmux -L bando`.
- Antes de usar API de SwiftTerm, GRDB ou TOMLKit, consulte a documentação atual pelo Context7.

## Regras de arquitetura

1. **Sem daemon.** Nada fica rodando em segundo plano além do tmux. App e CLI leem e gravam o SQLite e se avisam por Darwin notification (`notify_post`).
2. **Sem polling.** Mudança de estado chega por hook do agente, hook do tmux (`alert-silence`, `alert-activity`, `pane-died`) ou FSEvents. Não use `Timer` para checar estado.
3. **`BandoCore` não importa SwiftUI nem AppKit.** Toda regra de negócio fica nele; app e CLI só chamam.
4. **Agentes e providers vêm de config.** Nunca escreva `if agent == "claude"` fora do código de presets de hooks. Comportamento específico de agente vai para o TOML ou para o preset.
5. **Segredos só no Keychain.** Nunca grave chave em TOML, SQLite, log, argumentos de processo ou ambiente do tmux. Quem lê o Keychain é o `bando run`, logo antes do `exec` do agente.
6. **Hooks em modo de acréscimo.** Ao instalar hooks em agentes (por exemplo `~/.claude/settings.json`), acrescente; nunca remova nem sobrescreva hooks de terceiros. O hook só age se `BANDO_SESSION_ID` estiver definido.
7. **Presets vêm de `catalog/`.** Nunca edite `Presets.swift` à mão: edite `catalog/*.toml` e rode `scripts/gen-presets.py`.
8. **Arquivos do usuário são intocáveis em atualizações.** `~/.config/bando/*.toml` só é escrito quando o usuário salva na tela de configurações ou roda `bando config init` (que nunca sobrescreve). Entrada inválida vira `ConfigIssue` e é pulada; nunca impede o app de abrir. Campos novos precisam ser opcionais no TOML.
9. **Apagar com trava.** Remover worktree recusa quando há mudança não commitada ou commit sem push, a menos que o usuário confirme.

## Desempenho

Metas (ver `doc/PLANO.md`, seção 2): app com 5 sessões abaixo de 80 MB de RAM, CPU 0% com agentes ociosos, `.app` com até 25 MB.

- Rode `scripts/bench.sh` ao terminar mudanças na UI ou no ciclo de vida das sessões e anote em `doc/medicoes.md`.
- Não adicione dependência nova sem dizer quanto ela soma no binário e na RAM.
- Terminais de sessões fora da tela devem ser desanexados (o tmux mantém o processo; o SwiftTerm não precisa ficar vivo).

## Comandos

```bash
swift build
scripts/test.sh              # use este, não `swift test`: com só Command Line Tools o framework Testing fica fora do caminho padrão
swift run bando <comando>
python3 -I scripts/gen-presets.py [--check]
scripts/build-app.sh
scripts/bench.sh [segundos] [nota]
```

Testes usam Swift Testing (`import Testing`, `@Test`, `#expect`).

## Ferramentas parecidas

O Bando se compara a outras ferramentas de agentes em paralelo (ver `doc/pesquisa-ux.md`). Não copie código, textos nem recursos visuais de nenhuma delas. Nunca coloque no repositório dados pessoais de quem usa (caminhos, sessões, nomes de projetos ou clientes).

## Estilo de escrita

Sem travessão no meio da frase, sem "não é X, é Y", sem palavras infladas (robusto, crucial, poderoso...), sem emoji decorativo. Frases curtas, números e nomes concretos.

## Commits

Mensagens em português, no imperativo, curtas ("Adiciona leitura do providers.toml"). Só faça commit quando o usuário pedir.
