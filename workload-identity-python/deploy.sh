#!/usr/bin/env bash
# Deploys the workload-identity-python demo: an AKS cluster with Microsoft Entra
# Workload ID, a Key Vault secret, and a Python pod that reads the secret through
# a federated managed identity (no keys or passwords anywhere).
#
# Usage: ./deploy.sh
#
# Optional environment variables:
#   RESOURCE_GROUP  Resource group to create/use (default: rg-workload-identity-python)
#   LOCATION        Azure region (default: eastus)
#   NODE_VM_SIZE    AKS node size (default: Standard_D2s_v5)

set -Eeuo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../scripts/common.sh
source "$DEMO_DIR/../scripts/common.sh"
init_demo "$@"

require_tools az kubectl
require_az_login
register_providers Microsoft.ContainerService Microsoft.ContainerRegistry \
  Microsoft.KeyVault Microsoft.ManagedIdentity
ensure_resource_group
deploy_bicep ${NODE_VM_SIZE:+"nodeVmSize=$NODE_VM_SIZE"}
read_outputs \
  CLUSTER_NAME=clusterName \
  ACR_NAME=acrName \
  ACR_LOGIN_SERVER=acrLoginServer \
  KEY_VAULT_URL=keyVaultUri \
  SECRET_NAME=secretName \
  IDENTITY_CLIENT_ID=identityClientId

# shellcheck disable=SC2034 # IMAGE is used in k8s/wi-pod.yaml.
IMAGE="$ACR_LOGIN_SERVER/wi-kv-test:1.0"
build_image "$ACR_NAME" "$ACR_LOGIN_SERVER" wi-kv-test:1.0 "$DEMO_DIR/src"
aks_get_credentials "$CLUSTER_NAME"

info "Creating the service account (annotated with the managed identity's client ID)..."
render_template "$DEMO_DIR/k8s/wi-sa.yaml" IDENTITY_CLIENT_ID | kubectl apply -f -

# (Re)creates the pod and checks that the workload identity webhook injected the token.
deploy_pod() {
  kubectl delete pod wi-kv-test --ignore-not-found --wait=true >/dev/null &&
    render_template "$DEMO_DIR/k8s/wi-pod.yaml" IMAGE KEY_VAULT_URL SECRET_NAME |
    kubectl apply -f - &&
    [[ -n "$(kubectl get pod wi-kv-test \
      -o jsonpath='{.spec.containers[0].env[?(@.name=="AZURE_FEDERATED_TOKEN_FILE")].value}')" ]]
}
info "Starting the sample pod..."
retry 10 15 deploy_pod || die "The workload identity webhook didn't inject the pod. Check 'kubectl get pods -n kube-system'."
kubectl wait --for=condition=Ready pod/wi-kv-test --timeout=300s

secret_was_read() { kubectl logs wi-kv-test 2>/dev/null | grep -q "Secret value:"; }
info "Waiting for the pod to read the secret (role assignments can take a minute to apply)..."
if ! retry 30 10 secret_was_read; then
  kubectl logs wi-kv-test --tail=20 || true
  die "The pod hasn't read the secret yet. Follow it with: kubectl logs -f wi-kv-test"
fi
kubectl logs wi-kv-test | grep "Secret value:" | tail -n 1

cat <<EOF

Done! The pod read the Key Vault secret using its federated identity.

  Follow the logs:     kubectl logs -f wi-kv-test
  Injected variables:  kubectl describe pod wi-kv-test | grep AZURE_
  Clean up:            ./destroy.sh
EOF
