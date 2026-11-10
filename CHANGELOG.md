# Mudanças

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
