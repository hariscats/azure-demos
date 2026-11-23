#!/usr/bin/env bash
set -euo pipefail
mode=${1:-disk}
if (( $# > 1 )) || [[ ! $mode =~ ^(disk|fingerprint|preflight|elasticsearch)$ ]]; then
  echo "Usage: bash reproduce.sh [disk|fingerprint|preflight|elasticsearch]" >&2
  exit 2
fi
die() { echo "$*" >&2; exit 1; }
AZ_CLOUD=${AZ_CLOUD:-AzureCloud}
LOCATION=${LOCATION:-westus2}
VM_SIZE=${VM_SIZE:-Standard_D8as_v7}
OS_SKU=${OS_SKU:-Ubuntu}
FIPS=${FIPS:-false}
AKS_VERSION=${AKS_VERSION:-1.36.5}
TARGET_RA_KB=${TARGET_RA_KB:-128}
[[ $AZ_CLOUD == AzureCloud || $AZ_CLOUD == AzureUSGovernment ]] || die "Unsupported AZ_CLOUD: $AZ_CLOUD"
[[ $LOCATION =~ ^[a-z0-9]+$ ]] || die "LOCATION must be an Azure region name (e.g. westus2)."
[[ $AKS_VERSION =~ ^1\.(0|[1-9][0-9]?)\.[0-9]+$ ]] || die "AKS_VERSION must be an exact Kubernetes 1.x patch."
[[ $TARGET_RA_KB =~ ^[1-9][0-9]{0,8}$ ]] || die "TARGET_RA_KB must be a positive integer in KiB (up to nine digits)."

pool_names=(nodepool1)
pool_sizes=("$VM_SIZE")
pool_skus=("$OS_SKU")
pool_fips=("$FIPS")
if [[ -n ${CONTROL_POOLS:-} ]]; then
  [[ $mode != elasticsearch ]] || die "CONTROL_POOLS requires disk, fingerprint, or preflight mode."
  [[ $CONTROL_POOLS != ,* && $CONTROL_POOLS != *, && $CONTROL_POOLS != *,,* ]] || die "Empty CONTROL_POOLS entry."
  IFS=, read -r -a controls <<< "$CONTROL_POOLS"
  for control in "${controls[@]}"; do
    [[ $control =~ ^([a-z][a-z0-9]{0,11}):([^:]+):([^:]+):(true|false)$ ]] ||
      die "Invalid CONTROL_POOLS entry: $control (expected name:vmSize:osSku:fips)."
    pool=${BASH_REMATCH[1]}
    for existing in "${pool_names[@]}"; do
      [[ $existing != "$pool" ]] || die "Duplicate pool name: $pool"
    done
    pool_names+=("$pool")
    pool_sizes+=("${BASH_REMATCH[2]}")
    pool_skus+=("${BASH_REMATCH[3]}")
    pool_fips+=("${BASH_REMATCH[4]}")
  done
  [[ $CONTROL_POOLS != *$'\n'* ]] || die "CONTROL_POOLS must be a single line."
fi
minor=${AKS_VERSION#1.}; minor=${minor%%.*}
for index in "${!pool_names[@]}"; do
  pool=${pool_names[index]} vm=${pool_sizes[index]} sku=${pool_skus[index]} fips=${pool_fips[index]}
  [[ $vm =~ ^Standard_[A-Za-z0-9_]+$ ]] || die "$pool: invalid VM size: $vm"
  [[ $sku =~ ^(Ubuntu|Ubuntu2204|Ubuntu2404|AzureLinux)$ ]] || die "$pool: unsupported OS SKU: $sku"
  [[ $fips == true || $fips == false ]] || die "$pool: FIPS must be true or false."
  [[ $FIPS != true || $fips == true ]] || die "$pool: AKS requires FIPS on added pools when the default pool has FIPS."
  if [[ $fips == true ]]; then
    [[ $sku != Ubuntu2404 ]] || die "$pool: AKS does not currently offer FIPS with Ubuntu2404; use Ubuntu or Ubuntu2204."
    (( minor >= 19 )) || die "$pool: FIPS requires AKS 1.19 or later."
    if [[ $sku == AzureLinux ]] && (( minor < 32 )); then
      die "$pool: AzureLinux FIPS requires Azure Linux 3.0; use AKS 1.32 or later for this OS SKU."
    fi
  fi
done

tools=(az jq)
if [[ $mode != preflight ]]; then tools+=(kubectl); fi
if [[ $mode == elasticsearch ]]; then
  if [[ $AZ_CLOUD != AzureCloud || $LOCATION != westus2 || $VM_SIZE != Standard_D8as_v7 ||
        $OS_SKU != Ubuntu || $FIPS != false || $TARGET_RA_KB != 128 || -n ${DAEMONSET_YAML:-} ]]; then
    die "Legacy Elasticsearch replay uses the reference node configuration; use disk or fingerprint for feasibility."
  fi
  lab_path="$(dirname "$0")/../aks-readahead-lab"
  [[ -d $lab_path ]] || die "Elasticsearch benchmark inputs are missing; use disk or fingerprint for feasibility."
  lab_src="$(cd "$lab_path" && pwd)"
  inputs=(base.yaml hotplug.yaml posted.yaml observe.py workload.py mapping.json reclaim.yaml
          reclaim.py setup.sh bench.py resident.py summarize.py aggregate.py)
  for input in "${inputs[@]}"; do
    [[ -r "$lab_src/$input" ]] || { echo "Missing benchmark input: $lab_src/$input" >&2; exit 1; }
  done
  tools+=(python3)
elif [[ $mode == disk ]]; then
  tools+=(shasum)
  if [[ -z ${DAEMONSET_YAML:-} ]]; then tools+=(curl); fi
fi
for tool in "${tools[@]}"; do command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 1; }; done
umask 077
output_parent=${REPRO_OUTPUT_DIR:-${TMPDIR:-/tmp}}
mkdir -p "$output_parent"
WORK=$(mktemp -d "$(cd "$output_parent" && pwd)/aks-5743.XXXXXX")
mkdir "$WORK/debug"
exec > >(tee -a "$WORK/debug/run.log") 2>&1
stage() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
LAB="ra5743-$(date -u +%y%m%d%H%M%S)-$RANDOM"
RG="rg-$LAB"
NRG="$RG-nodes"
export KUBECONFIG="$WORK/kubeconfig"
original_cloud=$(az cloud show --query name -o tsv)
[[ -n $original_cloud ]] || die "Cannot determine the active Azure cloud."
verify_groups=false

cleanup() {
  status=$?
  trap - EXIT
  set +e
  if [[ $status != 0 && -s "$KUBECONFIG" ]]; then
    stage "Run failed (exit $status). Collecting diagnostics in $WORK/debug before cleanup."
    kubectl get pods,pvc -A -o wide --request-timeout=15s > "$WORK/debug/pods-and-volumes.txt" 2>&1
    kubectl get events -A --sort-by=.lastTimestamp --request-timeout=15s > "$WORK/debug/events.txt" 2>&1
    if [[ $mode == elasticsearch ]]; then
      kubectl logs es -c elasticsearch --tail=200 --request-timeout=15s > "$WORK/debug/elasticsearch.log" 2>&1
      kubectl exec --request-timeout=15s es -c client -- sh -c '
        if test -f /tmp/ingest.log; then cat /tmp/ingest.log; fi
        for f in /tmp/*.jsonl.err; do
          if test -s "$f"; then echo "$f"; tail -30 "$f"; fi
        done' > "$WORK/debug/client.log" 2>&1
    fi
  fi
  if [[ $mode == disk && -s "$KUBECONFIG" && ! -s "$WORK/queues.log" ]]; then
    kubectl logs original --timestamps --request-timeout=15s > "$WORK/queues.log" 2>/dev/null
  fi
  if [[ $status != 0 && -n ${disk_output:-} && $disk_output != "$WORK" && ! -s "$disk_output/queues.log" ]]; then
    disk_kube logs original --timestamps --request-timeout=15s > "$disk_output/queues.log" 2>/dev/null
  fi
  if [[ $verify_groups == true ]]; then
    if [[ $(az cloud show --query name -o tsv) != "$AZ_CLOUD" ]]; then
      stage "Active cloud changed; refusing cleanup in the wrong cloud. Check $RG and $NRG in $AZ_CLOUD."
      status=1
    else
      stage "Cleaning up $RG in $AZ_CLOUD"
      if [[ $(az group show --subscription "$SUB" -n "$RG" --query tags.experiment -o tsv 2>/dev/null) == "$LAB" ]]; then
        az group delete --subscription "$SUB" -n "$RG" --yes || status=1
      fi
      for group in "$RG" "$NRG"; do
        exists=$(az group exists --subscription "$SUB" -n "$group" -o tsv) || status=1
        echo "$group exists: $exists"
        [[ $exists == false ]] || status=1
      done
    fi
  fi
  az cloud set --name "$original_cloud" || { echo "Could not restore Azure cloud: $original_cloud" >&2; status=1; }
  if [[ $status == 0 ]]; then rm -f "$KUBECONFIG"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
az cloud set --name "$AZ_CLOUD"
SUB=$(az account show --query id -o tsv) || die "Sign in to $AZ_CLOUD and select an authorized test subscription."
[[ -n $SUB ]] || die "No active subscription in $AZ_CLOUD."
az account show --subscription "$SUB" --query name -o tsv
echo "Cloud: $AZ_CLOUD    Region: $LOCATION    Local files: $WORK"

stage "Checking AKS $AKS_VERSION and requested VM sizes before provisioning"
versions=$(az aks get-versions --subscription "$SUB" --location "$LOCATION" -o json) ||
  die "Could not list AKS versions in $AZ_CLOUD/$LOCATION."
jq -e --arg version "$AKS_VERSION" '
  any(.values[]? | select(.isPreview != true); (.patchVersions // {}) | has($version)) or
  any(.orchestrators[]? | select(.isPreview != true); .orchestratorVersion == $version)
' <<< "$versions" >/dev/null ||
  die "AKS $AKS_VERSION is not listed for $AZ_CLOUD/$LOCATION on this subscription. Choose a patch with az aks get-versions -l $LOCATION -o table."
for index in "${!pool_names[@]}"; do
  pool=${pool_names[index]} vm=${pool_sizes[index]} sku=${pool_skus[index]} fips=${pool_fips[index]}
  skus=$(az vm list-skus --subscription "$SUB" --location "$LOCATION" --resource-type virtualMachines --size "$vm" -o json) ||
    die "$pool: could not check $vm in $AZ_CLOUD/$LOCATION."
  jq -e --arg vm "$vm" 'any(.[]; .name == $vm and all(.restrictions[]?; .type != "Location"))' \
    <<< "$skus" >/dev/null || die "$pool: VM size $vm is unavailable or restricted in $AZ_CLOUD/$LOCATION."
  echo "$pool: $vm listed; requested OS SKU=$sku, FIPS=$fips passes documented compatibility checks."
done
stage "Catalog preflight passed. Regional node image availability, quota, and capacity are confirmed only by provisioning."
if [[ $mode == preflight ]]; then exit 0; fi

if [[ $mode == disk ]]; then
  if [[ -n ${DAEMONSET_YAML:-} ]]; then
    [[ -f $DAEMONSET_YAML && -r $DAEMONSET_YAML ]] || die "Cannot read DAEMONSET_YAML: $DAEMONSET_YAML"
    cp -- "$DAEMONSET_YAML" "$WORK/posted.yaml"
  else
    curl -fsSL https://api.github.com/repos/Azure/AKS/issues/comments/6265013208 |
      jq -berj '.body | capture("```\n(?<yaml>[\\s\\S]*?)```").yaml' > "$WORK/posted.yaml"
  fi
  echo "905ddd3ef8f8df2f96263709dfb921f34126972ce560612e16a1f3b9789914f0  $WORK/posted.yaml" |
    shasum -a 256 -c -
fi

echo "Lab: $RG    Node group: $NRG"
for group in "$RG" "$NRG"; do
  if ! exists=$(az group exists --subscription "$SUB" -n "$group" -o tsv) || [[ $exists != false ]]; then
    die "Cannot confirm $group is unused in $AZ_CLOUD. No resources created."
  fi
done
verify_groups=true
stage "Provisioning the disposable AKS cluster"
fips_flags=()
if [[ $FIPS == true ]]; then fips_flags+=(--enable-fips-image); fi
az group create --subscription "$SUB" -n "$RG" -l "$LOCATION" --tags experiment="$LAB" -o none
az aks create --subscription "$SUB" -g "$RG" -n "$LAB" --node-resource-group "$NRG" \
  --location "$LOCATION" --nodepool-name "${pool_names[0]}" --if-none-match '*' --tags experiment="$LAB" \
  --node-count 1 --node-vm-size "$VM_SIZE" --node-osdisk-type Managed \
  --node-osdisk-size 64 --os-sku "$OS_SKU" --kubernetes-version "$AKS_VERSION" "${fips_flags[@]}" \
  --network-plugin azure --network-plugin-mode overlay --no-ssh-key --tier free -o none ||
  die "AKS could not provision $VM_SIZE/$OS_SKU/FIPS=$FIPS in $AZ_CLOUD/$LOCATION; see the Azure error above."
for ((index=1; index<${#pool_names[@]}; index++)); do
  pool=${pool_names[index]} vm=${pool_sizes[index]} sku=${pool_skus[index]} fips=${pool_fips[index]}
  fips_flags=()
  if [[ $fips == true ]]; then fips_flags+=(--enable-fips-image); fi
  stage "Provisioning control pool $pool"
  az aks nodepool add --subscription "$SUB" -g "$RG" --cluster-name "$LAB" -n "$pool" \
    --node-count 1 --node-vm-size "$vm" --node-osdisk-type Managed --node-osdisk-size 64 \
    --os-sku "$sku" --kubernetes-version "$AKS_VERSION" "${fips_flags[@]}" --mode User -o none ||
    die "AKS could not provision $pool ($vm/$sku/FIPS=$fips) in $AZ_CLOUD/$LOCATION; see the Azure error above."
done
az aks get-credentials --subscription "$SUB" -g "$RG" -n "$LAB" -f "$KUBECONFIG"
kubectl wait --for=condition=Ready nodes --all --timeout=5m
kubectl get nodes -o wide -L kubernetes.azure.com/node-image-version

if [[ $mode == elasticsearch ]]; then
  mkdir "$WORK/search"; cd "$WORK/search"; mkdir raw
  for input in "${inputs[@]}"; do cp "$lab_src/$input" .; done
  printf '#!/bin/sh\nexec kubectl "$@"\n' > kube.sh; chmod +x kube.sh
  bash setup.sh
  kubectl wait --for=condition=Ready pod/es pod/observer pod/cache-control --timeout=10m
  kubectl exec es -c client -- python -c '
import time, urllib.request
for i in range(120):
    try:
        urllib.request.urlopen("http://127.0.0.1:9200", timeout=2).close()
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit("Elasticsearch did not become ready")
'
  kubectl exec es -c elasticsearch -- awk '$5=="/usr/share/elasticsearch/data"' /proc/self/mountinfo
  kubectl logs observer --tail=1 > "$WORK/debug/initial-queues.json"
  stage "Indexing 2,000,000 GeoNames documents"
  # Keep indexing in the pod if the long-lived kubectl output stream disconnects.
  kubectl exec es -c client -- sh -c '
    (python -u /scripts/workload.py ingest > /tmp/ingest.log 2>&1
     echo "$?" > /tmp/ingest.status) </dev/null >/dev/null 2>&1 &'
  deadline=$((SECONDS + 1800))
  last_line=''
  while :; do
    if (( SECONDS > deadline )); then echo "Indexing timed out" >&2; exit 1; fi
    if progress=$(kubectl exec --request-timeout=15s es -c client -- sh -c '
      if test -s /tmp/ingest.status; then printf "done "; cat /tmp/ingest.status
      elif test -s /tmp/ingest.log; then tail -1 /tmp/ingest.log; fi'); then
      if [[ $progress == "done "* ]]; then break; fi
      if [[ -n "$progress" && $progress != "$last_line" ]]; then stage "Ingest: $progress"; fi
      last_line=$progress
    fi
    sleep 5
  done
  kubectl exec es -c client -- cat /tmp/ingest.log > raw/ingest.log
  [[ $progress == "done 0" ]] || { cat raw/ingest.log >&2; exit 1; }
  stage "Ingest completed. Starting the cold and warm search comparisons."
  python3 -u bench.py
  stage "Starting the fully resident control"
  python3 -u resident.py
  kubectl logs observer > raw/samples.jsonl
  python3 summarize.py
  python3 aggregate.py
  cat pooled.csv
  python3 - <<'CHECK'
import csv
from pathlib import Path

with Path('benchmark.csv').open() as f:
    rows = list(csv.DictReader(f))
if len(rows) != 39:
    raise SystemExit(f'Expected 39 benchmark passes, found {len(rows)}')
for row in rows:
    label = row['label']
    expected = '65536' if '-high-' in label else '128'
    if (row['ra_min'], row['ra_max']) != (expected, expected) or int(row['samples']) == 0:
        raise SystemExit(f'{label}: expected sampled readahead of {expected} KiB, '
                         f'found min={row["ra_min"]}, max={row["ra_max"]}, samples={row["samples"]}')
    if int(row['scheduled']) != 96 or int(row['n']) + int(row['errors']) != 96:
        raise SystemExit(f'{label}: missing client results')
measured = [row for row in rows if row['label'].split('-')[-1] in ('cold', 'warm', 'repeat')]
errors = sum(int(row['errors']) for row in measured)
completed = sum(int(row['n']) for row in measured)
print(f'Verified {len(rows)} passes at their intended sampled readahead. '
      f'{len(measured)} measured passes, {completed} successful requests, {errors} errors/timeouts.')
CHECK
  exit 0
fi

disk_kube() { kubectl --namespace "$disk_namespace" "$@"; }
disk() {
  disk_kube apply -f - <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: $1}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: managed-csi-premium
  resources: {requests: {storage: 8Gi}}
---
apiVersion: v1
kind: Pod
metadata: {name: $1}
spec:
  automountServiceAccountToken: false
  terminationGracePeriodSeconds: 1
  nodeSelector:
    kubernetes.azure.com/agentpool: $pool
  hostPID: $2
  containers:
  - name: observer
    image: busybox:1.36.1
    securityContext: {privileged: $2}
    command: [sh, -c]
    args:
    - |
      while :; do
        for f in /sys/block/nvme*/queue/read_ahead_kb /sys/block/sd*/queue/read_ahead_kb; do
          [ -r "\$f" ] || continue
          d=\${f%/queue/*}
          printf '%s=%s ' "\${d##*/}" "\$(cat "\$f")"
        done
        echo
        sleep 1
      done
    volumeMounts: [{name: disk, mountPath: /data}]
  volumes: [{name: disk, persistentVolumeClaim: {claimName: $1}}]
YAML
  disk_kube wait --for=condition=Ready "pod/$1" --timeout=5m
}

fingerprint_node() {
  local node_name node_json
  node_name=$(disk_kube get pod original -o jsonpath='{.spec.nodeName}')
  node_json=$(kubectl get node "$node_name" -o json)
  jq -e --arg pool "$pool" --arg vm "$vm" '
    .metadata.labels["kubernetes.azure.com/agentpool"] == $pool and
    .metadata.labels["node.kubernetes.io/instance-type"] == $vm
  ' <<< "$node_json" >/dev/null || die "Unexpected pool or VM size for $node_name."
  disk_kube exec -i original -- sh -s -- "$DEV" <<'PROBE' |
set -eu
block_name() {
  name=${1##*/}
  if [ -f "/sys/class/block/$name/partition" ]; then
    parent=$(readlink -f "/sys/class/block/$name")
    parent=${parent%/*}
    name=${parent##*/}
  fi
  printf '%s' "$name"
}
fips=$(cat /proc/sys/crypto/fips_enabled 2>/dev/null || true)
printf 'fips\t%s\n' "$fips"
root_mm=$(awk '$5=="/" {print $3; exit}' /proc/1/mountinfo)
root_device=$(readlink -f "/sys/dev/block/$root_mm" || true)
os_disk=$(block_name "$root_device")
pvc_disk=$(block_name "$1")
printf 'pvc\t%s\n' "$pvc_disk"
azure_devices=/proc/1/root/dev/disk/azure
kvp=/proc/1/root/var/lib/hyperv/.kvp_pool_0
if [ -r "$kvp" ]; then
  records=$(($(wc -c < "$kvp") / 2560))
  record=0
  while [ "$record" -lt "$records" ]; do
    key=$(dd if="$kvp" bs=2560 skip="$record" count=1 2>/dev/null |
      dd bs=512 count=1 2>/dev/null | tr -d '\000')
    case "$key" in
      HostOSBuildNumber|HostOSMajorVersion|HostOSMinorVersion|HostOSVersion)
        value=$(dd if="$kvp" bs=2560 skip="$record" count=1 2>/dev/null |
          dd bs=512 skip=1 count=4 2>/dev/null | tr -d '\000\t\r\n')
        if [ -n "$value" ]; then printf 'host\t%s\t%s\n' "$key" "$value"; fi ;;
    esac
    record=$((record + 1))
  done
fi
for device in /sys/block/*; do
  [ -e "$device/device" ] || continue
  disk_name=${device##*/}
  model=$(cat "$device/device/model" 2>/dev/null || true)
  protocol=other
  controller=unknown
  case "$disk_name" in
    nvme*n*)
      protocol=NVMe
      nvme_controller=/sys/class/nvme/${disk_name%n*}
      [ -n "$model" ] || model=$(cat "$nvme_controller/model" 2>/dev/null || true)
      controller=$(cat "$nvme_controller/transport" 2>/dev/null || true) ;;
    sd*|sr*)
      protocol=SCSI
      host=$(readlink -f "$device/device")
      host=${host#*/host}; host=${host%%/*}
      controller=$(cat "/sys/class/scsi_host/host$host/proc_name" 2>/dev/null || true) ;;
  esac
  role=unknown
  for link in "$azure_devices"/root "$azure_devices"/os "$azure_devices"/resource \
      "$azure_devices"/local/by-index/* "$azure_devices"/local/by-serial/* \
      "$azure_devices"/scsi1/lun* "$azure_devices"/data/by-lun/*; do
    [ -L "$link" ] || continue
    [ "$(block_name "$(readlink "$link")")" = "$disk_name" ] || continue
    case "$link" in
      */root|*/os) role=os; break ;;
      */resource|*/local/*) role=local; break ;;
      *) role=data ;;
    esac
  done
  case "$model" in
    *NVMe*Direct*Disk*) [ "$role" != unknown ] || role=local ;;
  esac
  if [ "$disk_name" = "$os_disk" ]; then role=os; fi
  if [ "$disk_name" = "$pvc_disk" ]; then role=data; fi
  optimal=$(cat "$device/queue/optimal_io_size" 2>/dev/null || true)
  readahead=$(cat "$device/queue/read_ahead_kb" 2>/dev/null || true)
  printf 'disk\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$disk_name" \
    "$(printf '%s' "$model" | tr -d '\t\r\n')" "$protocol" "${controller:-unknown}" "$role" "$optimal" "$readahead"
done
PROBE
    jq -Rn --argjson node "$node_json" --arg pool "$pool" --arg sku "$sku" \
  --argjson fips "$fips" '
      def number: if test("^[0-9]+$") then tonumber else null end;
      [inputs | split("\t")] as $rows |
      ($rows | map(select(.[0] == "host") | {key: .[1], value: .[2]}) | from_entries) as $kvp |
      {
        node: $node.metadata.name, pool: $pool, requested_os_sku: $sku, requested_fips: $fips,
        os_image: $node.status.nodeInfo.osImage, kernel_version: $node.status.nodeInfo.kernelVersion,
        node_image_version: $node.metadata.labels["kubernetes.azure.com/node-image-version"],
        vm_size: $node.metadata.labels["node.kubernetes.io/instance-type"],
        fips_enabled: ($rows[] | select(.[0] == "fips") | (.[1] // "") | number),
        host_build: ($kvp.HostOSBuildNumber // $kvp.HostOSVersion // "not visible from guest"),
        host_os_kvp: $kvp, original_pvc_device: ($rows[] | select(.[0] == "pvc") | .[1]),
        block_devices: [$rows[] | select(.[0] == "disk") |
          {name: .[1], model: .[2], protocol: .[3], controller_type: (.[3] + "/" + .[4]), role: .[5],
           optimal_io_size: ((.[6] // "") | number), read_ahead_kb: ((.[7] // "") | number)} |
          . + {host_fix_verdict: (if .protocol != "NVMe" or (.role != "os" and .role != "data") then null
            elif .optimal_io_size == 33554432 then "HOST_FIX_ABSENT"
            elif .optimal_io_size == 262144 then "HOST_FIX_PRESENT"
            else "OTHER" end)}]
      }
    '
}

seed() { disk_kube exec original -- sh -ec 'printf "%s\n" "$2" > "$1/queue/read_ahead_kb"' sh "$DEV" "$TARGET_RA_KB"; }
show() { disk_kube logs original --tail=3 --timestamps; }
detach() {
  disk_kube delete pod hotplug
  disk_kube exec original -- sh -ec '
    for i in $(seq 1 180); do
      [ -e "/sys/dev/block/$1" ] || exit 0
      sleep 1
    done
    echo "Timed out waiting for physical detach" >&2; exit 1
  ' sh "$HOT_MM"
}
wait_low() {
  disk_kube exec original -- sh -ec '
    for i in $(seq 1 150); do
      [ "$(cat "$1/queue/read_ahead_kb")" = "$2" ] && exit 0
      sleep 1
    done
    echo "Original PVC did not reach $2 KiB" >&2; exit 1
  ' sh "$DEV" "$TARGET_RA_KB"
}
test_queue_resets() {
  local natural_ra=$1 ds_patch delay
  echo "Untreated attach"
  seed; sleep 2; show
  disk hotplug false
  HOT_MM=$(disk_kube exec hotplug -- awk '$5=="/data" {print $3}' /proc/self/mountinfo)
  sleep 2; show
  echo "Untreated detach"
  seed; sleep 2; show
  detach
  sleep 2; show

  if (( natural_ra >= TARGET_RA_KB )); then
    echo "Attach and detach with the published DaemonSet"
    ds_patch=$(jq -nc --arg pool "$pool" --arg target "$TARGET_RA_KB" '
      {spec: {template: {spec: {nodeSelector: {"kubernetes.azure.com/agentpool": $pool},
        containers: [{name: "readahead", env: [{name: "READ_AHEAD_KB", value: $target}]}]}}}}
    ')
    disk_kube patch --local --type=strategic -f "$WORK/posted.yaml" -p "$ds_patch" -o json |
      disk_kube apply -f -
    disk_kube rollout status ds/reduce-block-readahead --timeout=3m
    wait_low
    # Shift the attach requests within the polling cycle. The observer records the actual device times.
    for delay in 4 32 5; do
      sleep "$delay"
      disk hotplug false
      HOT_MM=$(disk_kube exec hotplug -- awk '$5=="/data" {print $3}' /proc/self/mountinfo)
      if [[ $delay == 5 ]]; then
        disk_kube logs ds/reduce-block-readahead --timestamps > "$disk_output/daemonset-before-replacement.log"
        disk_kube delete pod -l app=block-readahead
        disk_kube rollout status ds/reduce-block-readahead --timeout=3m
      fi
      wait_low
      detach
      wait_low
    done
    sleep 2
    disk_kube logs ds/reduce-block-readahead --timestamps > "$disk_output/daemonset.log"
  else
    echo "Skipping DaemonSet cycles: it only lowers readahead, and the natural $natural_ra KiB is below $TARGET_RA_KB KiB."
  fi
  disk_kube logs original --timestamps > "$disk_output/queues.log"
  echo "Observed queue changes for $pool (UTC, KiB)"
  awk '{$1=$1; state=substr($0,index($0," ")+1); if (state!=last) print; last=state}' "$disk_output/queues.log"
}

jq -n --arg cloud "$AZ_CLOUD" --arg location "$LOCATION" --arg version "$AKS_VERSION" \
  '{cloud: $cloud, location: $location, aks_version: $version, nodes: []}' > "$WORK/fingerprint.json"
for index in "${!pool_names[@]}"; do
  pool=${pool_names[index]} vm=${pool_sizes[index]} sku=${pool_skus[index]} fips=${pool_fips[index]}
  disk_namespace=default
  disk_output=$WORK
  if (( index > 0 )); then
    disk_namespace="repro-$pool"
    disk_output="$WORK/pools/$pool"
    mkdir -p "$disk_output"
    kubectl create namespace "$disk_namespace"
  fi
  stage "Sampling natural queue settings on $pool"
  disk original true
  MM=$(disk_kube exec original -- awk '$5=="/data" {print $3; exit}' /proc/self/mountinfo)
  [[ $MM =~ ^[0-9]+:[0-9]+$ ]] || die "$pool: could not identify the original PVC device."
  DEV=$(disk_kube exec original -- readlink -f "/sys/dev/block/$MM")
  echo "original PVC -> /data -> $MM -> $DEV"
  sample=$(fingerprint_node)
  jq --argjson sample "$sample" '.nodes += [$sample]' "$WORK/fingerprint.json" > "$WORK/fingerprint.tmp"
  mv "$WORK/fingerprint.tmp" "$WORK/fingerprint.json"
  jq -r '. | ["POOL", "NODE", "VM", "IMAGE", "OS", "KERNEL", "FIPS", "HOST BUILD"],
    [.pool, .node, .vm_size, .node_image_version, .os_image, .kernel_version, (.fips_enabled // "unreadable"), .host_build],
    ["DEVICE", "ROLE", "MODEL", "CONTROLLER", "IO OPT (B)", "READAHEAD (KiB)", "HOST FIX"],
    (.block_devices[] | [.name, .role, .model, .controller_type, .optimal_io_size, .read_ahead_kb, .host_fix_verdict])
    | map(. // "-") | join(" | ")' <<< "$sample"
  if [[ $fips == true ]]; then
    jq -e '.fips_enabled == 1' <<< "$sample" >/dev/null || die "$pool: requested FIPS but /proc/sys/crypto/fips_enabled did not report 1."
  fi
  natural_ra=$(jq -er '.original_pvc_device as $pvc | .block_devices[] | select(.name == $pvc) | .read_ahead_kb' <<< "$sample") ||
    die "$pool: natural readahead was not captured for the original PVC."
  echo "$pool: original PVC natural readahead is $natural_ra KiB"
  if [[ $mode == disk ]]; then
    disk_kube logs original --tail=1 --timestamps
    test_queue_resets "$natural_ra"
  fi
done
echo "Fingerprint: $WORK/fingerprint.json"
