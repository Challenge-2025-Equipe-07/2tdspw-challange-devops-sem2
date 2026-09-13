#!/usr/bin/env bash
# =============================================================================
# CRUD na nuvem — executa Tutor, Pet, Veterinário, Consulta via HTTP
# e só consulta o Postgres para provar que os curls gravaram.
# Time CCGL · RM564113
# =============================================================================
set -euo pipefail

BASE="${BASE_URL:-https://app-ccgl-rm564113.azurewebsites.net/veti}"
PG_SERVER_NAME="pg-ccgl-rm564113"
PG_DB_NAME="db-challenge"
PG_ADMIN_USER="ccgl"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-${SQL_ADMIN_PASSWORD:-}}"
KEYVAULT_NAME="kv-ccgl-rm564113"
AUTH_EMAIL="${AUTH_EMAIL:-vet@ccgl.com}"
AUTH_PASSWORD="${AUTH_PASSWORD:-SenhaForte!123}"
AUTH_EMAIL2="${AUTH_EMAIL2:-vet2@ccgl.com}"
UNIQ="$(date +%s)"
CPF1="1$(printf '%010d' $((UNIQ % 10000000000)))"
CPF2="2$(printf '%010d' $((UNIQ % 10000000000)))"

iso_from_epoch() {
  python3 -c "from datetime import datetime, timezone, timedelta; print((datetime.fromtimestamp(int('$UNIQ'), timezone.utc)+timedelta(days=int('$1'), seconds=int('$2'))).strftime('%Y-%m-%dT%H:%M:%S'))"
}
# Horários únicos por execução — TB_CONSULTA é UNIQUE (data, veterinário)
DATA1="$(iso_from_epoch 2 0)"
DATA2="$(iso_from_epoch 3 0)"
DATA1_UPD="$(iso_from_epoch 5 17)"

json_get() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)'"$1"')'
}

page_id_by_email() {
  python3 -c '
import json, sys
email = sys.argv[1]
d = json.load(sys.stdin)
print(next(x["id"] for x in d["content"] if x.get("email") == email))
' "$1"
}

extract_token() {
  python3 -c '
import json, sys
s = sys.stdin.read().strip()
if not s:
    sys.exit(1)
if s.startswith("eyJ"):
    print(s)
    raise SystemExit(0)
try:
    v = json.loads(s)
except json.JSONDecodeError:
    print(s.strip("\""))
    raise SystemExit(0)
print(v["token"] if isinstance(v, dict) else v)
'
}

# Azure CLI 2.86+ não inclui `az postgres flexible-server execute` (extensão rdbms-connect).
pg_query() {
  local sql="$1"
  export PGHOST="${PG_SERVER_NAME}.postgres.database.azure.com"
  export PGPORT="5432"
  export PGUSER="$PG_ADMIN_USER"
  export PGPASSWORD="$PG_ADMIN_PASSWORD"
  export PGDATABASE="$PG_DB_NAME"
  if command -v psql >/dev/null 2>&1; then
    psql "sslmode=require" -v ON_ERROR_STOP=1 -c "$sql"
    return $?
  fi
  PG_SQL_PAYLOAD="$sql" python3 - <<'PY'
import os, sys, subprocess

sql = os.environ["PG_SQL_PAYLOAD"]
host = os.environ["PGHOST"]
port = os.environ.get("PGPORT", "5432")
user = os.environ["PGUSER"]
password = os.environ["PGPASSWORD"]
dbname = os.environ["PGDATABASE"]

def try_import():
    for name in ("psycopg", "psycopg2"):
        try:
            return __import__(name)
        except ImportError:
            continue
    return None

from urllib.parse import quote

mod = try_import()
if mod is None:
    subprocess.check_call(
        [sys.executable, "-m", "pip", "install", "psycopg[binary]", "-q"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    mod = try_import()
if mod is None:
    sys.stderr.write("Não foi possível importar psycopg. Instale: pip install 'psycopg[binary]'\n")
    sys.exit(1)

uri = (
    f"postgresql://{quote(user, safe='')}:{quote(password, safe='')}"
    f"@{host}:{port}/{dbname}?sslmode=require"
)
conn = mod.connect(uri)
try:
    conn.autocommit = True
    cur = conn.cursor()
    parts = [p.strip() for p in sql.split(";") if p.strip()]
    for part in parts:
        cur.execute(part)
        if cur.description:
            cols = [d[0] for d in cur.description]
            print(" | ".join(cols))
            for row in cur.fetchall():
                print(" | ".join("" if v is None else str(v) for v in row))
    cur.close()
finally:
    conn.close()
PY
}

echo "============================================="
echo " CRUD Veti — ${BASE}"
echo "============================================="

echo "==> [1/11] GET /tutores"
HEALTH_BODY="$(curl -sS "${BASE}/tutores" --max-time 30)"
if ! printf '%s' "$HEALTH_BODY" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
  echo "❌ API não respondeu JSON em ${BASE}/tutores" >&2
  echo "${HEALTH_BODY:0:400}" >&2
  exit 1
fi
echo "   API no ar ✅"

echo "==> [2/11] Register ADMIN ${AUTH_EMAIL} + USER ${AUTH_EMAIL2}"
set +e
REG1="$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${AUTH_EMAIL}\",\"password\":\"${AUTH_PASSWORD}\",\"role\":\"ADMIN\"}")"
REG2="$(curl -sS -o /dev/null -w "%{http_code}" -X POST "${BASE}/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${AUTH_EMAIL2}\",\"password\":\"${AUTH_PASSWORD}\",\"role\":\"USER\"}")"
set -e
echo "   ADMIN HTTP ${REG1} · USER HTTP ${REG2} (200 novo / 400 já existe)"

echo "==> [3/11] Login ADMIN"
LOGIN_BODY="$(curl -sS -X POST "${BASE}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${AUTH_EMAIL}\",\"password\":\"${AUTH_PASSWORD}\"}")"
TOKEN="$(printf '%s' "$LOGIN_BODY" | extract_token)"
if [[ -z "${TOKEN}" || "${TOKEN}" == "null" || ! "${TOKEN}" =~ ^eyJ ]]; then
  echo "❌ Login falhou: ${LOGIN_BODY:0:400}" >&2
  exit 1
fi
echo "   TOKEN ok ✅"
AUTH=( -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" )

echo "==> [4/11] Criar 2 tutores (TB_TUTOR)"
TUTOR1="$(curl -sS -f -X POST "${BASE}/tutores" "${AUTH[@]}" \
  -d "{\"name\":\"Ana Silva\",\"email\":\"ana${UNIQ}@ccgl.com\",\"phone\":\"11999999999\",\"cpf\":\"${CPF1}\"}")"
TUTOR2="$(curl -sS -f -X POST "${BASE}/tutores" "${AUTH[@]}" \
  -d "{\"name\":\"Bruno Souza\",\"email\":\"bruno${UNIQ}@ccgl.com\",\"phone\":\"11888888888\",\"cpf\":\"${CPF2}\"}")"
ID_TUTOR1="$(printf '%s' "$TUTOR1" | json_get '["id"]')"
ID_TUTOR2="$(printf '%s' "$TUTOR2" | json_get '["id"]')"
echo "   tutor ${ID_TUTOR1} Ana · tutor ${ID_TUTOR2} Bruno"

echo "==> [5/11] Criar 2 pets (TB_PET)"
PET1="$(curl -sS -f -X POST "${BASE}/pets" "${AUTH[@]}" \
  -d "{\"name\":\"Rex\",\"raca\":\"LABRADOR_RETRIEVER\",\"peso\":28.5,\"idade\":4,\"castrado\":true,\"idTutor\":${ID_TUTOR1}}")"
PET2="$(curl -sS -f -X POST "${BASE}/pets" "${AUTH[@]}" \
  -d "{\"name\":\"Mimi\",\"raca\":\"PERSIAN\",\"peso\":4.2,\"idade\":2,\"castrado\":false,\"idTutor\":${ID_TUTOR2}}")"
ID_PET1="$(printf '%s' "$PET1" | json_get '["id"]')"
ID_PET2="$(printf '%s' "$PET2" | json_get '["id"]')"
echo "   pet ${ID_PET1} Rex · pet ${ID_PET2} Mimi"

echo "==> [6/11] IDs dos veterinários (TB_VETERINARIO)"
VETS="$(curl -sS -f "${BASE}/veterinarios?size=50")"
ID_VET1="$(printf '%s' "$VETS" | page_id_by_email "${AUTH_EMAIL}")"
ID_VET2="$(printf '%s' "$VETS" | page_id_by_email "${AUTH_EMAIL2}")"
echo "   vet ADMIN ${ID_VET1} · vet USER ${ID_VET2}"

echo "==> [7/11] Criar 2 consultas (TB_CONSULTA)"
CON1="$(curl -sS -f -X POST "${BASE}/consultas" "${AUTH[@]}" \
  -d "{\"dataConsulta\":\"${DATA1}\",\"idVeterinario\":${ID_VET1},\"idPet\":${ID_PET1},\"descricao\":\"Check-up Rex\"}")"
CON2="$(curl -sS -f -X POST "${BASE}/consultas" "${AUTH[@]}" \
  -d "{\"dataConsulta\":\"${DATA2}\",\"idVeterinario\":${ID_VET2},\"idPet\":${ID_PET2},\"descricao\":\"Vacina Mimi\"}")"
ID_CON1="$(printf '%s' "$CON1" | json_get '["id"]')"
ID_CON2="$(printf '%s' "$CON2" | json_get '["id"]')"
echo "   consulta ${ID_CON1} ${DATA1} · consulta ${ID_CON2} ${DATA2}"

echo "==> [8/11] Consultar GET"
curl -sS -f "${BASE}/tutores?size=10"; echo
curl -sS -f "${BASE}/pets?size=10"; echo
curl -sS -f "${BASE}/consultas?size=10"; echo
curl -sS -f "${BASE}/veterinarios?size=10"; echo

echo "==> [9/11] Alterar tutor ${ID_TUTOR1} + pet ${ID_PET1} + consulta ${ID_CON1}"
curl -sS -f -X PUT "${BASE}/tutores/${ID_TUTOR1}" "${AUTH[@]}" \
  -d "{\"name\":\"Ana Silva Costa\",\"email\":\"ana${UNIQ}@ccgl.com\",\"phone\":\"11777777777\",\"cpf\":\"${CPF1}\"}"
echo
curl -sS -f -X PUT "${BASE}/pets/${ID_PET1}" "${AUTH[@]}" \
  -d "{\"name\":\"Rex Costa\",\"raca\":\"LABRADOR_RETRIEVER\",\"peso\":29.0,\"idade\":5,\"castrado\":true,\"idTutor\":${ID_TUTOR1}}"
echo
set +e
CON_UPD="$(curl -sS -w "\n%{http_code}" -X PUT "${BASE}/consultas/${ID_CON1}" "${AUTH[@]}" \
  -d "{\"dataConsulta\":\"${DATA1_UPD}\",\"idVeterinario\":${ID_VET1},\"idPet\":${ID_PET1},\"descricao\":\"Retorno Rex\"}")"
CON_UPD_CODE="$(printf '%s' "$CON_UPD" | tail -n 1)"
CON_UPD_BODY="$(printf '%s' "$CON_UPD" | sed '$d')"
set -e
echo "$CON_UPD_BODY"
if [[ "$CON_UPD_CODE" -ge 400 ]]; then
  echo "❌ PUT /consultas/${ID_CON1} HTTP ${CON_UPD_CODE} (único: data+veterinário). Horário: ${DATA1_UPD}" >&2
  exit 1
fi

echo "==> [10/11] Excluir consulta ${ID_CON2}"
DEL_CODE="$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE "${BASE}/consultas/${ID_CON2}" \
  -H "Authorization: Bearer ${TOKEN}")"
echo "   DELETE /consultas/${ID_CON2} HTTP ${DEL_CODE}"

if [[ -z "$PG_ADMIN_PASSWORD" ]]; then
  PG_ADMIN_PASSWORD="$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name pg-password --query value -o tsv 2>/dev/null || true)"
fi

echo "==> [11/11] SELECT no Postgres (só leitura — conferir o que os curls gravaram)"
if [[ -z "$PG_ADMIN_PASSWORD" ]]; then
  echo "   Sem senha Postgres (PG_ADMIN_PASSWORD / Key Vault) — no Beekeeper: FROM tb_tutor / tb_pet (minúsculas)."
else
  pg_query "$(cat <<SQL
SELECT 'PUT tutor' AS checagem, id_tutor, nm_tutor, ds_telefone, ds_email
FROM tb_tutor WHERE id_tutor IN (${ID_TUTOR1}, ${ID_TUTOR2}) ORDER BY id_tutor;
SELECT 'POST pet' AS checagem, id_pet, nm_pet, ds_raca, tb_tutor_id_tutor
FROM tb_pet WHERE id_pet IN (${ID_PET1}, ${ID_PET2}) ORDER BY id_pet;
SELECT 'POST register' AS checagem, id_veterinario, ds_email, ds_role
FROM tb_veterinario WHERE id_veterinario IN (${ID_VET1}, ${ID_VET2}) ORDER BY id_veterinario;
SELECT 'consulta ativa (PUT)' AS checagem, id_consulta, dt_consulta, tb_pet_id_pet, tb_veterinario_id_veterinario
FROM tb_consulta WHERE id_consulta = ${ID_CON1};
SELECT 'DELETE consulta ${ID_CON2} (esperado 0)' AS checagem, COUNT(*) AS ainda_existe
FROM tb_consulta WHERE id_consulta = ${ID_CON2};
SELECT p.nm_pet, t.nm_tutor, p.tb_tutor_id_tutor
FROM tb_pet p JOIN tb_tutor t ON t.id_tutor = p.tb_tutor_id_tutor
WHERE p.id_pet IN (${ID_PET1}, ${ID_PET2}) ORDER BY p.id_pet;
SQL
)"
fi

echo ""
echo "============================================="
echo " ✅ CRUD HTTP executado"
echo "============================================="
echo " Esperado no SELECT:"
echo "   tutor ${ID_TUTOR1} = Ana Silva Costa / 11777777777"
echo "   tutor ${ID_TUTOR2} = Bruno Souza"
echo "   pet ${ID_PET1} = Rex Costa · pet ${ID_PET2} = Mimi"
echo "   consulta ${ID_CON1} existe · consulta ${ID_CON2} COUNT=0 (DELETE)"
echo " Swagger:    ${BASE}/swagger-ui.html"
echo "============================================="
