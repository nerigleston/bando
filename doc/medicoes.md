# Medições

Geradas por `scripts/bench.sh`. Meta (PLANO.md, seção 2): footprint até 80 MB com grade 2×2 e 5 sessões, CPU parada com agentes ociosos, .app até 25 MB.

| Data | Versão | Footprint | Pico | RSS | CPU (tempo acumulado) | tmux | .app | Nota |
|---|---|---|---|---|---|---|---|---|
| 2026-11-09 14:38 | 0.1.0-dev | 42.6M | 90.0M | 104M |   0:00.32 →   0:00.33 em 20s | 6M | 12M | fase 0: lista de agentes + 1 terminal zsh |
| 2026-11-09 17:40 | 0.1.0-dev | 110.4M | - | - | ~3% com 1 agente imprimindo sem parar | - | 28M | grade 2×2 com 4 agentes reais (Codex, Gemini, OpenCode, estresse); meta de 80 MB não atingida, terminais SwiftTerm ~7-8 MB cada |
| 2026-11-09 17:40 | 0.1.0-dev | supervisor 6.5M estável por 5 min | - | - | 0,36 s em 5 min | - | - | supervisor (bando run) com agente imprimindo sem parar, depois da correção do vazamento |
