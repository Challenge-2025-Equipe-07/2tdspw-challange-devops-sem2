#!/usr/bin/env bash
# =============================================================================
# Testes de API com Newman (Postman) — mínimo de 4 casos, aqui são 5:
# GET /tutores, login JWT, criar tutor, alterar tutor, criar pet.
# O register entra como preparo (200 novo / 400 já existe).
# =============================================================================
set -euo pipefail

BASE_URL="${BASE_URL:-https://app-ccgl-rm564113.azurewebsites.net/veti}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTION="${SCRIPT_DIR}/veti.postman_collection.json"

if ! command -v npx >/dev/null 2>&1; then
  echo "npx não encontrado. Instale Node.js para rodar o Newman." >&2
  exit 1
fi

ENV_FILE="$(mktemp)"
trap 'rm -f "$ENV_FILE"' EXIT

export BASE_URL ENV_FILE
python3 - <<'PY'
import json, os
env = {
    "name": "veti-azure",
    "values": [
        {"key": "baseUrl", "value": os.environ["BASE_URL"], "enabled": True}
    ],
}
with open(os.environ["ENV_FILE"], "w", encoding="utf-8") as fh:
    json.dump(env, fh)
PY

echo "============================================="
echo " Newman — ${BASE_URL}"
echo "============================================="

npx --yes newman run "$COLLECTION" \
  --environment "$ENV_FILE" \
  --reporters cli
