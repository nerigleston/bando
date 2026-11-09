# Mudanças

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

- Corrige "Não foi possível buscar atualizações": faltava conferir o pacote antes de extrair, exigência do Sparkle para feed assinado. Quem tem a 0.1.1 ou a 0.1.2 precisa reinstalar uma vez (`curl -fsSL https://bando-releases.s3.amazonaws.com/install.sh | bash`); daí em diante o app se atualiza sozinho.
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
