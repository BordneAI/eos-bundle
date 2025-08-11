# BordneAI EOS v17.0.2 (WSL2 / SpoonOS)

**Status:** Green ✅ — local, cost-free agentic path using SpoonReactAI (mock).  
**Bundle SHA256:** `6641d873abae19bad49e07b050a7d0442cfdec7ddf957f417c52ec52a3b74f7d`

## Quick start
```bash
bash ./final_setup.sh
/bin/eos_ops.sh {run|smoke|diag|package|env}
```

## What's inside
- `spoonos/` (git submodule) — primary agent framework
- `spoonos/assets/eos/` — `diagnostics.js`, `hud.js` (manifest-driven)
- DFEP staging: `spoonos/benchmarks/latest.json`

> Note: submodule edits are local; see **Submodule strategy** below.

## Submodule strategy
Fork `xspoonai/spoon-core` → push branch `bordneai-eos-v1702` → update submodule pointer here for reproducible rollouts.
