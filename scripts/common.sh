#!/usr/bin/env bash
# Shared helpers for the demo deploy.sh / destroy.sh scripts.
#
# Every demo deploys into its own resource group (default: rg-<demo-folder>)
# that is tagged "azure-demos=<demo-folder>". destroy.sh only deletes resource
# groups that carry that tag, so it never removes something it didn't create.
#
# Usage from a demo script:
#   DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$DEMO_DIR/../scripts/common.sh"
#   init_demo "$@"

# shellcheck disable=SC2034 # Variables set here are used by the sourcing scripts.

TAG_KEY="azure-demos"
NL=$'\n'

if [[ -t 2 ]]; then
  _c_info=$'\033[1;34m' _c_warn=$'\033[1;33m' _c_err=$'\033[1;31m' _c_off=$'\033[0m'
else
  _c_info='' _c_warn='' _c_err='' _c_off=''
fi

info() { printf '%s==>%s %s\n' "$_c_info" "$_c_off" "$*" >&2; }
warn() { printf '%sWARNING:%s %s\n' "$_c_warn" "$_c_off" "$*" >&2; }
die() {
  printf '%sERROR:%s %s\n' "$_c_err" "$_c_off" "$*" >&2
  exit 1
}

# Prints the comment block at the top of the running script (after the shebang).
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

_on_exit() {
  local status=$?
  if [[ $status -ne 0 && "$(basename "$0")" == "deploy.sh" ]]; then
    warn "Deployment did not finish. It's safe to re-run ./deploy.sh, or remove everything with ./destroy.sh."
  fi
}

# Usage: init_demo "$@"
# Parses the common flags and sets DEMO, RESOURCE_GROUP, LOCATION and ASSUME_YES.
init_demo() {
  [[ -n "${DEMO_DIR:-}" ]] || die "DEMO_DIR must be set before calling init_demo."
  ASSUME_YES="${ASSUME_YES:-0}"
  local arg
  for arg in "$@"; do
    case "$arg" in
      -y | --yes) ASSUME_YES=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown argument: $arg"
        ;;
    esac
  done

  DEMO="$(basename "$DEMO_DIR")"
  RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${DEMO}}"
  LOCATION_OVERRIDE="${LOCATION:-}"
  LOCATION="${LOCATION:-eastus}"
  trap _on_exit EXIT
}

# Usage: require_tools az kubectl ...
require_tools() {
  local tool missing=""
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
  done
  [[ -z "$missing" ]] ||
    die "Missing required tool(s):$missing. Install them (or use Azure Cloud Shell, which has them all) and re-run."
}

require_az_login() {
  local account
  account="$(az account show --query "[name, id]" --output tsv 2>/dev/null)" ||
    die "The Azure CLI isn't signed in. Run 'az login' (and 'az account set --subscription <id>' if needed) first."
  info "Subscription:   ${account%%"$NL"*} (${account##*"$NL"})"
  info "Resource group: $RESOURCE_GROUP"
}

# Usage: register_providers Microsoft.ContainerService Microsoft.KeyVault ...
# Registers resource providers that aren't registered yet (needed once per subscription).
register_providers() {
  local registered ns
  registered="$(az provider list --query "[?registrationState=='Registered'].namespace" --output tsv)"
  for ns in "$@"; do
    if ! grep -qix "$ns" <<<"$registered"; then
      info "Registering resource provider $ns (one-time per subscription, can take a few minutes)..."
      az provider register --namespace "$ns" --wait --output none
    fi
  done
}

# Creates the demo resource group (tagged azure-demos=<demo>) if it doesn't exist.
# When re-deploying into an existing group, its region is reused unless LOCATION is set.
ensure_resource_group() {
  local existing
  existing="$(az group show --name "$RESOURCE_GROUP" --query location --output tsv 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    [[ -n "$LOCATION_OVERRIDE" ]] || LOCATION="$existing"
    info "Using existing resource group '$RESOURCE_GROUP' ($existing)."
  else
    info "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" \
      --tags "$TAG_KEY=$DEMO" --output none
  fi
}

# Usage: deploy_bicep [name=value ...]
# Deploys <demo>/infra/main.bicep into the resource group. `location` is always passed.
deploy_bicep() {
  info "Deploying infra/main.bicep to '$LOCATION' (this can take 5-10 minutes)..."
  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEMO" \
    --template-file "$DEMO_DIR/infra/main.bicep" \
    --parameters location="$LOCATION" "$@" \
    --output none
}

# Usage: read_outputs VAR=outputName [VAR=outputName ...]
# Reads outputs of the deploy_bicep deployment into shell variables.
read_outputs() {
  local pair query="" values line
  for pair in "$@"; do
    query="${query:+$query, }properties.outputs.${pair#*=}.value"
  done
  values="$(az deployment group show --resource-group "$RESOURCE_GROUP" --name "$DEMO" \
    --query "[$query]" --output tsv)" ||
    die "Couldn't read the outputs of deployment '$DEMO' in '$RESOURCE_GROUP'."
  for pair in "$@"; do
    line="${values%%"$NL"*}"
    if [[ "$values" == *"$NL"* ]]; then values="${values#*"$NL"}"; else values=""; fi
    [[ -n "$line" && "$line" != "None" ]] || die "Deployment output '${pair#*=}' is empty."
    printf -v "${pair%%=*}" '%s' "$line"
  done
}

# Usage: render_template FILE VAR [VAR ...]
# Prints FILE with every ${VAR} placeholder replaced by the value of the shell variable VAR.
render_template() {
  local file="$1" content scan var placeholder rendered re='[$][{][A-Za-z_][A-Za-z0-9_]*[}]'
  shift
  content="$(<"$file")"
  scan="$content"
  while [[ $scan =~ $re ]]; do
    placeholder="${BASH_REMATCH[0]}"
    var="${placeholder:2:${#placeholder}-3}"
    case " $* " in
      *" $var "*) ;;
      *) die "$file uses \${$var}, but no value was provided for it." ;;
    esac
    scan="${scan#*"$placeholder"}"
  done
  for var in "$@"; do
    placeholder="\${$var}"
    rendered=""
    while [[ "$content" == *"$placeholder"* ]]; do
      rendered="$rendered${content%%"$placeholder"*}${!var}"
      content="${content#*"$placeholder"}"
    done
    content="$rendered$content"
  done
  printf '%s\n' "$content"
}

# Usage: build_image ACR_NAME LOGIN_SERVER IMAGE:TAG CONTEXT_DIR
# Builds and pushes the image with ACR Tasks, falling back to local Docker when
# ACR Tasks isn't available (it's disabled on some subscription types, such as free trials).
build_image() {
  local acr="$1" server="$2" image="$3" context="$4"
  info "Building image '$image' with ACR Tasks in registry '$acr'..."
  if az acr build --registry "$acr" --image "$image" --platform linux/amd64 \
    --output none "$context"; then
    return 0
  fi
  warn "az acr build failed."
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    info "Falling back to a local Docker build and push..."
    az acr login --name "$acr" --output none
    docker build --platform linux/amd64 --tag "$server/$image" "$context"
    docker push "$server/$image"
  else
    die "Couldn't build '$image'. If ACR Tasks isn't available in your subscription, start Docker locally and re-run."
  fi
}

# Usage: aks_get_credentials CLUSTER_NAME
# Merges the cluster into your kubeconfig and makes it the current kubectl context.
aks_get_credentials() {
  info "Getting kubectl credentials for AKS cluster '$1'..."
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$1" \
    --overwrite-existing --output none
}

# Usage: retry ATTEMPTS DELAY_SECONDS command [args...]
retry() {
  local attempts="$1" delay="$2" i=1
  shift 2
  until "$@"; do
    ((i < attempts)) || return 1
    sleep "$delay"
    i=$((i + 1))
  done
}

# Usage: confirm "Question?"  (returns 0 for yes; --yes or ASSUME_YES=1 skips the prompt)
confirm() {
  local reply
  [[ "$ASSUME_YES" == "1" || "$ASSUME_YES" == "true" ]] && return 0
  [[ -t 0 ]] || die "No terminal available to confirm. Re-run with --yes to continue."
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Returns 1 when the resource group doesn't exist, exits when it wasn't created by
# this demo (missing tag), and otherwise asks for confirmation.
confirm_destroy() {
  local tag
  if [[ "$(az group exists --name "$RESOURCE_GROUP" --output tsv)" != "true" ]]; then
    info "Resource group '$RESOURCE_GROUP' doesn't exist. Nothing to delete."
    return 1
  fi
  tag="$(az group show --name "$RESOURCE_GROUP" --query "tags.\"$TAG_KEY\"" --output tsv)"
  if [[ "$tag" != "$DEMO" ]]; then
    die "Resource group '$RESOURCE_GROUP' isn't tagged '$TAG_KEY=$DEMO', so this demo didn't create it. Refusing to delete it."
  fi
  confirm "Delete resource group '$RESOURCE_GROUP' and everything in it?" || die "Cancelled."
}

# Deletes the resource group, purges soft-deleted Key Vaults and Azure OpenAI
# (Cognitive Services) accounts so a re-deploy can reuse their names, and removes
# the kubectl contexts of the deleted AKS clusters.
destroy_resource_group() {
  local clusters vaults accounts name loc
  clusters="$(az aks list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)"
  vaults="$(az keyvault list --resource-group "$RESOURCE_GROUP" --resource-type vault \
    --query "[].name" --output tsv)"
  accounts="$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" \
    --query "[].[name, location]" --output tsv)"

  info "Deleting resource group '$RESOURCE_GROUP' (this usually takes 5-15 minutes)..."
  az group delete --name "$RESOURCE_GROUP" --yes --output none

  for name in $vaults; do
    info "Purging soft-deleted Key Vault '$name'..."
    az keyvault purge --name "$name" --output none || warn "Couldn't purge Key Vault '$name'."
  done
  while IFS=$'\t' read -r name loc; do
    [[ -n "$name" ]] || continue
    info "Purging soft-deleted Azure AI account '$name'..."
    az cognitiveservices account purge --name "$name" --resource-group "$RESOURCE_GROUP" \
      --location "$loc" --output none || warn "Couldn't purge account '$name'."
  done <<<"$accounts"
  for name in $clusters; do
    remove_kube_context "$name"
  done
  info "Deleted resource group '$RESOURCE_GROUP'."
}

# Usage: remove_kube_context CLUSTER_NAME
# Removes the context, cluster and user entries that `az aks get-credentials` added.
remove_kube_context() {
  local cluster="$1"
  command -v kubectl >/dev/null 2>&1 || return 0
  kubectl config get-contexts "$cluster" >/dev/null 2>&1 || return 0
  if [[ "$(kubectl config current-context 2>/dev/null || true)" == "$cluster" ]]; then
    kubectl config unset current-context >/dev/null
  fi
  kubectl config delete-context "$cluster" >/dev/null 2>&1 || true
  kubectl config delete-cluster "$cluster" >/dev/null 2>&1 || true
  kubectl config delete-user "clusterUser_${RESOURCE_GROUP}_${cluster}" >/dev/null 2>&1 || true
  info "Removed kubectl context '$cluster'."
}
