#!/usr/bin/env bash
# =============================================================================
# CRUD na nuvem — Tutor + Pet (tabelas relacionadas) · Opção B
# Time CCGL · RM564113
# =============================================================================
set -euo pipefail

RM_ID="rm564113"
WEBAPP_NAME="app-ccgl-${RM_ID}"
SQL_SERVER_NAME="sql-ccgl-${RM_ID}"
SQL_DB_NAME="db-challenge"
SQL_ADMIN_USER="sqladmin"
SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-}"

BASE="${BASE_URL:-https://${WEBAPP_NAME}.azurewebsites.net/veti}"
AUTH_EMAIL="${AUTH_EMAIL:-vet@ccgl.com}"
AUTH_PASSWORD="${AUTH_PASSWORD:-SenhaForte!123}"
UNIQ="$(date +%s)"
CPF1="1$(printf '%010d' $((UNIQ % 10000000000)))"
CPF2="2$(printf '%010d' $((UNIQ % 10000000000)))"

json_get() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)'"$1"')'
}

echo "============================================="
echo " CRUD Veti — ${BASE}"
echo "============================================="

echo "==> [1/8] Health"
curl -sf "${BASE}/health"
echo

echo "==> [2/8] Register veterinário ADMIN"
set +e
REG_CODE="$(curl -s -o /tmp/veti-register.body -w "%{http_code}" \
  -X POST "${BASE}/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${AUTH_EMAIL}\",\"password\":\"${AUTH_PASSWORD}\",\"role\":\"ADMIN\"}")"
set -e
echo "   HTTP ${REG_CODE} (200 novo / 400 já existe)"

echo "==> [3/8] Login"
LOGIN_BODY="$(curl -sf -X POST "${BASE}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${AUTH_EMAIL}\",\"password\":\"${AUTH_PASSWORD}\"}")"
TOKEN="$(printf '%s' "$LOGIN_BODY" | python3 -c 'import json,sys; v=json.load(sys.stdin); print(v["token"] if isinstance(v, dict) else v)')"
if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "❌ Falha no login. Corpo: ${LOGIN_BODY}" >&2
  exit 1
fi
echo "   Token obtido ✅"
AUTH=( -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" )

echo "==> [4/8] Criar 2 tutores"
TUTOR1="$(curl -sf -X POST "${BASE}/tutores" "${AUTH[@]}" \
  -d "{\"name\":\"Ana Silva\",\"email\":\"ana${UNIQ}@ccgl.com\",\"phone\":\"11999999999\",\"cpf\":\"${CPF1}\"}")"
TUTOR2="$(curl -sf -X POST "${BASE}/tutores" "${AUTH[@]}" \
  -d "{\"name\":\"Bruno Souza\",\"email\":\"bruno${UNIQ}@ccgl.com\",\"phone\":\"11888888888\",\"cpf\":\"${CPF2}\"}")"
ID1="$(printf '%s' "$TUTOR1" | json_get '["id"]')"
ID2="$(printf '%s' "$TUTOR2" | json_get '["id"]')"
echo "   Tutor 1 id=${ID1}  Tutor 2 id=${ID2}"

echo "==> [5/8] Criar 2 pets (FK Tutor)"
PET1="$(curl -sf -X POST "${BASE}/pets" "${AUTH[@]}" \
  -d "{\"name\":\"Rex\",\"raca\":\"LABRADOR_RETRIEVER\",\"peso\":28.5,\"idade\":4,\"castrado\":true,\"idTutor\":${ID1}}")"
PET2="$(curl -sf -X POST "${BASE}/pets" "${AUTH[@]}" \
  -d "{\"name\":\"Mimi\",\"raca\":\"PERSIAN\",\"peso\":4.2,\"idade\":2,\"castrado\":false,\"idTutor\":${ID2}}")"
PET_ID1="$(printf '%s' "$PET1" | json_get '["id"]')"
PET_ID2="$(printf '%s' "$PET2" | json_get '["id"]')"
echo "   Pet 1 id=${PET_ID1}  Pet 2 id=${PET_ID2}"

echo "==> [6/8] Consultar (GET)"
curl -sf "${BASE}/tutores?size=10"
echo
curl -sf "${BASE}/pets?size=10"
echo

echo "==> [7/8] Alterar tutor 1 + excluir pet 2"
curl -sf -X PUT "${BASE}/tutores/${ID1}" "${AUTH[@]}" \
  -d "{\"name\":\"Ana Silva Costa\",\"email\":\"ana${UNIQ}@ccgl.com\",\"phone\":\"11777777777\",\"cpf\":\"${CPF1}\"}"
echo
DEL_CODE="$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${BASE}/pets/${PET_ID2}" \
  -H "Authorization: Bearer ${TOKEN}")"
echo "   DELETE /pets/${PET_ID2} HTTP ${DEL_CODE}"

echo "==> [8/8] SELECT no Azure SQL (persistência)"
if [[ -z "$SQL_ADMIN_PASSWORD" ]]; then
  echo "   SQL_ADMIN_PASSWORD não definido — pule o SELECT ou exporte a senha."
  echo "   sqlcmd -S ${SQL_SERVER_NAME}.database.windows.net -d ${SQL_DB_NAME} \\"
  echo "     -U ${SQL_ADMIN_USER} -P '***' -N -C \\"
  echo "     -Q \"SELECT TOP 10 * FROM TB_TUTOR; SELECT TOP 10 * FROM TB_PET;\""
elif command -v sqlcmd >/dev/null 2>&1; then
  sqlcmd -S "${SQL_SERVER_NAME}.database.windows.net" -d "$SQL_DB_NAME" \
    -U "$SQL_ADMIN_USER" -P "$SQL_ADMIN_PASSWORD" -N -C \
    -Q "SELECT TOP 10 ID_TUTOR, NM_TUTOR, DS_EMAIL FROM TB_TUTOR; SELECT TOP 10 ID_PET, NM_PET, TB_TUTOR_ID_TUTOR FROM TB_PET;"
else
  echo "   sqlcmd não encontrado. Instale o mssql-tools ou rode no Query Editor do Portal:"
  echo "   SELECT TOP 10 * FROM TB_TUTOR;"
  echo "   SELECT TOP 10 * FROM TB_PET;"
fi

echo ""
echo "============================================="
echo " ✅ CRUD concluído (Tutor + Pet, ≥ 2 linhas)"
echo "============================================="
echo " Swagger: ${BASE}/swagger-ui.html"
echo "============================================="
