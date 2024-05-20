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

