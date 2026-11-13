# Mudanças

## 0.1.34

- Imagem colada com ⌘V na tarefa da nova sessão (e no campo do projeto) vira um PNG e entra como caminho do arquivo. Antes o campo ignorava a imagem. Arquivo copiado no Finder entra pelo caminho.
- Configurar projeto (botão de engrenagem na página do projeto): script de setup do worktree e branch base, que antes só existiam pelo CLI. O setup roda uma vez por worktree; trocar de agente não repete.
- `.worktreeinclude` na raiz do repositório (sintaxe do `.gitignore`, a mesma convenção do Codex): arquivos ignorados que casam com ele são copiados para o worktree novo, além dos `.env`.
- Pergunta de confiança do Claude Code no worktree: se o repositório principal (ou uma pasta acima) já é confiável no `~/.claude.json`, o Bando responde sim, uma vez, no primeiro minuto. O Bando só lê esse arquivo. Sem confiança prévia, a pergunta continua para você.

## 0.1.33

- Nome da sessão sem custo: o Bando lê o título que o agente escreve no terminal (o Claude Code põe "✳ resumo", o Codex põe o nome da conversa). O padrão de cada agente fica no catálogo (`terminal_title`). Para esses agentes, o título por modelo só é pedido se depois de 30 segundos o agente ainda não tiver dado nome.
- Branch com nome legível: o nome inicial tira palavras vazias e fica com até 5 palavras (`bando/veniti-seja-irreconhecivel-b10f` em vez de `bando/veja-o-veniti-pfvr-quero-que-seja-irreco-b10f`). Quando a sessão ganha título, o branch passa a usá-lo (`bando/novo-robo-veniti-6c19`), uma vez só e só se ainda não foi enviado ao remoto. A pasta do worktree mantém o nome inicial.
- Cópia pedida pelo agente (OSC 52) chega à área de transferência. O tmux do Bando descartava essa cópia.

## 0.1.32

- Links clicáveis também no OpenCode: dentro do tmux ele desligava os links OSC 8. As sessões recebem `FORCE_HYPERLINK=1` (a menos que você já defina outro valor), e o ⌘+clique abre o link. O Antigravity já liga os links sozinho quando o tmux anuncia suporte, o que a 0.1.31 passou a fazer. Codex e Gemini CLI mostram o endereço por extenso, que já abria com ⌘+clique.

## 0.1.31

- ⌘+clique abre os links com texto do agente (como as fontes que o Claude Code lista). O tmux descartava o endereço desses links (OSC 8) e só o texto azul chegava ao terminal. O Bando agora liga os hyperlinks no servidor tmux dele, também para sessões já abertas depois que o terminal reconecta.

## 0.1.30

- Texto copiado de uma sessão e colado fora do Bando mantém os acentos. Com o app aberto pelo Dock ou pelo Finder, as sessões rodavam sem `LANG`, e o `pbcopy` do agente gravava o texto como Mac Roman ("só" virava "s√≥"). Agora toda sessão recebe um `LANG` UTF-8 (o idioma do macOS, ou `en_US.UTF-8`), inclusive o shell que fica depois que o agente sai. Sessões já abertas pegam a correção ao parar e retomar.

## 0.1.29

- O painel de arquivos mostra tudo, inclusive o que o git ignora (`.env`, `node_modules`, `.venv`), mais apagado. Só `.git` e `.DS_Store` ficam escondidos.
- Sessão nova em worktree recebe os arquivos de ambiente da pasta principal que o git ignora (`.env`, `.env.local`, `.env-all`, `api/.env`...). Antes o worktree nascia sem eles. Arquivos dentro de pastas ignoradas ficam de fora, e nada é sobrescrito.

## 0.1.28

- Na troca de agente, você escolhe quem escreve o resumo: o agente que sai ou o que entra. Com "escrito pelo novo agente", o Bando exporta a conversa para `.bando/conversa.md` e o agente que entra lê, escreve `.bando/handoff.md` e segue. Funciona mesmo com o agente anterior parado ou sem limite. No terminal: `bando swap --levar resumo-novo`. A exportação só existe a partir do Claude Code.
- Com "escrito pelo agente atual" e o agente parado, o novo agente passa a resumir a conversa exportada em vez de começar só com a tarefa.

## 0.1.27

- Venice AI abre com o DeepSeek V4.1 Flash 1017 Uncensored como modelo padrão. A lista de modelos sugeridos foi atualizada com IDs atuais da Venice (Kimi K3.1 Pro, GLM 5.3, DeepSeek V4 Pro 0813, GPT-6 Sol e Claude Sonnet 5.5).

## 0.1.26

- Venice AI entra no catálogo de providers para Codex, OpenCode, Qwen Code e Goose. A chave fica no Keychain (`bando secret set bando/venice`). Claude Code fica de fora: a Venice não tem endpoint no formato da Anthropic.

## 0.1.25

- O visualizador de arquivos (aba ao lado do Terminal) edita e salva texto UTF-8, com desfazer (⌘Z), busca (⌘F) e ⌘S. A aba ganha um ponto quando há mudança não salva. Se o agente mudou o arquivo depois que você abriu, o Bando não sobrescreve sem perguntar: oferece Recarregar ou Sobrescrever. Arquivo que não é UTF-8 continua só leitura. Contribuição de @webdevpls (#5).
- A edição não salva sobrevive à troca para a aba Terminal e para outra sessão. Fechar o app ainda descarta o que não foi salvo.
- Salvar um link simbólico (por exemplo `CLAUDE.md` apontando para `AGENTS.md`) grava no arquivo de destino e mantém o link.

## 0.1.24

- Retomar volta a funcionar depois que o agente sai. O shell que fica no terminal da sessão impedia o `bando resume` (e o botão Retomar) de abrir o agente de novo, sem aviso. Agora esse shell é fechado e o agente abre na mesma conversa. Se houver outro programa rodando nesse terminal, o Bando avisa qual é e não fecha nada.

## 0.1.23

- Ao fechar e abrir o app, ele volta para a sessão que estava aberta (antes ia para a mais urgente). Grade, colunas e sessões da grade continuam guardadas.
- Cópias de teste do app (abertas com BANDO_STATE_DIR) usam preferências separadas e não mexem mais nas do Bando de uso diário.

## 0.1.22

- O título automático é gerado pelo agente e pelo provider da própria sessão (Claude Code, Codex, OpenCode ou Gemini CLI, com as chaves e o modelo padrão do provider), e não mais sempre pelo Claude. Com a conta do próprio agente, o Claude Code usa o Haiku. Agente sem pergunta única no catálogo (`title`) fica com o nome provisório.

## 0.1.21

- Menos memória: as conversas do Claude Code (algumas passam de 200 MB) eram lidas inteiras a cada resposta para o anel de contexto e o título. Agora são lidas em blocos de 1 MB, o contexto vem do fim do arquivo e os totais vêm do banco. Pico ao abrir caiu de ~530 MB para ~150 MB; uso estável de ~175 MB para ~145 MB com 3 terminais na grade.
- Caminho de imagem ou arquivo arrastado/colado entra como colagem de verdade (bracketed paste): o Claude Code transforma em anexo `[Image #N]`, como no Xirp.

## 0.1.20

- Imagem sem arquivo (print copiado, imagem arrastada do navegador ou da miniatura do print) vira um PNG em `$TMPDIR/bando-uploads/` e o caminho é colado no terminal, como no Xirp. Vale para ⌘V com imagem na área de transferência e para arrastar.
- Sessão criada de dentro do worktree de outra sessão fica no projeto do repositório. Antes o worktree virava um projeto à parte (com o nome dele, como `sessao-f380`).

## 0.1.19

Não publicada (o CI foi cancelado por um commit seguinte); entrou na 0.1.20.

- Arrastar arquivo ou pasta do Finder para o terminal cola o caminho, com espaços e caracteres especiais protegidos (vários de uma vez também). Imagem arrastada vira caminho que o Claude Code lê. Texto e links arrastados entram como estão. Nada é executado: o Enter é seu.

## 0.1.18

- Sessão aberta sem tarefa (vazia) ganha nome a partir da primeira mensagem escrita no agente, no fim da primeira resposta. Antes ficava "sessão 4f66".
- Menu de agente: botão de atualizar visível em todos os agentes instalados e "Atualizar todos os agentes".
- Modelo já vem preenchido com o da sessão ou o padrão do provider, e muda junto com o provider; lista com os modelos do provider.
- O provider padrão passa a se chamar "Conta do agente", com explicação: usa a conta ou a chave que a CLI já tem.

## 0.1.17

- Atualização pronta aparece no rodapé da lateral ("Bando X pronto · Reiniciar e instalar"), sem depender da permissão de notificação do macOS. Antes, sem essa permissão, a versão nova só entrava ao fechar o app, sem aviso.

## 0.1.16

- Reforma da interface: sessões em árvore sob o projeto na lateral, busca, modo Selecionar para parar ou apagar várias de uma vez, confirmação antes de parar ou apagar, modais e popovers no mesmo estilo e grade que escolhe o formato pela quantidade de sessões, com prévia ao arrastar. Contribuição de @webdevpls (#3).
- Painel de arquivos: o começo das linhas ficava escondido embaixo dos números de linha. Os números agora ficam numa coluna à parte.
- Troca de agente: o campo de modelo começa vazio (modelo padrão do agente) e mostra o modelo atual como dica.
- Botão de atualizar em cada agente instalado, na troca de agente. Roda o comando de atualização num Terminal à parte (ex.: `claude update`); agentes sem comando próprio rodam a instalação de novo. Campo novo `update` no `agents.toml`.

## 0.1.15

- Nome das sessões como no Xirp: um nome provisório na hora (começo da tarefa), depois o título que o Claude Code dá à conversa (inclusive o do /rename) ou, sem ele, um título curto gerado pelo Claude Haiku a partir da tarefa, no idioma dela. Nome dado por você nunca é trocado. O menu da sessão ganhou "Gerar nome de novo".
- Inclui o que estava na 0.1.13 e na 0.1.14 (painel de arquivos, microfone, Option no ABNT2), que não chegaram a ser publicadas: os testes travavam no CI.

## 0.1.14

Não publicada (testes travados no CI); entrou na 0.1.15.

- Microfone liberado para os agentes nas sessões (o ditado por voz do Claude Code, por exemplo): o macOS passa a pedir permissão em vez de negar. Contribuição de @webdevpls (#1).
- Option no teclado ABNT2 compõe o caractere no terminal (Option+Q = /, Option+W = ?). Option+Enter e Option+seta continuam como antes (#1).

## 0.1.13

Não publicada (testes travados no CI); entrou na 0.1.15.

- Painel de arquivos à direita da sessão (⌘E): árvore do worktree sem o que o git ignora, marcação do que mudou e visualização do arquivo em aba ao lado do terminal, com busca (⌘F). Só leitura.
- Testes do serviço de sessões: pasta sem git, worktree em repositório, projeto Geral, migração e importação do General do Xirp.

## 0.1.12

- Instalação e atualizações pelo domínio do site: `curl -fsSL https://bando.nerifilho.com.br/install.sh | bash` e download em https://bando.nerifilho.com.br/download.

## 0.1.11

- Com "baixar e instalar automaticamente" ligado, a versão nova era baixada e só entrava quando o app fechava, sem aviso. Agora chega a notificação "Bando X pronto para instalar", e o clique reinicia e instala na hora. O menu Bando também mostra "Reiniciar e instalar a X".

## 0.1.10

- "Não esmaecer os sem foco" fica salvo: antes voltava a esmaecer quando o app reabria (inclusive depois de atualizar).
- Menu da grade mais largo, sem textos cortados.

## 0.1.9

- Cmd+clique num caminho de arquivo no terminal mostra o arquivo no Finder (antes aparecia "Link blocked"). Vale para caminho absoluto, com ~, file:// ou relativo à pasta da sessão, mesmo com ponto final ou :linha:coluna no fim.

## 0.1.8

- Shift+Enter quebra a linha no agente (antes só Option+Enter). O Bando manda a mesma sequência do Option+Enter, que Claude Code e os outros agentes entendem.

## 0.1.7

- Corrige o fechamento inesperado do app: a tela consultava o tmux enquanto desenhava os painéis. Agora a consulta roda em segundo plano.
- O menu ⋯ da sessão volta a responder: o botão some com o mouse fora, e o menu aberto perdia a âncora.

## 0.1.6

- A linha da sessão na lateral não muda mais de altura quando o mouse passa por cima.

## 0.1.5

- "Geral": sessões fora de um projeto (na pasta pessoal) ficam num grupo próprio no topo da lateral, como o "General" do Xirp. Dá para abrir uma sessão nova nele pelo seletor de projeto.
- Pasta sem git não dá mais erro: a sessão roda direto nela, sem worktree.
- A página do projeto usa a largura toda da janela.
- `bando import xirp` traz as sessões do "General" do Xirp para o Geral, e `--so-sessoes` reimporta sem mexer em custos e PRs.

## 0.1.4

- Primeira versão entregue pela atualização automática (sem mudança de recurso).

## 0.1.3

- Corrige "Não foi possível buscar atualizações": faltava conferir o pacote antes de extrair, exigência do Sparkle para feed assinado. Quem tem a 0.1.1 ou a 0.1.2 precisa reinstalar uma vez (`curl -fsSL https://bando.nerifilho.com.br/install.sh | bash`); daí em diante o app se atualiza sozinho.
- Sessões cujo projeto foi removido aparecem em "Sem projeto" na lateral.
- Sessões escondidas ficam em "N ocultas", no fim da lateral.

## 0.1.2

- Grade com mais respiro: margem no terminal, cantos arredondados e espaço entre os painéis.
- Cabeçalho de cada painel com projeto e título num texto só, branch que some quando não cabe e ações ao passar o mouse.
- Clicar dentro do terminal de um painel move o foco para ele.
- O .dmg abre com o atalho para Aplicativos: é só arrastar.

## 0.1.1

Primeira versão publicada.

- Sessões em git worktree + tmux, com qualquer agente configurado em TOML (28 no catálogo) e 53 providers.
- Nova sessão numa caixa de texto central, página de cada projeto e lateral por projeto ou por estado.
- Grade até 4×4 com tamanhos ajustáveis, 15 temas, notificações e selo no Dock.
- Troca de agente na mesma sessão, com resumo ou conversa levados ao novo agente.
- MCP centralizado, uso e custo por sessão, relatórios por dia, semana, mês ou intervalo.
- Importação do Xirp (projetos, sessões, custos e PRs).
- Atualização automática: poucos minutos depois de uma versão nova sair, o app avisa (por notificação, se estiver em segundo plano) e instala com um clique.

## 0.1.0

Não publicada (o build universal falhou no CI).
