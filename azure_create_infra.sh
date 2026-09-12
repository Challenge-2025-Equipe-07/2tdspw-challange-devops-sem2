#!/usr/bin/env bash
# =============================================================================
# Opção B — App Service (Web App) + Azure SQL Database (PaaS)
# Time CCGL · RM564113 · Região chilecentral
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Parâmetros centrais
# ---------------------------------------------------------------------------
RM_ID="rm564113"
LOCATION="chilecentral"
RG="rg-challenge-devops"

SQL_SERVER_NAME="sql-ccgl-${RM_ID}"
SQL_DB_NAME="db-challenge"
SQL_ADMIN_USER="sqladmin"
SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-}"

KEYVAULT_NAME="kv-ccgl-${RM_ID}"

APP_SERVICE_PLAN="plan-ccgl-${RM_ID}"
WEBAPP_NAME="app-ccgl-${RM_ID}"

JAR_PATH="${JAR_PATH:-target/*.jar}"
APP_PORT="${APP_PORT:-8080}"

JWT_SECRET="${JWT_SECRET:-veti-default-secret-change-in-production}"

# ---------------------------------------------------------------------------
# Solicita senha do SQL se não fornecida
# ---------------------------------------------------------------------------
if [[ -z "$SQL_ADMIN_PASSWORD" ]]; then
    read -r -s -p "Defina a senha do Azure SQL (admin=$SQL_ADMIN_USER): " SQL_ADMIN_PASSWORD
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

echo "============================================="
echo " Opção B: App Service + Azure SQL (PaaS)"
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
az provider register --namespace Microsoft.Web          >/dev/null
az provider register --namespace Microsoft.Sql          >/dev/null
az provider register --namespace Microsoft.KeyVault     >/dev/null

# ---------------------------------------------------------------------------
# 3. Resource Group
# ---------------------------------------------------------------------------
echo "==> [3/8] Criando Resource Group: $RG ($LOCATION)"
az group create --name "$RG" --location "$LOCATION" >/dev/null

# ---------------------------------------------------------------------------
# 4. Azure SQL Database (PaaS) — camada mais barata
# ---------------------------------------------------------------------------
echo "==> [4/8] Criando Azure SQL Server: $SQL_SERVER_NAME"
az sql server create \
--name "$SQL_SERVER_NAME" \
--resource-group "$RG" \
--location "$LOCATION" \
--admin-user "$SQL_ADMIN_USER" \
--admin-password "$SQL_ADMIN_PASSWORD" \
--enable-public-network true >/dev/null

echo "==> [4/8] Criando banco de dados: $SQL_DB_NAME (Basic — ~\$5/mês)"
az sql db create \
--resource-group "$RG" \
--server "$SQL_SERVER_NAME" \
--name "$SQL_DB_NAME" \
--service-objective Basic \
--backup-storage-redundancy Local \
--zone-redundant false >/dev/null

echo "==> [4/8] Liberando acesso temporário (todos os IPs) para setup"
az sql server firewall-rule create \
--resource-group "$RG" \
--server "$SQL_SERVER_NAME" \
--name "AllowAllSetup" \
--start-ip-address 0.0.0.0 \
--end-ip-address 255.255.255.255 >/dev/null

echo "==> [4/8] Liberando serviços Azure (App Service → SQL)"
az sql server firewall-rule create \
--resource-group "$RG" \
--server "$SQL_SERVER_NAME" \
--name "AllowAzureServices" \
--start-ip-address 0.0.0.0 \
--end-ip-address 0.0.0.0 >/dev/null

SQL_JDBC_URL="jdbc:sqlserver://${SQL_SERVER_NAME}.database.windows.net:1433;database=${SQL_DB_NAME};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"

# ---------------------------------------------------------------------------
# 5. Key Vault — guardar segredos
# ---------------------------------------------------------------------------
echo "==> [5/8] Criando/atualizando Key Vault: $KEYVAULT_NAME"
# Access policies (não RBAC): evita ForbiddenByRbac ao setar secrets com a conta do az login
if az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RG" >/dev/null 2>&1; then
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
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "sql-jdbc-url"  --value "$SQL_JDBC_URL"        >/dev/null
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "sql-username"  --value "$SQL_ADMIN_USER"      >/dev/null
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "sql-password"  --value "$SQL_ADMIN_PASSWORD"  >/dev/null
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "jwt-secret"    --value "$JWT_SECRET"          >/dev/null

# ---------------------------------------------------------------------------
# 6. App Service Plan (F1 = Free ou B1 = Basic ~$13/mês)
# ---------------------------------------------------------------------------
echo "==> [6/8] Criando App Service Plan: $APP_SERVICE_PLAN (B1 — Linux)"
az appservice plan create \
--name "$APP_SERVICE_PLAN" \
--resource-group "$RG" \
--location "$LOCATION" \
--sku B1 \
--is-linux >/dev/null

# ---------------------------------------------------------------------------
# 7. Web App (Java 21 — alinhado ao pom.xml do projeto)
# ---------------------------------------------------------------------------
echo "==> [7/8] Criando Web App: $WEBAPP_NAME"
az webapp create \
--name "$WEBAPP_NAME" \
--resource-group "$RG" \
--plan "$APP_SERVICE_PLAN" \
--runtime "JAVA:21-java21" >/dev/null

GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-disabled-placeholder}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-disabled-placeholder}"

echo "==> [7/8] Configurando variáveis de ambiente (App Settings)"
az webapp config appsettings set \
--resource-group "$RG" \
--name "$WEBAPP_NAME" \
--settings \
SPRING_PROFILES_ACTIVE="azure" \
DB_URL="$SQL_JDBC_URL" \
DB_USER="$SQL_ADMIN_USER" \
DB_PASSWORD="$SQL_ADMIN_PASSWORD" \
SPRING_DATASOURCE_URL="$SQL_JDBC_URL" \
SPRING_DATASOURCE_USERNAME="$SQL_ADMIN_USER" \
SPRING_DATASOURCE_PASSWORD="$SQL_ADMIN_PASSWORD" \
SPRING_DATASOURCE_DRIVER_CLASS_NAME="com.microsoft.sqlserver.jdbc.SQLServerDriver" \
SPRING_JPA_DATABASE_PLATFORM="org.hibernate.dialect.SQLServerDialect" \
SPRING_JPA_HIBERNATE_DDL_AUTO="update" \
SPRING_H2_CONSOLE_ENABLED="false" \
JWT_SECRET="$JWT_SECRET" \
GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
WEBSITES_PORT="$APP_PORT" >/dev/null

# ---------------------------------------------------------------------------
# 8. Deploy do JAR
# ---------------------------------------------------------------------------
echo "==> [8/8] Deploy do JAR no Web App"
echo "    Procurando: $JAR_PATH"

shopt -s nullglob
JAR_FILES=($JAR_PATH)
shopt -u nullglob

if [[ ${#JAR_FILES[@]} -eq 0 ]]; then
    echo ""
    echo "⚠️  Nenhum JAR encontrado em '$JAR_PATH'."
    echo "   Faça o build primeiro: ./mvnw clean package -DskipTests"
    echo "   Depois rode: az webapp deploy --resource-group $RG --name $WEBAPP_NAME --src-path <caminho-do.jar> --type jar"
    echo ""
else
    JAR_FILE="${JAR_FILES[0]}"
    echo "    Deploying: $JAR_FILE"
    az webapp deploy \
    --resource-group "$RG" \
    --name "$WEBAPP_NAME" \
    --src-path "$JAR_FILE" \
    --type jar >/dev/null
    echo "    Deploy concluído!"
fi

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
WEBAPP_URL="https://${WEBAPP_NAME}.azurewebsites.net"

echo ""
echo "============================================="
echo " ✅ Infraestrutura criada com sucesso!"
echo "============================================="
echo " Resource Group:  $RG"
echo " SQL Server:      ${SQL_SERVER_NAME}.database.windows.net"
echo " SQL Database:    $SQL_DB_NAME"
echo " Key Vault:       $KEYVAULT_NAME"
echo " App Service:     $WEBAPP_NAME"
echo " URL da App:      $WEBAPP_URL"
echo " API base:        ${WEBAPP_URL}/veti"
echo " Health:          ${WEBAPP_URL}/veti/health"
echo ""
echo " Próximo passo:   ./azure_test_infra.sh && ./azure_test_crud.sh"
echo "============================================="
