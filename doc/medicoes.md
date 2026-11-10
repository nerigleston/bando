# Medições

Geradas por `scripts/bench.sh`. Meta (PLANO.md, seção 2): footprint até 80 MB com grade 2×2 e 5 sessões, CPU parada com agentes ociosos, .app até 25 MB.

| Data | Versão | Footprint | Pico | RSS | CPU (tempo acumulado) | tmux | .app | Nota |
|---|---|---|---|---|---|---|---|---|
| 2026-11-09 14:38 | 0.1.0-dev | 42.6M | 90.0M | 104M |   0:00.32 →   0:00.33 em 20s | 6M | 12M | fase 0: lista de agentes + 1 terminal zsh |
| 2026-11-09 17:40 | 0.1.0-dev | 110.4M | - | - | ~3% com 1 agente imprimindo sem parar | - | 28M | grade 2×2 com 4 agentes reais (Codex, Gemini, OpenCode, estresse); meta de 80 MB não atingida, terminais SwiftTerm ~7-8 MB cada |
| 2026-11-09 17:40 | 0.1.0-dev | supervisor 6.5M estável por 5 min | - | - | 0,36 s em 5 min | - | - | supervisor (bando run) com agente imprimindo sem parar, depois da correção do vazamento |
| 2026-11-10 00:26 | 0.1.0-dev | 98.4M | 114.0M | 141M |   0:00.99 →   0:04.92 em 30s | 13M | 31M | UI: lateral em árvore, modais, tooltip, grade adaptativa. Grade 3×1 com uma sessão do Claude gerando texto durante a medição, então a CPU não é de agentes ociosos |
| 2026-11-10 01:35 | 0.1.0-dev | 170.3M | 529.5M | 253M |   0:05.86 →   0:08.51 em 30s | 20M | 31M | 0.1.20 (main): grade com as sessões salvas, agentes ociosos; painel de arquivos, títulos automáticos |
| 2026-11-10 01:44 | 0.1.0-dev | 209.5M | 215.8M | 244M |   0:06.85 →   0:10.71 em 30s | 20M | 31M | leitura de transcript em blocos e contexto incremental (grade 4×1, 3 terminais, uma sessão gerando texto) |
| 2026-11-10 01:52 | 0.1.0-dev | 146.1M | 152.7M | 177M |   0:02.04 →   0:04.82 em 30s | 20M | 31M | contexto pelo fim do arquivo + totais do banco (grade 4×1, 3 terminais, uma sessão gerando texto) |
