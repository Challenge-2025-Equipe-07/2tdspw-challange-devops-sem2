#!/usr/bin/env bash
# =============================================================================
# Teste da infraestrutura — Opção 2 (App Service + PostgreSQL PaaS)
# Time CCGL · RM564113
# =============================================================================
set -euo pipefail

RM_ID="rm564113"
RG="rg-challenge-devops"
WEBAPP_NAME="app-ccgl-${RM_ID}"
PG_SERVER_NAME="pg-ccgl-${RM_ID}"
PG_DB_NAME="db-challenge"
LAW_NAME="law-ccgl-${RM_ID}"
APPINSIGHTS_NAME="appi-ccgl-${RM_ID}"

# GET /health é o alias do Actuator (API + PostgreSQL + dependência).
HEALTH_PATH="${HEALTH_PATH:-/health}"
WEBAPP_URL="https://${WEBAPP_NAME}.azurewebsites.net"

app_setting() {
  az webapp config appsettings list \
    --resource-group "$RG" \
    --name "$WEBAPP_NAME" \
    --query "[?name=='${1}'].value | [0]" -o tsv 2>/dev/null || true
}

echo "============================================="
echo " Testando infraestrutura"
echo "============================================="

echo "==> [1/5] Verificando estado do Web App: $WEBAPP_NAME"
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

echo "==> [2/5] Verificando Azure PostgreSQL: $PG_SERVER_NAME"
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

echo "==> [3/5] Application Insights: $APPINSIGHTS_NAME"
AI_STATE="$(az monitor app-insights component show \
  --app "$APPINSIGHTS_NAME" \
  --resource-group "$RG" \
  --query provisioningState -o tsv 2>/dev/null || echo "NOT_FOUND")"
echo "   Estado: $AI_STATE"
if [[ "$AI_STATE" != "Succeeded" ]]; then
  echo "❌ Application Insights não está Succeeded"
  exit 1
fi

LAW_STATE="$(az monitor log-analytics workspace show \
  --resource-group "$RG" \
  --workspace-name "$LAW_NAME" \
  --query provisioningState -o tsv 2>/dev/null || echo "NOT_FOUND")"
echo "   Log Analytics: $LAW_STATE"
if [[ "$LAW_STATE" != "Succeeded" ]]; then
  echo "❌ Log Analytics não está Succeeded"
  exit 1
fi

AI_CS="$(app_setting APPLICATIONINSIGHTS_CONNECTION_STRING)"
AI_AGENT="$(app_setting ApplicationInsightsAgent_EXTENSION_VERSION)"
if [[ -z "$AI_CS" || "$AI_CS" == "null" ]]; then
  echo "❌ APPLICATIONINSIGHTS_CONNECTION_STRING ausente no Web App"
  exit 1
fi
if [[ "$AI_AGENT" != "~3" ]]; then
  echo "❌ ApplicationInsightsAgent_EXTENSION_VERSION deveria ser ~3 (atual: ${AI_AGENT:-vazio})"
  exit 1
fi
echo "   Connection string configurada · agente ~3 ✅"

WEBAPP_ID="$(az webapp show --resource-group "$RG" --name "$WEBAPP_NAME" --query id -o tsv)"
if ! az monitor diagnostic-settings show --name diag-webapp --resource "$WEBAPP_ID" >/dev/null 2>&1; then
  echo "❌ Diagnostic setting diag-webapp ausente"
  exit 1
fi
echo "   Diagnostic setting diag-webapp ✅"

echo "==> [4/5] Probe: ${WEBAPP_URL}${HEALTH_PATH}"
set +e
HEALTH_BODY="$(curl -s -w "\n%{http_code}" "${WEBAPP_URL}${HEALTH_PATH}" --max-time 30)"
CURL_STATUS=$?
set -e
HTTP_CODE="$(printf '%s' "$HEALTH_BODY" | tail -n 1)"
HEALTH_JSON="$(printf '%s' "$HEALTH_BODY" | sed '$d')"

if [[ $CURL_STATUS -ne 0 || "$HTTP_CODE" -ge 400 ]] \
  || ! printf '%s' "$HEALTH_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("status")=="UP"' 2>/dev/null; then
  echo "❌ Health check falhou (HTTP $HTTP_CODE) — ${HEALTH_PATH} não retornou status UP"
  echo "   Corpo (primeiros 300 chars): ${HEALTH_JSON:0:300}"
  echo "   Se aparecer a página 'Hey, Java developers!', o JAR ainda não foi publicado."
  echo ""
  echo "   Logs recentes:"
  az webapp log tail --resource-group "$RG" --name "$WEBAPP_NAME" --timeout 10 2>/dev/null || true
  exit 1
fi
echo "   HTTP $HTTP_CODE ✅"

echo "==> [5/5] Resposta de ${HEALTH_PATH}"
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
echo " App Insights: $APPINSIGHTS_NAME"
echo " Probe:        ${HEALTH_PATH}"
echo ""
echo " Próximo: ./azure_test_crud.sh"
echo "          ./tests/run_newman.sh"
echo "============================================="
