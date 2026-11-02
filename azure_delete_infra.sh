#!/usr/bin/env bash
# =============================================================================
# Deletar toda a infraestrutura — Opção 2 (App Service + PostgreSQL PaaS)
# Time CCGL · RM564113
# =============================================================================
set -euo pipefail

RM_ID="rm564113"
LOCATION="chilecentral"
RG="rg-challenge-devops"
KEYVAULT_NAME="kv-ccgl-${RM_ID}"

echo "============================================="
echo " ⚠️  Deletando TODA a infraestrutura Azure"
echo "============================================="
echo " Resource Group: $RG"
echo ""
echo " Isso vai remover:"
echo "   - Web App (App Service)"
echo "   - App Service Plan"
echo "   - Azure Database for PostgreSQL Flexible Server"
echo "   - Application Insights"
echo "   - Log Analytics"
echo "   - Key Vault"
echo "   - Todos os recursos do grupo"
echo ""

read -r -p "Tem certeza? (y/N): " CONFIRM
case "$CONFIRM" in
  y|Y|yes|YES) ;;
  *)
    echo "Cancelado."
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# 1. Purge do Key Vault ANTES do RG (senão o nome fica preso em soft-delete)
# ---------------------------------------------------------------------------
echo "==> Removendo Key Vault: $KEYVAULT_NAME"
if az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RG" >/dev/null 2>&1; then
  az keyvault delete --name "$KEYVAULT_NAME" --resource-group "$RG" >/dev/null || true
fi
echo "==> Purgando Key Vault (libera o nome para o próximo create)"
az keyvault purge --name "$KEYVAULT_NAME" --location "$LOCATION" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Deletar Resource Group (remove o restante)
# ---------------------------------------------------------------------------
echo "==> Deletando Resource Group: $RG"
az group delete --name "$RG" --yes --no-wait

echo ""
echo "============================================="
echo " 🗑️  Delete solicitado (async)."
echo " Verifique com: az group show -n $RG"
echo " O Key Vault foi purgado para liberar o nome."
echo "============================================="
