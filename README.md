# AKS Networking Demos

## Introduction

This repository demonstrates deploying an Azure Kubernetes Service (AKS) cluster using the Azure Container Networking Interface (CNI) in Overlay mode. It features a sample Nginx app deployment, a network policy to manage access within the cluster, and a test deployment to illustrate network policy enforcement. This demo aims to provide insights into scalable and efficient network management capabilities in a Kubernetes environment on Azure. Overtime, this repository will be expanded to include more networking features and best practices.

## Prerequisites

- Azure CLI installed and configured
- `kubectl` installed
- An active Azure subscription

## Repository Structure

```
/
|-- cnioverlay/
|   |-- deployment.yaml                 # Nginx deployment
|   |-- service.yaml                    # Service to expose Nginx
|   |-- networkpolicy.yaml              # Network policy for Nginx access control
|   `-- frontend-test-deployment.yaml   # Test Deployment to demonstrate network policy enforcement
|-- scripts/
|   `-- setup-aks-cni-overlay.sh        # Script to setup AKS with Azure CNI Overlay
|-- README.md
```

## Getting Started

### 1. Setup AKS Cluster

Execute the `setup-aks-cni-overlay.sh` script in the `scripts/` directory to create your AKS cluster with Azure CNI Overlay.

```bash
./scripts/setup-aks-cni-overlay.sh
```

### 2. Deploy Sample App

Deploy the Nginx application:

```bash
kubectl apply -f cnioverlay/deployment.yaml
```

### 3. Expose the App

Expose Nginx using:

```bash
kubectl apply -f cnioverlay/service.yaml
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

### 5. Optional - Apply Network Policy

Before applying the network policy, ensure that the `NetworkPolicy` resource is enabled in the AKS cluster. This can be done by setting the `networkPolicy` field to `azure` in the `networkProfile` section of the AKS cluster configuration.

```bash
az aks update --resource-group <resource-group-name> --name <cluster-name> --network-policy azure
```

Restrict access to Nginx pods:

```bash
kubectl apply -f cnioverlay/networkpolicy.yaml
```

### 6. Optional - Demonstrate Network Policy Enforcement

Deploy a test frontend application that adheres to the network policy:

```bash
kubectl apply -f tests/frontend-test-deployment.yaml
```

## Demonstrating Network Policy Enforcement

1. **From an Allowed Pod**: Exec into the `frontend-test` pod and use `wget` or `curl` to access the Nginx service. This should succeed, demonstrating the network policy allows traffic from pods with the `role: web-frontend` label.

2. **From a Disallowed Pod**: Attempting a similar access from a pod not matching the network policy should fail, illustrating the enforcement of network isolation.
