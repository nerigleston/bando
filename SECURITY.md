# Segurança

## Como relatar

Não abra issue pública para falha de segurança. Use o relato privado do GitHub: aba **Security** do repositório > **Report a vulnerability**.

Inclua o que for possível: versão do Bando (menu Bando > Sobre), macOS, passos para reproduzir e o impacto.

A resposta inicial vem em até 7 dias. A correção sai numa versão nova, que chega a quem usa o Bando pela atualização automática.

## O que é sensível no Bando

- Chaves de providers ficam no Keychain do macOS e só entram no ambiente do processo do agente. Qualquer caminho que as grave em arquivo, log, argumento de processo ou banco é falha de segurança.
- Atualizações são conferidas pela assinatura EdDSA do Sparkle. Qualquer forma de instalar uma versão sem assinatura válida é falha de segurança.
