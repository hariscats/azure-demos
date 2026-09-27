# Azure CNI Overlay on AKS

An Azure Kubernetes Service (AKS) cluster that uses [Azure CNI Overlay](https://learn.microsoft.com/azure/aks/azure-cni-overlay)
networking, with a sample nginx app behind a public load balancer. The deploy script shows where each kind of
IP address comes from:

| Component | IP range | Source |
| --- | --- | --- |
| Nodes | `10.224.0.0/16` (default subnet of the AKS-managed VNet) | Virtual network |
| Pods | `192.168.0.0/16` (`podCidr`) | Private overlay; uses no VNet addresses |
| Services | `10.0.0.0/16` (`serviceCidr`) | Kubernetes cluster IPs |

Pods reach Azure resources and the internet by using the node's IP (SNAT). Because pods don't use VNet addresses,
you can run many more pods with a small subnet than with flat Azure CNI.

## Quick start

```bash
./deploy.sh    # ~8 minutes. Creates rg-cni-overlay, a 2-node cluster, and the nginx app.
./destroy.sh   # Deletes the resource group and removes the kubectl context.
```

You need the Azure CLI (signed in with `az login`) and `kubectl`. [Azure Cloud Shell](https://shell.azure.com)
has both. Override the defaults with `LOCATION`, `RESOURCE_GROUP` or `NODE_VM_SIZE`. To change the CIDRs, edit the
parameters in [`infra/main.bicep`](infra/main.bicep).

## What gets deployed

- [`infra/main.bicep`](infra/main.bicep): an AKS cluster (Free tier, 2 nodes) with `networkPlugin: azure`,
  `networkPluginMode: overlay`, and explicit pod, service and DNS CIDRs.
- [`k8s/deployment.yaml`](k8s/deployment.yaml): nginx with 3 replicas. Each replica answers with its pod name and
  pod IP, so you can see which overlay address served a request.
- [`k8s/service.yaml`](k8s/service.yaml): a `LoadBalancer` service that exposes nginx on a public IP.

## Explore

```bash
# Call the app a few times. Each answer comes from a pod IP in 192.168.0.0/16.
curl http://$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Nodes, pods, services and endpoints with their IPs
kubectl get nodes,pods,services,endpointslices -o wide

# The cluster's network configuration
az aks show -g rg-cni-overlay -n aks-cni-overlay --query networkProfile

# The AKS-managed virtual network lives in the node resource group
az network vnet list -g "$(az aks show -g rg-cni-overlay -n aks-cni-overlay --query nodeResourceGroup -o tsv)" -o table

# Pod-to-service traffic inside the cluster (over the overlay network)
kubectl run nettest --rm -it --restart=Never --image=mcr.microsoft.com/azurelinux/busybox:1.36 \
  --command -- busybox wget -qO- http://nginx-service

# Logs from every nginx replica
kubectl logs -l app=nginx --prefix

# kube-system pods with hostNetwork: true share the node's IP (see the note below)
kubectl get pods -n kube-system -o custom-columns='POD:.metadata.name,IP:.status.podIP,HOST-NETWORK:.spec.hostNetwork'
```

## Clean up

```bash
./destroy.sh   # Asks for confirmation. Use --yes to skip the prompt.
```

`destroy.sh` deletes only the resource group that `deploy.sh` created (tagged `azure-demos=cni-overlay`).

---
**NOTE**

In this AKS cluster deployed with Azure CNI in Overlay mode, it's important to note that certain system-level components, specifically some kube-system pods such as kube-proxy, do not receive an IP address from the Azure CNI overlay podCidr. This is due to their **hostNetwork** property being set to true, meaning they share the host's network namespace and consequently, its IP address. In most cases, this doesn't affect workloads but here's the implications in case your situation is different.
* Network Policies: These pods will not be affected by network policies targeting pod IP addresses, as they operate outside the pod-specific network space.
* Security: Direct access to the host network may introduce security considerations that need to be addressed differently compared to regular pods.
* Monitoring and Logging: Monitoring tools and logging configurations may require adjustments since network traffic from these pods will appear to originate from the host IP.
* Pod Communications: Services that rely on pod-to-pod communication via the overlay network may not interact with these host-network pods in the expected manner.

---
