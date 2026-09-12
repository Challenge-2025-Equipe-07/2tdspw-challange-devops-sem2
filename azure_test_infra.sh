#!/usr/bin/env bash
# =============================================================================
# Teste da infraestrutura — Opção B (App Service + Azure SQL PaaS)
# Time CCGL · RM564113
# =============================================================================
set -euo pipefail

RM_ID="rm564113"
RG="rg-challenge-devops"
WEBAPP_NAME="app-ccgl-${RM_ID}"
SQL_SERVER_NAME="sql-ccgl-${RM_ID}"
SQL_DB_NAME="db-challenge"

APP_PORT="${APP_PORT:-8080}"
HEALTH_PATH="${HEALTH_PATH:-/veti/health}"

WEBAPP_URL="https://${WEBAPP_NAME}.azurewebsites.net"

echo "============================================="
echo " Testando infraestrutura — Opção B"
echo "============================================="

# ---------------------------------------------------------------------------
# 1. Verificar se o Web App existe e está running
# ---------------------------------------------------------------------------
echo "==> [1/4] Verificando estado do Web App: $WEBAPP_NAME"
STATE="$(az webapp show \
  --resource-group "$RG" \
  --name "$WEBAPP_NAME" \
  --query state -o tsv 2>/dev/null || echo "NOT_FOUND")"

if [[ "$STATE" != "Running" ]]; then
  echo "❌ Web App não está Running (estado: $STATE)"
  echo "   Logs recentes:"
  az webapp log tail --resource-group "$RG" --name "$WEBAPP_NAME" --timeout 5 2>/dev/null || true
  exit 1
fi
echo "   Estado: $STATE ✅"

# ---------------------------------------------------------------------------
# 2. Verificar se o Azure SQL está acessível
# ---------------------------------------------------------------------------
echo "==> [2/4] Verificando Azure SQL Server: $SQL_SERVER_NAME"
SQL_STATE="$(az sql server show \
  --resource-group "$RG" \
  --name "$SQL_SERVER_NAME" \
  --query state -o tsv 2>/dev/null || echo "NOT_FOUND")"

echo "   Estado SQL Server: $SQL_STATE"

DB_STATUS="$(az sql db show \
  --resource-group "$RG" \
  --server "$SQL_SERVER_NAME" \
  --name "$SQL_DB_NAME" \
  --query status -o tsv 2>/dev/null || echo "NOT_FOUND")"

echo "   Estado Database:   $DB_STATUS"

if [[ "$DB_STATUS" != "Online" ]]; then
  echo "❌ Banco de dados não está Online"
  exit 1
fi
echo "   SQL Database Online ✅"

# ---------------------------------------------------------------------------
# 3. Health check HTTP
# ---------------------------------------------------------------------------
echo "==> [3/4] Health check: ${WEBAPP_URL}${HEALTH_PATH}"

set +e
HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" "${WEBAPP_URL}${HEALTH_PATH}" --max-time 30)"
CURL_STATUS=$?
set -e

if [[ $CURL_STATUS -ne 0 || "$HTTP_CODE" -ge 400 ]]; then
  echo "❌ Health check falhou (HTTP $HTTP_CODE)"
  echo ""
  echo "   Tentando a raiz (${WEBAPP_URL}/)..."
  ROOT_CODE="$(curl -s -o /dev/null -w "%{http_code}" "${WEBAPP_URL}/" --max-time 30 || true)"
  echo "   HTTP raiz: $ROOT_CODE"
  echo ""
  echo "   Logs recentes:"
  az webapp log tail --resource-group "$RG" --name "$WEBAPP_NAME" --timeout 10 2>/dev/null || true
  exit 1
fi
echo "   HTTP $HTTP_CODE ✅"

# ---------------------------------------------------------------------------
# 4. Teste rápido de endpoint (se existir /api)
# ---------------------------------------------------------------------------
echo "==> [4/4] Testando GET /veti/tutores"
set +e
BODY="$(curl -s "${WEBAPP_URL}/veti/tutores" --max-time 15)"
set -e
echo "   Resposta (primeiros 500 chars):"
echo "   ${BODY:0:500}"

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " ✅ Todos os testes passaram!"
echo "============================================="
echo " Web App URL:  $WEBAPP_URL"
echo " SQL Server:   ${SQL_SERVER_NAME}.database.windows.net"
echo " SQL Database: $SQL_DB_NAME"
echo ""
echo " API base:      ${WEBAPP_URL}/veti"
echo ""
echo " Próximo:"
echo "   1. ./azure_test_crud.sh"
echo "   2. sqlcmd -S ${SQL_SERVER_NAME}.database.windows.net -d $SQL_DB_NAME \\"
echo "        -U sqladmin -P \"\$SQL_ADMIN_PASSWORD\" -N -C \\"
echo "        -Q \"SELECT TOP 10 * FROM TB_TUTOR; SELECT TOP 10 * FROM TB_PET;\""
echo "============================================="
