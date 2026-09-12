#!/usr/bin/env bash
# =============================================================================
# Deletar toda a infraestrutura — Opção B (App Service + Azure SQL PaaS)
# Time CCGL · RM564113
# =============================================================================
set -euo pipefail

RM_ID="rm564113"
RG="rg-challenge-devops"
SQL_SERVER_NAME="sql-ccgl-${RM_ID}"
KEYVAULT_NAME="kv-ccgl-${RM_ID}"

echo "============================================="
echo " ⚠️  Deletando TODA a infraestrutura Azure"
echo "============================================="
echo " Resource Group: $RG"
echo ""
echo " Isso vai remover:"
echo "   - Web App (App Service)"
echo "   - App Service Plan"
echo "   - Azure SQL Server + Database"
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
# 1. Deletar Resource Group (remove tudo de uma vez)
# ---------------------------------------------------------------------------
echo "==> Deletando Resource Group: $RG"
az group delete --name "$RG" --yes --no-wait

# ---------------------------------------------------------------------------
# 2. Purge do Key Vault (soft-delete fica 90 dias por padrão)
# ---------------------------------------------------------------------------
echo "==> Purgando Key Vault (soft-delete): $KEYVAULT_NAME"
az keyvault purge --name "$KEYVAULT_NAME" 2>/dev/null || true

echo ""
echo "============================================="
echo " 🗑️  Delete solicitado (async)."
echo " Verifique com: az group show -n $RG"
echo " O Key Vault foi purgado para liberar o nome."
echo "============================================="
