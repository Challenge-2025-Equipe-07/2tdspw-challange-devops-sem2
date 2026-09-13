#!/usr/bin/env bash
# =============================================================================
# Opção B — App Service (Web App) + Azure Database for PostgreSQL (PaaS)
# Time CCGL · RM564113 · Região chilecentral
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Parâmetros centrais
# ---------------------------------------------------------------------------
RM_ID="rm564113"
LOCATION="chilecentral"
RG="rg-challenge-devops"

PG_SERVER_NAME="pg-ccgl-${RM_ID}"
PG_DB_NAME="db-challenge"
PG_ADMIN_USER="ccgl"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-${SQL_ADMIN_PASSWORD:-}}"

KEYVAULT_NAME="kv-ccgl-${RM_ID}"

APP_SERVICE_PLAN="plan-ccgl-${RM_ID}"
WEBAPP_NAME="app-ccgl-${RM_ID}"

APP_PORT="${APP_PORT:-8080}"
JAVA_REPO_URL="${JAVA_REPO_URL:-https://github.com/Challenge-2025-Equipe-07/challenge-2026-java-spint1.git}"
JAVA_DIR_NAME="${JAVA_DIR_NAME:-challenge-2026-java-spint1}"

JWT_SECRET="${JWT_SECRET:-veti-default-secret-change-in-production}"

# ---------------------------------------------------------------------------
# Solicita senha do PostgreSQL se não fornecida
# ---------------------------------------------------------------------------
if [[ -z "$PG_ADMIN_PASSWORD" ]]; then
  read -r -s -p "Defina a senha do Azure PostgreSQL (admin=$PG_ADMIN_USER): " PG_ADMIN_PASSWORD
  echo
fi

# ---------------------------------------------------------------------------
# Validações
# ---------------------------------------------------------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Comando necessário não encontrado: $1" >&2; exit 1; }
}
require_cmd az
require_cmd curl
require_cmd git

wait_pg_ready() {
  local reason="${1:-}"
  [[ -n "$reason" ]] && echo "==> [4/8] Aguardando PostgreSQL Ready ($reason)"
  local state=""
  local i
  for i in $(seq 1 60); do
    state="$(az postgres flexible-server show \
      --resource-group "$RG" \
      --name "$PG_SERVER_NAME" \
      --query state -o tsv 2>/dev/null || echo "NOT_FOUND")"
    if [[ "$state" == "Ready" ]]; then
      echo "    PostgreSQL Ready"
      return 0
    fi
    echo "    Estado: $state — aguardando..."
    sleep 10
  done
  echo "❌ PostgreSQL não ficou Ready (estado: ${state:-unknown})" >&2
  exit 1
}

# Flexible Server rejeita operações paralelas (ex.: firewall enquanto o create ainda termina).
az_pg_retry() {
  local attempt=1
  local max=12
  local out rc
  while true; do
    set +e
    out="$("$@" 2>&1)"
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
      return 0
    fi
    if printf '%s' "$out" | grep -q 'ServerIsBusy' && [[ $attempt -lt $max ]]; then
      echo "    Servidor ocupado — nova tentativa ${attempt}/${max} em 15s..." >&2
      sleep 15
      attempt=$((attempt + 1))
      continue
    fi
    printf '%s\n' "$out" >&2
    return "$rc"
  done
}

echo "============================================="
echo " Opção B: App Service + PostgreSQL Flexible Server (PaaS)"
echo " Time CCGL · RM564113 · chilecentral"
echo "============================================="

# ---------------------------------------------------------------------------
# 1. Login
# ---------------------------------------------------------------------------
echo "==> [1/8] Login no Azure"
if ! az account show >/dev/null 2>&1; then
  az login
fi

# ---------------------------------------------------------------------------
# 2. Registrar providers
# ---------------------------------------------------------------------------
echo "==> [2/8] Registrando provedores de recursos"
az provider register --namespace Microsoft.Web                >/dev/null
az provider register --namespace Microsoft.DBforPostgreSQL    >/dev/null
az provider register --namespace Microsoft.KeyVault           >/dev/null

# ---------------------------------------------------------------------------
# 3. Resource Group
# ---------------------------------------------------------------------------
echo "==> [3/8] Criando Resource Group: $RG ($LOCATION)"
az group create --name "$RG" --location "$LOCATION" >/dev/null

# ---------------------------------------------------------------------------
# 4. Azure Database for PostgreSQL Flexible Server (PaaS)
# ---------------------------------------------------------------------------
echo "==> [4/8] Criando PostgreSQL Flexible Server: $PG_SERVER_NAME (Burstable B1ms)"
if az postgres flexible-server show --resource-group "$RG" --name "$PG_SERVER_NAME" >/dev/null 2>&1; then
  echo "    Servidor já existe — reutilizando"
else
  set +e
  CREATE_OUT="$(az postgres flexible-server create \
    --resource-group "$RG" \
    --name "$PG_SERVER_NAME" \
    --location "$LOCATION" \
    --admin-user "$PG_ADMIN_USER" \
    --admin-password "$PG_ADMIN_PASSWORD" \
    --sku-name Standard_B1ms \
    --tier Burstable \
    --storage-size 32 \
    --version 16 \
    --public-access 0.0.0.0-255.255.255.255 \
    --yes 2>&1)"
  CREATE_RC=$?
  set -e
  if [[ $CREATE_RC -ne 0 ]]; then
    printf '%s\n' "$CREATE_OUT"
    if ! az postgres flexible-server show --resource-group "$RG" --name "$PG_SERVER_NAME" >/dev/null 2>&1; then
      exit "$CREATE_RC"
    fi
    echo "    Create retornou erro, mas o servidor existe — continuando"
  fi
fi

wait_pg_ready "após create"

echo "==> [4/8] Garantindo database: $PG_DB_NAME"
if az postgres flexible-server db show \
     --resource-group "$RG" \
     --server-name "$PG_SERVER_NAME" \
     --database-name "$PG_DB_NAME" >/dev/null 2>&1; then
  echo "    Database já existe"
else
  az_pg_retry az postgres flexible-server db create \
    --resource-group "$RG" \
    --server-name "$PG_SERVER_NAME" \
    --database-name "$PG_DB_NAME" >/dev/null
fi

echo "==> [4/8] Liberando acesso temporário (todos os IPs) para setup"
az_pg_retry az postgres flexible-server firewall-rule create \
  --resource-group "$RG" \
  --name "$PG_SERVER_NAME" \
  --rule-name AllowAllSetup \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 255.255.255.255 >/dev/null 2>&1 || true

echo "==> [4/8] Liberando serviços Azure (App Service → PostgreSQL)"
az_pg_retry az postgres flexible-server firewall-rule create \
  --resource-group "$RG" \
  --name "$PG_SERVER_NAME" \
  --rule-name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0 >/dev/null 2>&1 || true

PG_JDBC_URL="jdbc:postgresql://${PG_SERVER_NAME}.postgres.database.azure.com:5432/${PG_DB_NAME}?sslmode=require"

# ---------------------------------------------------------------------------
# 5. Key Vault — guardar segredos
# ---------------------------------------------------------------------------
echo "==> [5/8] Criando/atualizando Key Vault: $KEYVAULT_NAME"
if az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RG" >/dev/null 2>&1; then
  echo "    Key Vault já existe — atualizando"
  az keyvault update \
    --name "$KEYVAULT_NAME" \
    --resource-group "$RG" \
    --enable-rbac-authorization false >/dev/null
elif [[ -n "$(az keyvault list-deleted --query "[?name=='${KEYVAULT_NAME}'] | [0].name" -o tsv 2>/dev/null || true)" ]]; then
  echo "    Key Vault em soft-delete — recuperando"
  az keyvault recover --name "$KEYVAULT_NAME" --location "$LOCATION" >/dev/null
  az keyvault update \
    --name "$KEYVAULT_NAME" \
    --resource-group "$RG" \
    --enable-rbac-authorization false >/dev/null
else
  az keyvault create \
    --name "$KEYVAULT_NAME" \
    --resource-group "$RG" \
    --location "$LOCATION" \
    --sku standard \
    --enable-rbac-authorization false >/dev/null
fi

CURRENT_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
if [[ -z "$CURRENT_OID" ]]; then
  echo "❌ Não foi possível obter o Object ID do usuário logado (az ad signed-in-user show)." >&2
  exit 1
fi

echo "==> [5/8] Concedendo permissão de secrets ao usuário atual"
az keyvault set-policy \
  --name "$KEYVAULT_NAME" \
  --object-id "$CURRENT_OID" \
  --secret-permissions get list set delete >/dev/null

echo "==> [5/8] Salvando segredos no Key Vault"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "pg-jdbc-url"  --value "$PG_JDBC_URL"        >/dev/null
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "pg-username"  --value "$PG_ADMIN_USER"      >/dev/null
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "pg-password"  --value "$PG_ADMIN_PASSWORD"  >/dev/null
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "jwt-secret"   --value "$JWT_SECRET"         >/dev/null

# ---------------------------------------------------------------------------
# 6. App Service Plan
# ---------------------------------------------------------------------------
echo "==> [6/8] Criando App Service Plan: $APP_SERVICE_PLAN (B1 — Linux)"
az appservice plan create \
  --name "$APP_SERVICE_PLAN" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku B1 \
  --is-linux >/dev/null

# ---------------------------------------------------------------------------
# 7. Web App (Java 21)
# ---------------------------------------------------------------------------
echo "==> [7/8] Criando Web App: $WEBAPP_NAME"
az webapp create \
  --name "$WEBAPP_NAME" \
  --resource-group "$RG" \
  --plan "$APP_SERVICE_PLAN" \
  --runtime "JAVA:21-java21" >/dev/null

GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-disabled-placeholder}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-disabled-placeholder}"

echo "==> [7/8] Configurando App Settings (DB_URL/DB_USER/DB_PASSWORD da API Veti)"
az webapp config appsettings set \
  --resource-group "$RG" \
  --name "$WEBAPP_NAME" \
  --settings \
    DB_URL="$PG_JDBC_URL" \
    DB_USER="$PG_ADMIN_USER" \
    DB_PASSWORD="$PG_ADMIN_PASSWORD" \
    SPRING_DATASOURCE_URL="$PG_JDBC_URL" \
    SPRING_DATASOURCE_USERNAME="$PG_ADMIN_USER" \
    SPRING_DATASOURCE_PASSWORD="$PG_ADMIN_PASSWORD" \
    SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.postgresql.Driver" \
    SPRING_JPA_DATABASE_PLATFORM="org.hibernate.dialect.PostgreSQLDialect" \
    SPRING_JPA_HIBERNATE_DDL_AUTO="update" \
    JWT_SECRET="$JWT_SECRET" \
    GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
    GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
    WEBSITES_PORT="$APP_PORT" >/dev/null

# ---------------------------------------------------------------------------
# 8. Clone da API Java, build e deploy do JAR
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAVA_DIR="${SCRIPT_DIR}/${JAVA_DIR_NAME}"

pick_java21() {
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]] \
    && "${JAVA_HOME}/bin/java" -version 2>&1 | grep -Eq '"21[\.\"]'; then
    export PATH="${JAVA_HOME}/bin:${PATH}"
    return 0
  fi
  if [[ -x /usr/libexec/java_home ]]; then
    local home
    home="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
    if [[ -n "$home" ]]; then
      export JAVA_HOME="$home"
      export PATH="${JAVA_HOME}/bin:${PATH}"
      return 0
    fi
  fi
  if command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -Eq '"21[\.\"]'; then
    return 0
  fi
  echo "❌ Java 21 é obrigatório para o build (./mvnw)." >&2
  echo "   macOS: /usr/libexec/java_home -v 21" >&2
  echo "   Ou: export JAVA_HOME=/caminho/jdk-21" >&2
  exit 1
}

echo "==> [8/8] Clone + build + deploy da API Veti"
if [[ ! -d "${JAVA_DIR}/.git" ]]; then
  echo "    git clone ${JAVA_REPO_URL}"
  git clone --depth 1 "$JAVA_REPO_URL" "$JAVA_DIR"
else
  echo "    Repositório já existe em ${JAVA_DIR_NAME}/ — atualizando"
  git -C "$JAVA_DIR" pull --ff-only || true
fi

chmod +x "${JAVA_DIR}/mvnw"
pick_java21
echo "    JAVA_HOME=${JAVA_HOME:-}"
echo "    ./mvnw clean package -DskipTests"
( cd "$JAVA_DIR" && ./mvnw clean package -DskipTests )

JAR_FILE="${JAVA_DIR}/target/veti-0.0.1-SNAPSHOT.jar"
if [[ ! -f "$JAR_FILE" ]]; then
  shopt -s nullglob
  built=( "${JAVA_DIR}"/target/*.jar )
  shopt -u nullglob
  JAR_FILE="${built[0]:-}"
fi
if [[ -z "${JAR_FILE}" || ! -f "$JAR_FILE" ]]; then
  echo "❌ JAR não gerado em ${JAVA_DIR}/target/" >&2
  exit 1
fi

echo "    Deploying: $JAR_FILE"
az webapp deploy \
  --resource-group "$RG" \
  --name "$WEBAPP_NAME" \
  --src-path "$JAR_FILE" \
  --type jar >/dev/null
echo "    Deploy concluído!"

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
WEBAPP_URL="https://${WEBAPP_NAME}.azurewebsites.net"
PG_HOST="${PG_SERVER_NAME}.postgres.database.azure.com"
PG_PASS_ENC="$PG_ADMIN_PASSWORD"
if command -v python3 >/dev/null 2>&1; then
  PG_PASS_ENC="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PG_ADMIN_PASSWORD")"
fi
PG_URI="postgresql://${PG_ADMIN_USER}:${PG_PASS_ENC}@${PG_HOST}:5432/${PG_DB_NAME}?sslmode=require"

echo ""
echo "============================================="
echo " ✅ Infraestrutura criada com sucesso!"
echo "============================================="
echo " Resource Group:  $RG"
echo " PostgreSQL:      $PG_HOST"
echo " Database:        $PG_DB_NAME"
echo " Key Vault:       $KEYVAULT_NAME"
echo " App Service:     $WEBAPP_NAME"
echo " URL da App:      $WEBAPP_URL"
echo " API base:        ${WEBAPP_URL}/veti"
echo ""
echo " Connection URI:  $PG_URI"
echo " JDBC:            $PG_JDBC_URL"
echo " DBeaver:         $PG_HOST:5432  user=${PG_ADMIN_USER}  db=${PG_DB_NAME}  SSL=require"
echo ""
echo " Próximo passo:   ./azure_test_infra.sh"
echo "                  ./azure_test_crud.sh   # imprime curls para copiar"
echo "============================================="
