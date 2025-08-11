#!/usr/bin/env bash
set -euo pipefail
fail(){ echo "[ERROR] $*" >&2; exit 1; }
ok(){   echo "[OK] $*"; }
step(){ echo "[*] $*"; }




# ...paste the rest of your existing installer here...
