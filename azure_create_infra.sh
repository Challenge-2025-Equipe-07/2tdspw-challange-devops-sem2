#!/usr/bin/env bash
# =============================================================================
# Opção 2 — App Service (Web App) + Azure Database for PostgreSQL (PaaS)
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
LAW_NAME="law-ccgl-${RM_ID}"
APPINSIGHTS_NAME="appi-ccgl-${RM_ID}"

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
  [[ -n "$reason" ]] && echo "==> [4/9] Aguardando PostgreSQL Ready ($reason)"
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
echo " Opção 2: App Service + PostgreSQL Flexible Server (PaaS)"
echo " Time CCGL · RM564113 · chilecentral"
echo "============================================="

# ---------------------------------------------------------------------------
# 1. Login
# ---------------------------------------------------------------------------
echo "==> [1/9] Login no Azure"
if ! az account show >/dev/null 2>&1; then
  az login
fi

# ---------------------------------------------------------------------------
# 2. Registrar providers
# ---------------------------------------------------------------------------
echo "==> [2/9] Registrando provedores de recursos"
az provider register --namespace Microsoft.Web                 >/dev/null
az provider register --namespace Microsoft.DBforPostgreSQL     >/dev/null
az provider register --namespace Microsoft.KeyVault            >/dev/null
az provider register --namespace Microsoft.Insights            >/dev/null
az provider register --namespace Microsoft.OperationalInsights >/dev/null

# ---------------------------------------------------------------------------
# 3. Resource Group
# ---------------------------------------------------------------------------
echo "==> [3/9] Criando Resource Group: $RG ($LOCATION)"
az group create --name "$RG" --location "$LOCATION" >/dev/null

# ---------------------------------------------------------------------------
# 4. Azure Database for PostgreSQL Flexible Server (PaaS)
# ---------------------------------------------------------------------------
echo "==> [4/9] Criando PostgreSQL Flexible Server: $PG_SERVER_NAME (Burstable B1ms)"
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

echo "==> [4/9] Garantindo database: $PG_DB_NAME"
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

ensure_firewall() {
  local rule_name="$1"
  local start_ip="$2"
  local end_ip="$3"
  if az postgres flexible-server firewall-rule show \
       --resource-group "$RG" \
       --name "$PG_SERVER_NAME" \
       --rule-name "$rule_name" >/dev/null 2>&1; then
    echo "    Firewall ${rule_name} já existe"
    return 0
  fi
  az_pg_retry az postgres flexible-server firewall-rule create \
    --resource-group "$RG" \
    --name "$PG_SERVER_NAME" \
    --rule-name "$rule_name" \
    --start-ip-address "$start_ip" \
    --end-ip-address "$end_ip" >/dev/null
}

echo "==> [4/9] Liberando serviços Azure (App Service → PostgreSQL)"
ensure_firewall AllowAzureServices 0.0.0.0 0.0.0.0

PG_JDBC_URL="jdbc:postgresql://${PG_SERVER_NAME}.postgres.database.azure.com:5432/${PG_DB_NAME}?sslmode=require"

# ---------------------------------------------------------------------------
# 5. Key Vault — guardar segredos
# ---------------------------------------------------------------------------
echo "==> [5/9] Criando/atualizando Key Vault: $KEYVAULT_NAME"
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

echo "==> [5/9] Concedendo permissão de secrets ao usuário atual"
az keyvault set-policy \
  --name "$KEYVAULT_NAME" \
  --object-id "$CURRENT_OID" \
  --secret-permissions get list set delete >/dev/null

echo "==> [5/9] Salvando segredos no Key Vault"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "pg-jdbc-url"  --value "$PG_JDBC_URL"        >/dev/null
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "pg-username"  --value "$PG_ADMIN_USER"      >/dev/null
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "pg-password"  --value "$PG_ADMIN_PASSWORD"  >/dev/null
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "jwt-secret"   --value "$JWT_SECRET"         >/dev/null

# ---------------------------------------------------------------------------
# 6. App Service Plan
# ---------------------------------------------------------------------------
echo "==> [6/9] Criando App Service Plan: $APP_SERVICE_PLAN (B1 — Linux)"
if az appservice plan show --resource-group "$RG" --name "$APP_SERVICE_PLAN" >/dev/null 2>&1; then
  echo "    Plan já existe — reutilizando"
else
  az appservice plan create \
    --name "$APP_SERVICE_PLAN" \
    --resource-group "$RG" \
    --location "$LOCATION" \
    --sku B1 \
    --is-linux >/dev/null
fi

# ---------------------------------------------------------------------------
# 7. Web App (Java 21)
# ---------------------------------------------------------------------------
echo "==> [7/9] Criando Web App: $WEBAPP_NAME"
if az webapp show --resource-group "$RG" --name "$WEBAPP_NAME" >/dev/null 2>&1; then
  echo "    Web App já existe — reutilizando"
else
  az webapp create \
    --name "$WEBAPP_NAME" \
    --resource-group "$RG" \
    --plan "$APP_SERVICE_PLAN" \
    --runtime "JAVA:21-java21" >/dev/null
fi

# ---------------------------------------------------------------------------
# 8. Log Analytics + Application Insights + diagnostic settings
# O agente Java 3.x do App Service Linux é anexado pela plataforma quando
# APPLICATIONINSIGHTS_CONNECTION_STRING e ApplicationInsightsAgent_EXTENSION_VERSION=~3
# estão definidos. A plataforma injeta JAVA_TOOL_OPTIONS. Não definimos esse
# valor aqui para não apontar para um JAR que o runtime ainda não baixou.
# healthCheckPath=/health é aplicado depois do deploy do JAR.
# ---------------------------------------------------------------------------
echo "==> [8/9] Criando Log Analytics: $LAW_NAME"
OBS_LOCATION="$LOCATION"
if az monitor log-analytics workspace show \
     --resource-group "$RG" \
     --workspace-name "$LAW_NAME" >/dev/null 2>&1; then
  echo "    Workspace já existe — reutilizando"
  OBS_LOCATION="$(az monitor log-analytics workspace show \
    --resource-group "$RG" \
    --workspace-name "$LAW_NAME" \
    --query location -o tsv)"
else
  set +e
  LAW_OUT="$(az monitor log-analytics workspace create \
    --resource-group "$RG" \
    --workspace-name "$LAW_NAME" \
    --location "$OBS_LOCATION" 2>&1)"
  LAW_RC=$?
  set -e
  if [[ $LAW_RC -ne 0 ]]; then
    if az monitor log-analytics workspace show \
         --resource-group "$RG" \
         --workspace-name "$LAW_NAME" >/dev/null 2>&1; then
      echo "    Create retornou erro, mas o workspace existe — continuando"
    else
      echo "    ${OBS_LOCATION} recusou o Log Analytics — tentando eastus2"
      printf '%s\n' "$LAW_OUT" >&2
      OBS_LOCATION="eastus2"
      az monitor log-analytics workspace create \
        --resource-group "$RG" \
        --workspace-name "$LAW_NAME" \
        --location "$OBS_LOCATION" >/dev/null
    fi
  fi
fi

LAW_ID="$(az monitor log-analytics workspace show \
  --resource-group "$RG" \
  --workspace-name "$LAW_NAME" \
  --query id -o tsv)"

echo "==> [8/9] Criando Application Insights: $APPINSIGHTS_NAME ($OBS_LOCATION)"
if az monitor app-insights component show \
     --app "$APPINSIGHTS_NAME" \
     --resource-group "$RG" >/dev/null 2>&1; then
  echo "    Application Insights já existe — reutilizando"
else
  az monitor app-insights component create \
    --app "$APPINSIGHTS_NAME" \
    --location "$OBS_LOCATION" \
    --resource-group "$RG" \
    --workspace "$LAW_ID" \
    --kind web \
    --application-type web >/dev/null
fi

APPINSIGHTS_CS="$(az monitor app-insights component show \
  --app "$APPINSIGHTS_NAME" \
  --resource-group "$RG" \
  --query connectionString -o tsv)"
if [[ -z "$APPINSIGHTS_CS" ]]; then
  echo "❌ Connection string do Application Insights vazia" >&2
  exit 1
fi

echo "==> [8/9] Salvando connection string no Key Vault"
az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "appinsights-connection-string" \
  --value "$APPINSIGHTS_CS" >/dev/null

GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-disabled-placeholder}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-disabled-placeholder}"

echo "==> [8/9] Configurando App Settings (banco, JWT e Application Insights)"
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
    WEBSITES_PORT="$APP_PORT" \
    APPLICATIONINSIGHTS_CONNECTION_STRING="$APPINSIGHTS_CS" \
    ApplicationInsightsAgent_EXTENSION_VERSION="~3" >/dev/null

echo "==> [8/9] Habilitando log de aplicação e de container"
set +e
LOG_OUT="$(az webapp log config \
  --resource-group "$RG" \
  --name "$WEBAPP_NAME" \
  --application-logging filesystem \
  --level information \
  --docker-container-logging filesystem 2>&1)"
LOG_RC=$?
set -e
if [[ $LOG_RC -ne 0 ]]; then
  echo "    Log em filesystem recusado no Linux — habilitando o log do container"
  printf '%s\n' "$LOG_OUT" >&2
  az webapp log config \
    --resource-group "$RG" \
    --name "$WEBAPP_NAME" \
    --docker-container-logging filesystem >/dev/null
fi

WEBAPP_ID="$(az webapp show --resource-group "$RG" --name "$WEBAPP_NAME" --query id -o tsv)"

apply_diag() {
  local logs_json="$1"
  az monitor diagnostic-settings create \
    --name diag-webapp \
    --resource "$WEBAPP_ID" \
    --workspace "$LAW_ID" \
    --logs "$logs_json" \
    --metrics '[{"category":"AllMetrics","enabled":true}]'
}

remove_diag() {
  az monitor diagnostic-settings delete \
    --name diag-webapp \
    --resource "$WEBAPP_ID" >/dev/null 2>&1 || true
}

echo "==> [8/9] Diagnostic settings do Web App → Log Analytics"
remove_diag
set +e
DIAG_OUT="$(apply_diag '[{"category":"AppServiceHTTPLogs","enabled":true},{"category":"AppServiceConsoleLogs","enabled":true},{"category":"AppServiceAppLogs","enabled":true}]' 2>&1)"
DIAG_RC=$?
set -e
if [[ $DIAG_RC -ne 0 ]]; then
  echo "    Categorias explícitas recusadas — usando allLogs"
  printf '%s\n' "$DIAG_OUT" >&2
  remove_diag
  apply_diag '[{"categoryGroup":"allLogs","enabled":true}]' >/dev/null
fi

# ---------------------------------------------------------------------------
# 9. Clone da API Java, build e deploy do JAR
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# No repositório da API o mvnw está ao lado do script. Neste repositório de infra, o fonte fica na pasta clonada.
if [[ -x "${SCRIPT_DIR}/mvnw" ]]; then
  JAVA_DIR="$SCRIPT_DIR"
else
  JAVA_DIR="${SCRIPT_DIR}/${JAVA_DIR_NAME}"
fi

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

echo "==> [9/9] Clone + build + deploy da API Veti"
if [[ -d "${JAVA_DIR}/.git" ]]; then
  echo "    Repositório já existe em ${JAVA_DIR_NAME}/ — atualizando"
  git -C "$JAVA_DIR" pull --ff-only || true
elif [[ -x "${JAVA_DIR}/mvnw" ]]; then
  echo "    Fonte já presente em ${JAVA_DIR_NAME}/ — usando esta cópia"
elif [[ -e "$JAVA_DIR" ]]; then
  echo "❌ ${JAVA_DIR_NAME}/ existe, mas não é um clone git nem tem mvnw" >&2
  exit 1
else
  echo "    git clone --branch main ${JAVA_REPO_URL}"
  git clone --depth 1 --branch main "$JAVA_REPO_URL" "$JAVA_DIR"
fi

chmod +x "${JAVA_DIR}/mvnw"
WRAPPER_PROPS="${JAVA_DIR}/.mvn/wrapper/maven-wrapper.properties"
if [[ ! -f "$WRAPPER_PROPS" ]]; then
  echo "    Maven Wrapper ausente no repositório — recriando maven-wrapper.properties"
  mkdir -p "${JAVA_DIR}/.mvn/wrapper"
  cat > "$WRAPPER_PROPS" <<'EOF'
wrapperVersion=3.3.4
distributionType=only-script
distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.15/apache-maven-3.9.15-bin.zip
EOF
fi
pick_java21
echo "    JAVA_HOME=${JAVA_HOME:-}"
echo "    ./mvnw clean package -DskipTests"
echo "    (os testes rodam na pipeline do repositório Java; o deploy só publica o JAR)"
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

echo "    healthCheckPath=/health"
az webapp config set \
  --resource-group "$RG" \
  --name "$WEBAPP_NAME" \
  --generic-configurations '{"healthCheckPath": "/health"}' >/dev/null

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
WEBAPP_URL="https://${WEBAPP_NAME}.azurewebsites.net"
PG_HOST="${PG_SERVER_NAME}.postgres.database.azure.com"
PG_PASS_ENC="$PG_ADMIN_PASSWORD"
if command -v python3 >/dev/null 2>&1; then
  PG_PASS_ENC="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PG_ADMIN_PASSWORD")"
fi
PG_URI="postgres://${PG_ADMIN_USER}:${PG_PASS_ENC}@${PG_HOST}:5432/${PG_DB_NAME}?sslmode=require"

echo ""
echo "============================================="
echo " ✅ Infraestrutura criada com sucesso!"
echo "============================================="
echo " Resource Group:  $RG"
echo " PostgreSQL:      $PG_HOST"
echo " Database:        $PG_DB_NAME"
echo " Key Vault:       $KEYVAULT_NAME"
echo " Log Analytics:   $LAW_NAME ($OBS_LOCATION)"
echo " App Insights:    $APPINSIGHTS_NAME"
echo " App Service:     $WEBAPP_NAME"
echo " URL da App:      $WEBAPP_URL"
echo " API base:        ${WEBAPP_URL}/veti"
echo " Probe atual:     GET /health"
echo ""
echo " Beekeeper URL:   $PG_URI"
echo " JDBC (app only): $PG_JDBC_URL"
echo " Manual:          host=$PG_HOST  port=5432  user=${PG_ADMIN_USER}  db=${PG_DB_NAME}"
echo "                  SSL = Trust the server (não verifique o certificado)"
echo ""
echo " Próximo passo:   ./azure_test_infra.sh"
echo "                  ./azure_test_crud.sh   # CRUD HTTP + SELECT no banco"
echo "                  ./tests/run_newman.sh  # 5 casos Postman/Newman"
echo "============================================="
