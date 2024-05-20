# Using Workload Identity with Python

This repository contains a walkthrough to set up an AKS cluster with Workload Identity enabled and build a Python app that reads a value from Azure Key Vault.

## Prerequisites

- Azure CLI
- Kubernetes CLI (`kubectl`)
- Python 3.7+
- Docker

## Setup

### Set up the Identity

1. **Get the OIDC Issuer URL:**
   ```bash
   export AKS_OIDC_ISSUER="$(az aks show -n $CLUSTER_NAME -g $RG --query "oidcIssuerProfile.issuerUrl" -otsv)"
   ```

2. **Create the Managed Identity:**
   ```bash
   az identity create --name wi-demo-identity --resource-group $RG --location $LOC
   export USER_ASSIGNED_CLIENT_ID=$(az identity show --resource-group $RG --name wi-demo-identity --query 'clientId' -o tsv)
   ```

3. **Create a Service Account:**
   ```bash
   kubectl apply -f k8s/service-account.yaml
   ```

4. **Federate the Identity:**
   ```bash
   az identity federated-credential create \
   --name wi-demo-federated-id \
   --identity-name wi-demo-identity \
   --resource-group $RG \
   --issuer ${AKS_OIDC_ISSUER} \
   --subject system:serviceaccount:default:wi-demo-sa
   ```

### Create the Key Vault and Secret

1. **Create a Key Vault and Set Policies:**
   ```bash
   az keyvault create --name $KEY_VAULT_NAME --resource-group $RG --location $LOC
   USER_ID=$(az ad signed-in-user show --query id -o tsv)
   az keyvault set-policy -n $KEY_VAULT_NAME --certificate-permissions get --object-id $USER_ID
   ```

2. **Create a Secret and Grant Access:**
   ```bash
   az keyvault secret set --vault-name $KEY_VAULT_NAME --name "Secret" --value "Hello"
   az keyvault set-policy --name $KEY_VAULT_NAME --secret-permissions get --spn "${USER_ASSIGNED_CLIENT_ID}"
   ```

### Deployment

1. **Create `Dockerfile`:**
   ```dockerfile
   FROM python:3.7

   ENV PYTHONUNBUFFERED=1

   RUN mkdir /app
   WORKDIR /app
   ADD kv_secrets.py /app/
   RUN pip install azure-identity azure-keyvault-secrets

   CMD ["python", "/app/kv_secrets.py"]
   ```

2. **Build and Deploy:**

   **Build the Image:**
   ```bash
   az acr create -g $RG -n $ACR_NAME --sku Standard
   az acr build -t wi-kv-test -r $ACR_NAME .
   az aks update -g $RG -n $CLUSTER_NAME --attach-acr $ACR_NAME
   ```
Substitute the ACR and Key Vault names in the `k8s/deployment.yaml` file and then apply the deployment.

   **Deploy the Pod:**
   ```bash
   kubectl apply -f k8s/deployment.yaml

   kubectl logs -f wi-kv-test
   ```

### Conclusion

You now have a working pod that uses a Kubernetes Service Account federated to an Azure Managed Identity to access an Azure KV Secret.