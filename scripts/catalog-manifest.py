#!/usr/bin/env python3 -I
"""Gera catalog.json: versão, data, hash e assinatura EdDSA de cada arquivo
do catálogo. O app só aplica um catálogo baixado se a assinatura bater com a
chave pública do Info.plist (a mesma do Sparkle).

Uso: catalog-manifest.py <pasta> <arquivo-chave> <caminho do sign_update> <versão>
"""
import datetime, hashlib, json, pathlib, re, subprocess, sys

folder, key, sign_update, version = sys.argv[1:5]
files = {}
for name in ("agents.toml", "providers.toml"):
    path = pathlib.Path(folder) / name
    data = path.read_bytes()
    out = subprocess.run([sign_update, "--ed-key-file", key, str(path)],
                         check=True, capture_output=True, text=True).stdout
    sig = re.search(r'sparkle:edSignature="([^"]+)"', out)
    if not sig:
        sys.exit(f"sign_update não devolveu assinatura para {name}: {out!r}")
    files[name] = {"sha256": hashlib.sha256(data).hexdigest(),
                   "size": len(data), "edSignature": sig.group(1)}

print(json.dumps({
    "schema": 1,
    "appVersion": version,
    "publishedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "files": files,
}, indent=2, ensure_ascii=False))
