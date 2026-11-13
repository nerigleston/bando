#!/usr/bin/env python3 -I
"""Gera Sources/BandoCore/Config/Presets.swift a partir de catalog/*.toml.

O catálogo é a fonte única dos presets. Rode depois de editar catalog/ e
commite os dois. Com --check, só confere se o Swift está em dia (usado no CI
e nos testes).
"""
import pathlib, sys, tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources/BandoCore/Config/Presets.swift"
DELIM = "###"

def body(name):
    text = (ROOT / "catalog" / f"{name}.toml").read_text(encoding="utf-8")
    tomllib.loads(text)  # falha cedo se o TOML estiver quebrado
    if f'"{DELIM}' in text:
        sys.exit(f"catalog/{name}.toml contém {DELIM!r}; troque o delimitador")
    return "\n".join(("    " + l) if l else "" for l in text.rstrip("\n").split("\n"))

swift = f'''// Gerado por scripts/gen-presets.py a partir de catalog/. Não edite à mão.

/// Presets embutidos no binário. Os arquivos do usuário em `~/.config/bando/`
/// sobrescrevem campo a campo; um agente ou provider novo só precisa existir lá.
public enum Presets {{
    public static let agents = {DELIM}"""
{body("agents")}
    """{DELIM}

    public static let providers = {DELIM}"""
{body("providers")}
    """{DELIM}

    public static let themes = {DELIM}"""
{body("themes")}
    """{DELIM}

    public static let prices = {DELIM}"""
{body("prices")}
    """{DELIM}

    public static let compressors = {DELIM}"""
{body("compressors")}
    """{DELIM}
}}
'''

if "--check" in sys.argv:
    if OUT.read_text(encoding="utf-8") != swift:
        sys.exit("Presets.swift desatualizado: rode scripts/gen-presets.py")
    print("Presets.swift em dia")
else:
    OUT.write_text(swift, encoding="utf-8")
    print(f"gerado {OUT.relative_to(ROOT)}")
