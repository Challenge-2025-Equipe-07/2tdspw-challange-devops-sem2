#!/usr/bin/env bash
# =============================================================================
# Teste da infraestrutura — Opção B (App Service + PostgreSQL PaaS)
# Time CCGL · RM564113
# =============================================================================
set -euo pipefail

RM_ID="rm564113"
RG="rg-challenge-devops"
WEBAPP_NAME="app-ccgl-${RM_ID}"
PG_SERVER_NAME="pg-ccgl-${RM_ID}"
PG_DB_NAME="db-challenge"

HEALTH_PATH="${HEALTH_PATH:-/veti/tutores}"
WEBAPP_URL="https://${WEBAPP_NAME}.azurewebsites.net"

echo "============================================="
echo " Testando infraestrutura"
echo "============================================="

echo "==> [1/4] Verificando estado do Web App: $WEBAPP_NAME"
STATE="$(az webapp show \
  --resource-group "$RG" \
  --name "$WEBAPP_NAME" \
  --query state -o tsv 2>/dev/null || echo "NOT_FOUND")"

if [[ "$STATE" != "Running" ]]; then
  echo "❌ Web App não está Running (estado: $STATE)"
  az webapp log tail --resource-group "$RG" --name "$WEBAPP_NAME" --timeout 5 2>/dev/null || true
  exit 1
fi
echo "   Estado: $STATE ✅"

echo "==> [2/4] Verificando Azure PostgreSQL: $PG_SERVER_NAME"
PG_STATE="$(az postgres flexible-server show \
  --resource-group "$RG" \
  --name "$PG_SERVER_NAME" \
  --query state -o tsv 2>/dev/null || echo "NOT_FOUND")"

echo "   Estado servidor: $PG_STATE"

if [[ "$PG_STATE" != "Ready" ]]; then
  echo "❌ PostgreSQL Flexible Server não está Ready"
  exit 1
fi
echo "   PostgreSQL Ready ✅"

echo "==> [3/4] Health check: ${WEBAPP_URL}${HEALTH_PATH}"
set +e
HEALTH_BODY="$(curl -s -w "\n%{http_code}" "${WEBAPP_URL}${HEALTH_PATH}" --max-time 30)"
CURL_STATUS=$?
set -e
HTTP_CODE="$(printf '%s' "$HEALTH_BODY" | tail -n 1)"
HEALTH_JSON="$(printf '%s' "$HEALTH_BODY" | sed '$d')"

if [[ $CURL_STATUS -ne 0 || "$HTTP_CODE" -ge 400 ]] \
  || ! printf '%s' "$HEALTH_JSON" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  echo "❌ Health check falhou (HTTP $HTTP_CODE) — a API Veti não respondeu JSON"
  echo "   Corpo (primeiros 300 chars): ${HEALTH_JSON:0:300}"
  echo "   Se aparecer a página 'Hey, Java developers!', o JAR ainda não foi publicado."
  echo ""
  echo "   Logs recentes:"
  az webapp log tail --resource-group "$RG" --name "$WEBAPP_NAME" --timeout 10 2>/dev/null || true
  exit 1
fi
echo "   HTTP $HTTP_CODE ✅"

echo "==> [4/4] GET /veti/tutores"
echo "   Resposta (primeiros 500 chars):"
echo "   ${HEALTH_JSON:0:500}"

echo ""
echo "============================================="
echo " ✅ Todos os testes passaram!"
echo "============================================="
echo " Web App URL:  $WEBAPP_URL"
echo " PostgreSQL:   ${PG_SERVER_NAME}.postgres.database.azure.com"
echo " Database:     $PG_DB_NAME"
echo " API base:     ${WEBAPP_URL}/veti"
echo ""
echo " Próximo: ./azure_test_crud.sh"
echo "============================================="
