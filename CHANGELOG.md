# Mudanças

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
