#!/usr/bin/env bash
# Deploys the gh-actions-on-aks demo: an AKS cluster running GitHub Actions Runner
# Controller (ARC) with an autoscaling runner scale set named "arc-runner-set".
# Jobs that use "runs-on: arc-runner-set" run in pods that are created on demand.
#
# Usage: ./deploy.sh
#
# Environment variables:
#   GITHUB_PAT         GitHub personal access token that can manage self-hosted runners
#                      (prompted for when not set). See the README for the required scopes.
#   GITHUB_CONFIG_URL  Repository or organization to register the runners with
#                      (default: this clone's GitHub "origin" remote)
#   RESOURCE_GROUP     Resource group to create/use (default: rg-gh-actions-on-aks)
#   LOCATION           Azure region (default: eastus)
#   NODE_VM_SIZE       AKS node size (default: Standard_D2s_v5)
#   MAX_RUNNERS        Maximum number of runners (default: 3)
#   ARC_VERSION        ARC Helm chart version (default: latest)

set -Eeuo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../scripts/common.sh
source "$DEMO_DIR/../scripts/common.sh"
init_demo "$@"

ARC_CHARTS="oci://ghcr.io/actions/actions-runner-controller-charts"
RUNNER_SET="arc-runner-set"
MAX_RUNNERS="${MAX_RUNNERS:-3}"

# Prints https://github.com/<owner>/<repo> for this clone's origin remote, if it's on github.com.
origin_github_url() {
  local url
  url="$(git -C "$DEMO_DIR" remote get-url origin 2>/dev/null)" || return 0
  url="${url%/}"
  url="${url%.git}"
  case "$url" in
    git@github.com:*) url="${url#git@github.com:}" ;;
    ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
    https://github.com/*) url="${url#https://github.com/}" ;;
    https://*@github.com/*) url="${url#https://*@github.com/}" ;;
    *) return 0 ;;
  esac
  printf 'https://github.com/%s\n' "$url"
}

# Fails fast (before any Azure resources are created) when GitHub rejects the token.
check_github_token() {
  local path code
  case "$GITHUB_CONFIG_URL" in
    https://github.com/enterprises/*) return 0 ;;
    https://github.com/*/*) path="repos/${GITHUB_CONFIG_URL#https://github.com/}" ;;
    https://github.com/*) path="orgs/${GITHUB_CONFIG_URL#https://github.com/}" ;;
    *) return 0 ;;
  esac
  command -v curl >/dev/null 2>&1 || return 0
  info "Checking that the token can manage self-hosted runners for $GITHUB_CONFIG_URL..."
  # The token is passed on stdin so that it doesn't show up in the process list.
  code="$(printf 'Authorization: %s %s\n' "Bearer" "$GITHUB_PAT" |
    curl --silent --max-time 20 --header @- --header "Accept: application/vnd.github+json" \
      --output /dev/null --write-out '%{http_code}' "https://api.github.com/$path/actions/runners" ||
    true)"
  case "$code" in
    200) ;;
    401) die "GitHub rejected the token (HTTP 401). Check GITHUB_PAT." ;;
    403 | 404) die "The token can't manage self-hosted runners for $GITHUB_CONFIG_URL (HTTP $code). See the README for the required scopes." ;;
    *) warn "Couldn't verify the token with the GitHub API (HTTP ${code:-000}). Continuing anyway." ;;
  esac
}

listener_running() {
  [[ "$(kubectl get pods --namespace arc-systems \
    --selector "app.kubernetes.io/component=runner-scale-set-listener,actions.github.com/scale-set-name=$RUNNER_SET" \
    --output jsonpath='{.items[*].status.phase}')" == *Running* ]]
}

require_tools az kubectl helm

GITHUB_CONFIG_URL="${GITHUB_CONFIG_URL:-$(origin_github_url)}"
GITHUB_CONFIG_URL="${GITHUB_CONFIG_URL%/}"
[[ -n "$GITHUB_CONFIG_URL" ]] ||
  die "Set GITHUB_CONFIG_URL to the repository to register runners with, e.g. GITHUB_CONFIG_URL=https://github.com/<owner>/<repo> ./deploy.sh"
[[ "$MAX_RUNNERS" =~ ^[0-9]+$ ]] || die "MAX_RUNNERS must be a number."
if [[ -z "${GITHUB_PAT:-}" ]]; then
  [[ -t 0 ]] || die "Set GITHUB_PAT to a GitHub personal access token (see the README)."
  read -r -s -p "GitHub personal access token for $GITHUB_CONFIG_URL: " GITHUB_PAT
  echo >&2
  [[ -n "$GITHUB_PAT" ]] || die "A GitHub personal access token is required."
fi
info "Runners will be registered with: $GITHUB_CONFIG_URL"
check_github_token

require_az_login
register_providers Microsoft.ContainerService
ensure_resource_group
deploy_bicep ${NODE_VM_SIZE:+"nodeVmSize=$NODE_VM_SIZE"}
read_outputs CLUSTER_NAME=clusterName
aks_get_credentials "$CLUSTER_NAME"

info "Installing the ARC controller (Helm release 'arc' in namespace arc-systems)..."
helm upgrade --install arc "$ARC_CHARTS/gha-runner-scale-set-controller" \
  --namespace arc-systems --create-namespace ${ARC_VERSION:+--version "$ARC_VERSION"} --wait

info "Storing the GitHub token in the Kubernetes secret arc-runners/arc-github-secret..."
kubectl create namespace arc-runners --dry-run=client --output yaml | kubectl apply --filename -
printf '%s' "$GITHUB_PAT" |
  kubectl create secret generic arc-github-secret --namespace arc-runners \
    --from-file=github_token=/dev/stdin --dry-run=client --output yaml |
  kubectl apply --filename -

info "Installing the runner scale set '$RUNNER_SET' (0-$MAX_RUNNERS runners)..."
helm upgrade --install "$RUNNER_SET" "$ARC_CHARTS/gha-runner-scale-set" \
  --namespace arc-runners ${ARC_VERSION:+--version "$ARC_VERSION"} \
  --set githubConfigUrl="$GITHUB_CONFIG_URL" \
  --set githubConfigSecret=arc-github-secret \
  --set minRunners=0 \
  --set maxRunners="$MAX_RUNNERS" \
  --wait

info "Waiting for the scale set listener to connect to GitHub..."
if ! retry 36 5 listener_running; then
  kubectl logs --namespace arc-systems deployment/arc-gha-rs-controller --tail=20 || true
  die "The listener for '$RUNNER_SET' didn't start. Check the controller logs above, the token's scopes and GITHUB_CONFIG_URL."
fi

cat <<EOF

Done! The runner scale set '$RUNNER_SET' is registered with $GITHUB_CONFIG_URL.
It has no runners until a job asks for one.

  Run the sample workflow:  Actions tab > "Actions Runner Controller Demo" > Run workflow
                            (or: gh workflow run main.yml --repo ${GITHUB_CONFIG_URL#https://github.com/})
  Watch runners scale:      kubectl get pods --namespace arc-runners --watch
  Controller/listener:      kubectl get pods --namespace arc-systems
  Clean up:                 ./destroy.sh
EOF
