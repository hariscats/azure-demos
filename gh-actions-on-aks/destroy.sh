#!/usr/bin/env bash
# Deletes everything the gh-actions-on-aks demo created. It first uninstalls the
# runner scale set so that ARC removes its registration from GitHub, then deletes
# the resource group (AKS cluster) and the cluster's kubectl context.
#
# Usage: ./destroy.sh [--yes]
#
# Optional environment variables:
#   RESOURCE_GROUP  Resource group to delete (default: rg-gh-actions-on-aks)

set -Eeuo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../scripts/common.sh
source "$DEMO_DIR/../scripts/common.sh"
init_demo "$@"

RUNNER_SET="arc-runner-set"
MANUAL_CLEANUP="If '$RUNNER_SET' is still listed in GitHub (Settings > Actions > Runners), remove it there."

# Without this step the scale set stays registered (offline) in GitHub after the cluster is gone.
unregister_runner_set() {
  local clusters cluster releases
  clusters="$(az aks list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)"
  cluster="${clusters%%"$NL"*}"
  [[ -n "$cluster" ]] || return 0
  if ! command -v helm >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
    warn "helm and kubectl are needed to unregister the runner scale set. $MANUAL_CLEANUP"
    return 0
  fi
  aks_get_credentials "$cluster" || {
    warn "Couldn't get credentials for '$cluster'. $MANUAL_CLEANUP"
    return 0
  }
  if ! releases="$(helm list --namespace arc-runners --kube-context "$cluster" --short \
    --filter "^$RUNNER_SET\$" 2>&1)"; then
    warn "Couldn't reach cluster '$cluster': $releases"
    warn "$MANUAL_CLEANUP"
    return 0
  fi
  [[ -n "$releases" ]] || return 0
  info "Uninstalling the runner scale set so that ARC unregisters it from GitHub..."
  helm uninstall "$RUNNER_SET" --namespace arc-runners --kube-context "$cluster" \
    --wait --timeout 5m || warn "Couldn't uninstall '$RUNNER_SET'. $MANUAL_CLEANUP"
}

require_tools az
require_az_login
if confirm_destroy; then
  unregister_runner_set
  destroy_resource_group
fi
