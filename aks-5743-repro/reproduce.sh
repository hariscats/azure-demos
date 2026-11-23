#!/usr/bin/env bash
set -euo pipefail
if (( $# > 1 )) || [[ ${1:-disk} != disk && ${1:-disk} != elasticsearch ]]; then
  echo "Usage: bash reproduce.sh [disk|elasticsearch]" >&2
  exit 2
fi
mode=${1:-disk}
tools=(az kubectl)
if [[ $mode == elasticsearch ]]; then
  lab_src="$(cd "$(dirname "$0")/../aks-readahead-lab" && pwd)"
  inputs=(base.yaml hotplug.yaml posted.yaml observe.py workload.py mapping.json reclaim.yaml
          reclaim.py setup.sh bench.py resident.py summarize.py aggregate.py)
  for input in "${inputs[@]}"; do
    [[ -r "$lab_src/$input" ]] || { echo "Missing benchmark input: $lab_src/$input" >&2; exit 1; }
  done
  tools+=(python3)
else
  tools+=(curl jq shasum)
fi
for tool in "${tools[@]}"; do command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 1; }; done
umask 077
SUB=$(az account show --query id -o tsv)
az account show --query name -o tsv
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
echo "Lab: $RG    Node group: $NRG    Local files: $WORK"

if [[ $(az group exists --subscription "$SUB" -n "$RG") != false ||
      $(az group exists --subscription "$SUB" -n "$NRG") != false ]]; then
  echo "Resource group name already in use. Rerun for a fresh name." >&2
  exit 1
fi

cleanup() {
  status=$?
  trap - EXIT
  set +e
  if [[ $status != 0 && -s "$KUBECONFIG" ]]; then
    stage "Run failed (exit $status). Collecting diagnostics in $WORK/debug before cleanup."
    kubectl get pods,pvc -o wide --request-timeout=15s > "$WORK/debug/pods-and-volumes.txt" 2>&1
    kubectl get events --sort-by=.lastTimestamp --request-timeout=15s > "$WORK/debug/events.txt" 2>&1
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
  stage "Cleaning up $RG"
  if [[ $(az group show --subscription "$SUB" -n "$RG" --query tags.experiment -o tsv 2>/dev/null) == "$LAB" ]]; then
    az group delete --subscription "$SUB" -n "$RG" --yes || status=1
  fi
  for g in "$RG" "$NRG"; do
    exists=$(az group exists --subscription "$SUB" -n "$g") || status=1
    echo "$g exists: $exists"
    [[ "$exists" == false ]] || status=1
  done
  if [[ $status == 0 ]]; then rm -f "$KUBECONFIG"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
stage "Provisioning the disposable AKS cluster"
az group create --subscription "$SUB" -n "$RG" -l westus2 --tags experiment="$LAB" -o none
az aks create --subscription "$SUB" -g "$RG" -n "$LAB" --node-resource-group "$NRG" \
  --node-count 1 --node-vm-size Standard_D8as_v7 --node-osdisk-type Managed \
  --node-osdisk-size 64 --os-sku Ubuntu --kubernetes-version "${AKS_VERSION:-1.36.5}" \
  --network-plugin azure --network-plugin-mode overlay --no-ssh-key --tier free -o none
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

disk() {
  kubectl apply -f - <<YAML
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
  containers:
  - name: observer
    image: busybox:1.36.1
    securityContext: {privileged: $2}
    command: [sh, -c]
    args:
    - |
      while :; do
        for f in /sys/block/nvme*/queue/read_ahead_kb; do
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
  kubectl wait --for=condition=Ready "pod/$1" --timeout=5m
}
disk original true
MM=$(kubectl exec original -- awk '$5=="/data" {print $3}' /proc/self/mountinfo)
DEV=$(kubectl exec original -- readlink -f "/sys/dev/block/$MM")
echo "original PVC -> /data -> $MM -> $DEV"
kubectl exec original -- cat "$DEV/queue/optimal_io_size" "$DEV/queue/read_ahead_kb"
kubectl logs original --tail=1 --timestamps

seed() { kubectl exec original -- sh -c 'echo 128 > "$1/queue/read_ahead_kb"' sh "$DEV"; }
show() { kubectl logs original --tail=3 --timestamps; }
detach() {
  kubectl delete pod hotplug
  kubectl exec original -- sh -ec '
    for i in $(seq 1 180); do
      [ -e "/sys/dev/block/$1" ] || exit 0
      sleep 1
    done
    echo "Timed out waiting for physical detach" >&2; exit 1
  ' sh "$HOT_MM"
}
echo "Untreated attach"
seed; sleep 2; show
disk hotplug false
HOT_MM=$(kubectl exec hotplug -- awk '$5=="/data" {print $3}' /proc/self/mountinfo)
sleep 2; show
echo "Untreated detach"
seed; sleep 2; show
detach
sleep 2
show

fetch_ds() (
  curl -fsSL https://api.github.com/repos/Azure/AKS/issues/comments/6265013208 |
    jq -erj '.body | capture("```\n(?<yaml>[\\s\\S]*?)```").yaml' > "$WORK/posted.yaml"
  echo "905ddd3ef8f8df2f96263709dfb921f34126972ce560612e16a1f3b9789914f0  $WORK/posted.yaml" |
    shasum -a 256 -c -
  kubectl apply -f "$WORK/posted.yaml"
)
wait_low() {
  kubectl exec original -- sh -ec '
    for i in $(seq 1 150); do
      [ "$(cat "$1/queue/read_ahead_kb")" = 128 ] && exit 0
      sleep 1
    done
    echo "Original PVC did not reach 128 KiB" >&2; exit 1
  ' sh "$DEV"
}
echo "Attach and detach with the published DaemonSet"
fetch_ds
kubectl rollout status ds/reduce-block-readahead --timeout=3m
wait_low
# Shift the attach requests within the polling cycle. The observer records the actual device times.
for delay in 4 32 5; do
  sleep "$delay"
  disk hotplug false
  HOT_MM=$(kubectl exec hotplug -- awk '$5=="/data" {print $3}' /proc/self/mountinfo)
  if [[ $delay == 5 ]]; then
    kubectl logs ds/reduce-block-readahead --timestamps > "$WORK/daemonset-before-replacement.log"
    kubectl delete pod -l app=block-readahead
    kubectl rollout status ds/reduce-block-readahead --timeout=3m
  fi
  wait_low
  detach
  wait_low
done
sleep 2
kubectl logs ds/reduce-block-readahead --timestamps > "$WORK/daemonset.log"
kubectl logs original --timestamps > "$WORK/queues.log"
echo "Observed NVMe queue changes (UTC, KiB)"
awk '{$1=$1; state=substr($0,index($0," ")+1); if (state!=last) print; last=state}' "$WORK/queues.log"
