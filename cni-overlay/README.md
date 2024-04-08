# CNI Overlay Demo

## Introduction

This demonstrates deploying an Azure Kubernetes Service (AKS) cluster using the Azure Container Networking Interface (CNI) in Overlay mode. It features a script to create an AKS cluster with the CNI Overlay plugin, sample Nginx app deployment, a Service to expose it, and walkthrough to verify IP assignment.

## Prerequisites

- Azure CLI installed and configured
- `kubectl` installed
- An active Azure subscription

## Getting Started

### 1. Setup AKS Cluster

Execute the `setup-aks-cni-overlay.sh` script to create your AKS cluster with Azure CNI Overlay.

```bash
./setup-aks-cni-overlay.sh
```

### 2. Deploy Sample App

Deploy the Nginx application:

```bash
kubectl apply -f deployment.yaml
```

### 3. Expose the App

Expose Nginx using:

```bash
kubectl apply -f service.yaml
```

### 4. Verify IP Address ranges, assignments, and connectivity

Check AKS and network configuration:

```bash
az aks list -o table
az network vnet list -o table
az network vnet subnet list --resource-group <resource-group-name> --vnet-name <vnet-name> -o table
az aks show --resource-group <resource-group-name> --name <cluster-name> --query networkProfile.podCidr --output table
```

Verify the IP address assignments using the following command:

```bash
kubectl get no,po,svc,ep -o wide 
```

Verify connectivity to the Nginx service using the following command:

```bash
kubectl run -it --rm --restart=Never busybox --image=busybox -- wget -qO- http://<nginx-service-ip>
```

Select Deployment and then fetch each containers logs:

```bash
kubectl get pods -l app=<deployment-name> -n <namespace> --no-headers=true | awk '{print $1}' | xargs -I {} kubectl logs {} -n <namespace>
```

---
**NOTE**

In this AKS cluster deployed with Azure CNI in Overlay mode, it's important to note that certain system-level components, specifically some kube-system pods such as kube-proxy, do not receive an IP address from the Azure CNI overlay podCidr. This is due to their **hostNetwork** property being set to true, meaning they share the host's network namespace and consequently, its IP address. In most cases, this doesn't affect workloads but here's the implications in case your situation is different.
* Network Policies: These pods will not be affected by network policies targeting pod IP addresses, as they operate outside the pod-specific network space.
* Security: Direct access to the host network may introduce security considerations that need to be addressed differently compared to regular pods.
* Monitoring and Logging: Monitoring tools and logging configurations may require adjustments since network traffic from these pods will appear to originate from the host IP.
* Pod Communications: Services that rely on pod-to-pod communication via the overlay network may not interact with these host-network pods in the expected manner.

---
