#!/usr/bin/env python3
import hashlib
import json
import pathlib

p = pathlib.Path("workflows/minimaxH3SEEDHUNTERLatent_v25.json")
data = json.loads(p.read_text(encoding="utf-8"))
nodes = data.get("nodes") or []

if len(nodes) < 400:
    raise SystemExit(f"Seed Hunter v2.5 validation failed: only {len(nodes)} nodes")

types = {str(n.get("type", "")) for n in nodes}
required_types = {"VHS_VideoCombine", "MiniMaxH3AddGuide"}
missing = required_types - types
if missing:
    raise SystemExit(
        "Seed Hunter v2.5 validation failed: missing node types "
        + ", ".join(sorted(missing))
    )

strings = []
for n in nodes:
    vals = n.get("widgets_values")
    if isinstance(vals, list):
        strings.extend(str(v) for v in vals if isinstance(v, str))
    elif isinstance(vals, dict):
        strings.extend(str(v) for v in vals.values() if isinstance(v, str))

joined = "\n".join(strings)
expected_model = "Minimax-h3_Singularity_ref2va_Pruned_v1.3_int8.safetensors"
if expected_model not in joined:
    raise SystemExit(
        "Seed Hunter v2.5 validation failed: expected Singularity v1.3 Pruned "
        "model selector not found"
    )

print("Seed Hunter v2.5 JSON validation: OK")
print("nodes:", len(nodes))
print("sha256:", hashlib.sha256(p.read_bytes()).hexdigest())
