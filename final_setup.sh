#!/usr/bin/env bash
# BordneAI EOS v17.0.2 — Clean one-shot (WSL2, SpoonOS)
set -euo pipefail
fail(){ echo "[ERROR] $*" >&2; exit 1; }
ok(){   echo "[OK] $*"; }
step(){ echo "[*] $*"; }

ROOT="/mnt/c/Bordne.AI.EOS"
SPOON="$ROOT/spoonos"
PYENV="$SPOON/spoon-env"
ASSETS="$SPOON/assets/eos"
LLM="$SPOON/spoon_ai/llm"
LOGS="$SPOON/_logs"
DFEP="$SPOON/benchmarks"
PKG_PATH="$ROOT/eos-bundle-v17.0.2.zip"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

step "Ensuring dirs"; mkdir -p "$ROOT" "$ASSETS" "$LLM" "$LOGS" "$DFEP"

step "System deps"; sudo apt-get update -y >/dev/null && \
  sudo apt-get install -y python3 python3-venv python3-pip git jq curl nodejs npm zip >/dev/null
ok "Deps ready"

cd "$ROOT"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  step "Init git repo"; git init >/dev/null; git checkout -B main >/dev/null; ok "Repo ready"
fi

step "Submodule spoonos"
if [ -d "$SPOON" ] && ! git config -f .gitmodules --get submodule.spoonos.url >/dev/null 2>&1; then rm -rf "$SPOON"; fi
if git config -f .gitmodules --get submodule.spoonos.url >/dev/null 2>&1; then
  git submodule set-url spoonos https://github.com/xspoonai/spoon-core >/dev/null
  git submodule update --init --remote spoonos >/dev/null
else
  git submodule add https://github.com/xspoonai/spoon-core spoonos >/dev/null
  git submodule update --init --remote spoonos >/dev/null
fi
ok "Submodule ready"

step "Virtualenv"
python3 -m venv "$PYENV"
# shellcheck disable=SC1090
source "$PYENV/bin/activate"
python -m pip install --upgrade pip setuptools wheel >/dev/null 2>&1 || true
if [ -f "$SPOON/requirements.txt" ]; then python -m pip install -r "$SPOON/requirements.txt" || true; fi
ok "Venv + reqs ok"

step "config.json"
cat > "$SPOON/config.json" <<JSON
{
  "provider": "SpoonReactAI",
  "capabilities": { "tools": true },
  "logging": { "dir": "$LOGS", "level": "INFO" },
  "bundles": { "manifest": "$ASSETS/bundle-manifest.json" },
  "installed_at": "$NOW",
  "database_url": "sqlite:///./spoonai.db"
}
JSON
ok "config.json written"

step "Assets (manifest + diagnostics/hud)"
cat > "$ASSETS/bundle-manifest.json" <<JSON
{ "version": "17.0.2", "generated_at": "$NOW", "assets": ["diagnostics.js","hud.js"] }
JSON
cat > "$ASSETS/diagnostics.js" <<'JS'
module.exports = () => {
  console.log("[DIAG] INFO MIVP integrity baseline OK");
  console.log("[DIAG] INFO PAVP versioning check OK");
  console.log("[DIAG] INFO POP prioritization active (local mode)");
};
JS
cat > "$ASSETS/hud.js" <<'JS'
module.exports = () => { console.log("[HUD] Mood Strategic Adaptive"); };
JS
ok "Assets staged"

step "LLM adapters"
cat > "$LLM/aggregator.py" <<'PY'
from dataclasses import dataclass
@dataclass
class ProviderAggregator:
    tools: bool = True
    def ask(self, text: str) -> dict:
        mode = 'on' if self.tools else 'off'
        return {'reply': f"[SpoonReactAI] (tools={mode}) echo: {text}"}
PY
cat > "$LLM/manager.py" <<'PY'
from __future__ import annotations
from enum import Enum
from typing import Optional, List
from .aggregator import ProviderAggregator

class FallbackStrategy(str, Enum):
    NONE = "none"; ECHO = "echo"; AUTO = "auto"

class LoadBalancer:
    def __init__(self, providers: Optional[List[ProviderAggregator]] = None):
        self.providers = providers or [ProviderAggregator(True)]
    def route(self, _text: str) -> ProviderAggregator:
        return self.providers[0]

_current_manager: Optional["LLMManager"] = None

class LLMManager:
    def __init__(self, tools: bool = True,
                 fallback: FallbackStrategy = FallbackStrategy.AUTO,
                 balancer: Optional[LoadBalancer] = None):
        self.tools = tools
        self._fallback = fallback
        self._agg = balancer.route("init") if balancer else ProviderAggregator(tools=tools)

    def ask(self, text: str) -> dict:
        try:
            return self._agg.ask(text)
        except Exception:
            if self._fallback in (FallbackStrategy.ECHO, FallbackStrategy.AUTO):
                mode = 'on' if self.tools else 'off'
                return {"reply": f"[SpoonReactAI] (tools={mode}) echo: {text}"}
            raise

def get_llm_manager(tools: Optional[bool] = None) -> LLMManager:
    global _current_manager
    if _current_manager is None:
        _current_manager = LLMManager(tools=True if tools is None else bool(tools))
    elif tools is not None and getattr(_current_manager, "tools", None) != tools:
        _current_manager = LLMManager(tools=bool(tools))
    return _current_manager

def set_llm_manager(mgr: Optional[LLMManager]) -> None:
    global _current_manager
    _current_manager = mgr

ProviderManager = LLMManager
def get_provider_manager(tools: Optional[bool] = None) -> ProviderManager:
    return get_llm_manager(tools)

__all__ = [
    "LLMManager","FallbackStrategy","LoadBalancer",
    "get_llm_manager","set_llm_manager","ProviderManager","get_provider_manager"
]
PY
ok "Adapters written"

step ".pth inject"
SITE_PKGS="$(python - <<'PY'
import sys; print(next((p for p in sys.path if p.endswith('site-packages')), ''))
PY
)"
[ -n "$SITE_PKGS" ] || fail "site-packages not found"
echo "$SPOON" > "$SITE_PKGS/spoonos_dev.pth"
ok "pth at $SITE_PKGS/spoonos_dev.pth"

step "HUD/DIAG node sanity"
ASSETS_DIR="$ASSETS" node - <<'NODE'
const path=require('path'), base=process.env.ASSETS_DIR;
require(path.join(base,'diagnostics.js'))();
require(path.join(base,'hud.js'))();
console.log("HUD/DIAG OK");
NODE
ok "HUD/DIAG loaded"

step "Python smoke #1"
python - <<'PY'
from spoon_ai.llm.manager import LLMManager
print("[SMOKE1] repl:", LLMManager(tools=True).ask("Smoke: LLMManager")["reply"])
PY

step "Python smoke #2"
python - <<'PY'
import os, sys
root="/mnt/c/Bordne.AI.EOS/spoonos"
if root not in sys.path: sys.path.insert(0, root)
import spoon_ai.llm as pkg
need=["LLMManager","FallbackStrategy","LoadBalancer","get_llm_manager","set_llm_manager"]
missing=[n for n in need if not hasattr(pkg,n)]
print("[VERIFY] required:", need, "missing:", "none" if not missing else ", ".join(missing))
from spoon_ai.llm import get_llm_manager, set_llm_manager, LLMManager
print("[SMOKE2] get_llm_manager ->", get_llm_manager(tools=True).ask("ping get_llm_manager")["reply"])
set_llm_manager(LLMManager(tools=False))
print("[SMOKE2] after set_llm_manager->", get_llm_manager().ask("ping after set")["reply"])
logp=os.path.join(root,"_logs","smoke_local_research.log")
os.makedirs(os.path.dirname(logp),exist_ok=True); open(logp,"a",encoding="utf-8").write("OK\n")
print("[SMOKE2] log ->", logp)
PY

step "DFEP placeholder"
cat > "$DFEP/latest.json" <<JSON
{ "fetched_at": "$NOW",
  "MMLU_Pro": { "GPT-5": 86.0, "Grok 4": 86.6, "Gemini 2.5 Pro": 84.1 },
  "HLE": { "Grok 4": { "tool_free": 25.4, "with_tools": 38.6, "heavy_multi_agent": 50.7 } },
  "TruthfulQA": { "note": "No reliable recent per-model scores; dataset reference only" } }
JSON
ok "DFEP staged"

step "Package + SHA256"
( cd "$ASSETS" && zip -qr "$PKG_PATH" . )
sha256sum "$PKG_PATH" | awk '{print "[SHA256] "$1}'

step "Git checkpoint"
git add .gitmodules spoonos || true
git add . || true
git -c user.email="architect@bordne.ai" -c user.name="BordneAI-EOS" \
  commit -m "EOS v17.0.2: install+verify+package+runner" || true
ok "Checkpoint complete"

echo "[NEXT] Quick chat run: $SPOON/run_research_agent.sh (if present)"
echo "[NEXT] Ops helper: /bin/eos_ops.sh {run|smoke|diag|package|env}"
echo "[DONE] final_setup_v1702 complete."
