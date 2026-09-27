#!/usr/bin/env bash
# Deploys the cni-overlay demo: an AKS cluster with Azure CNI Overlay networking
# plus an nginx deployment behind a public LoadBalancer service, then shows which
# address range nodes, pods and services get their IPs from.
#
# Usage: ./deploy.sh
#
# Optional environment variables:
#   RESOURCE_GROUP  Resource group to create/use (default: rg-cni-overlay)
#   LOCATION        Azure region (default: eastus)
#   NODE_VM_SIZE    AKS node size (default: Standard_D2s_v5)

set -Eeuo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../scripts/common.sh
source "$DEMO_DIR/../scripts/common.sh"
init_demo "$@"

require_tools az kubectl
require_az_login
register_providers Microsoft.ContainerService
ensure_resource_group
deploy_bicep ${NODE_VM_SIZE:+"nodeVmSize=$NODE_VM_SIZE"}
read_outputs CLUSTER_NAME=clusterName NODE_RESOURCE_GROUP=nodeResourceGroup
aks_get_credentials "$CLUSTER_NAME"

info "Deploying nginx (3 replicas) and a LoadBalancer service..."
kubectl apply -f "$DEMO_DIR/k8s/"
kubectl rollout status deployment/nginx-deployment --timeout=300s

public_ip() { kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; }
has_public_ip() { [[ -n "$(public_ip)" ]]; }
info "Waiting for the service's public IP..."
retry 60 5 has_public_ip || die "The service didn't get a public IP. Check: kubectl describe service nginx-service"
PUBLIC_IP="$(public_ip)"

echo
info "Cluster network profile:"
az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --output table --query \
  "networkProfile.{Plugin:networkPlugin, Mode:networkPluginMode, PodCidr:podCidr, ServiceCidr:serviceCidr, DnsServiceIp:dnsServiceIp}"

echo
info "Nodes get IPs from the VNet subnet:"
az network vnet list --resource-group "$NODE_RESOURCE_GROUP" --output table --query \
  "[].{VNet:name, AddressSpace:join(', ', addressSpace.addressPrefixes), Subnet:subnets[0].name, SubnetPrefix:subnets[0].addressPrefix}"
kubectl get nodes -o custom-columns='NODE:.metadata.name,NODE-IP:.status.addresses[?(@.type=="InternalIP")].address'

echo
info "Pods get IPs from the overlay pod CIDR, which isn't part of the VNet:"
kubectl get pods -l app=nginx -o custom-columns='POD:.metadata.name,POD-IP:.status.podIP,NODE:.spec.nodeName'

echo
info "Services get IPs from the service CIDR (and a public IP from the Azure load balancer):"
kubectl get service nginx-service

if command -v curl >/dev/null 2>&1; then
  echo
  info "Calling http://$PUBLIC_IP from this machine (the load balancer spreads requests across the pods)..."
  if retry 12 5 curl --silent --fail --max-time 5 --output /dev/null "http://$PUBLIC_IP"; then
    for _ in 1 2 3 4 5; do curl --silent --max-time 5 "http://$PUBLIC_IP" || true; done
  else
    warn "No answer from http://$PUBLIC_IP yet. The load balancer rule can take a minute; try again shortly."
  fi
fi

cat <<EOF

Done! nginx is available at http://$PUBLIC_IP
Each response names the pod that served it and the pod's overlay IP.

  Everything at once:  kubectl get nodes,pods,services,endpointslices -o wide
  Host-network pods:   kubectl get pods -n kube-system -o wide   (these share their node's IP)
  Clean up:            ./destroy.sh
EOF
