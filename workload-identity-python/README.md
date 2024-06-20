# Use Workload Identity with Python client app in AKS to access Key Vault

In this walkthrough, we'll set up an AKS cluster with Workload Identity enabled and build a Python app that reads a value from Azure Key Vault.

## Prerequisites

- Azure CLI
- Kubernetes CLI (`kubectl`)
- Python 3.7+
- Docker

## Setup

### Cluster Creation

First, we need to create the AKS cluster with the OIDC Issuer and Workload Identity (WI) add-on enabled. The OIDC issuer in AKS issues tokens that Entra ID can validate and trust. This trust relationship is established through the federation of the managed identity (MI) with the Kubernetes service account.

```bash
export RG=WorkloadIdentityRG
export LOC=eastus
export CLUSTER_NAME=wilab
export UNIQUE_ID=$CLUSTER_NAME$RANDOM
export ACR_NAME=$UNIQUE_ID
export KEY_VAULT_NAME=$UNIQUE_ID

# Create the resource group
az group create -g $RG -l $LOC

# Create the cluster with the OIDC Issuer and Workload Identity enabled
az aks create -g $RG -n $CLUSTER_NAME \
  --node-count 1 \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --generate-ssh-keys

# Get the cluster credentials
az aks get-credentials -g $RG -n $CLUSTER_NAME
```

### Set up the Identity

To federate a managed identity with a Kubernetes Service Account, we need to get the AKS OIDC Issuer URL, create the Managed Identity, and then create the federation. 

1. **Get the OIDC Issuer URL:**
   ```bash
   export AKS_OIDC_ISSUER="$(az aks show -n $CLUSTER_NAME -g $RG --query "oidcIssuerProfile.issuerUrl" -otsv)"
   ```
   - **Explanation:** This command retrieves the OIDC Issuer URL of the AKS cluster, which will be used for setting up the federation. The federated setup allows Azure AD to trust the Service Account tokens issued by the AKS cluster. Entra ID issues tokens that can be used to access Azure resources based on the Service Account's identity and permissions.

2. **Create the Managed Identity:**
   ```bash
   az identity create --name wi-demo-identity --resource-group $RG --location $LOC
   export USER_ASSIGNED_CLIENT_ID=$(az identity show --resource-group $RG --name wi-demo-identity --query 'clientId' -o tsv)
   ```
   - **Explanation:** This creates a user-assigned managed identity in Azure and retrieves its client ID, which will be used to federate with the Kubernetes Service Account. Managed Identities in Azure are Entra ID identities automatically managed by Azure. They can be used to authenticate to any service that supports Entra ID authentication without the need to manage credentials. 

3. **Create a Service Account:**
   Create a Kubernetes service account and annotate it with the managed identity client ID.
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     annotations:
       azure.workload.identity/client-id: ${USER_ASSIGNED_CLIENT_ID}
     labels:
       azure.workload.identity/use: "true"
     name: wi-demo-sa
     namespace: default
   EOF
   ```
   - **Explanation:** This YAML definition creates a Kubernetes Service Account and associates it with the managed identity using annotations. A Kubernetes Service Account is an identity that can be assigned to a pod within a Kubernetes cluster. It allows pods to authenticate and perform actions within the cluster and, when federated, access external resources such as Azure services. Each Service Account is scoped to a specific namespace and can be assigned permissions through Kubernetes Role-Based Access Control (RBAC).

4. **Federate the Identity:**
   ```bash
   az identity federated-credential create \
     --name wi-demo-federated-id \
     --identity-name wi-demo-identity \
     --resource-group $RG \
     --issuer ${AKS_OIDC_ISSUER} \
     --subject system:serviceaccount:default:wi-demo-sa
   ```
   - **Explanation:** This command creates a federated credential, linking the managed identity to the Kubernetes Service Account using the OIDC Issuer URL. The OIDC issuer in AKS then issues tokens that Azure AD can validate and trust. This trust relationship is established through the **federation** of the managed identity with the Kubernetes service account.

### Create the Key Vault and Secret

1. **Create a Key Vault and Set Policies:**
   ```bash
   az keyvault create --name $KEY_VAULT_NAME --resource-group $RG --location $LOC
   USER_ID=$(az ad signed-in-user show --query id -o tsv)
   az keyvault set-policy -n $KEY_VAULT_NAME --certificate-permissions get --object-id $USER_ID
   ```
   - **Explanation:** This creates an Azure Key Vault and sets an access policy for the current user.

2. **Create a Secret and Grant Access:**
   ```bash
   az keyvault secret set --vault-name $KEY_VAULT_NAME --name "Secret" --value "Hello"
   az keyvault set-policy --name $KEY_VAULT_NAME --secret-permissions get --spn "${USER_ASSIGNED_CLIENT_ID}"
   ```
   - **Explanation:** This creates a secret in the Key Vault and grants the managed identity access to this secret.

### Create the Sample Python App

1. **Set up the Project:**
   ```bash
   mkdir wi-python
   cd wi-python
   pip install azure-identity azure-keyvault-secrets
   ```

2. **Create `secrets.py`:**
   ```python
   import os
   import time
   from azure.keyvault.secrets import SecretClient
   from azure.identity import DefaultAzureCredential

   keyVaultName = os.environ["KEY_VAULT_NAME"]
   secretName = os.environ["SECRET_NAME"]
   KVUri = f"https://{keyVaultName}.vault.azure.net"

   credential = DefaultAzureCredential()
   client = SecretClient(vault_url=KVUri, credential=credential)

   while True:
       print(f"Retrieving your secret from {keyVaultName}.")
       retrieved_secret = client.get_secret(secretName)
       print(f"Secret value: {retrieved_secret.value}")
       time.sleep(5)
   ```

3. **Create `Dockerfile`:**
   ```dockerfile
   FROM --platform=linux/amd64 python:3.10-slim

   ENV PYTHONUNBUFFERED=1

   RUN mkdir /app
   WORKDIR /app
   ADD secrets.py /app/
   RUN pip install azure-identity azure-keyvault-secrets

   CMD ["python", "/app/secrets.py"]
   ```

### Build and Deploy

1. **Build the Image:**
   ```bash
   az acr create -g $RG -n $ACR_NAME --sku Standard
   az acr build -t wi-kv-test -r $ACR_NAME .
   az aks update -g $RG -n $CLUSTER_NAME --attach-acr $ACR_NAME
   ```
   - **Explanation:** These commands create an Azure Container Registry, build the Docker image for the Python app, and link the ACR to the AKS cluster.

2. **Deploy the Pod:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: wi-kv-test
  namespace: default
  labels:
    azure.workload.identity/use: "true"  
spec:
  serviceAccountName: wi-demo-sa
  containers:
    - image: ${ACR_NAME}.azurecr.io/wi-kv-test:1.0
      imagePullPolicy: Always
      name: wi-kv-test
      env:
      - name: KEY_VAULT_NAME
        value: ${KEY_VAULT_NAME}
      - name: SECRET_NAME
        value: Secret     
  nodeSelector:
    kubernetes.io/os: linux
EOF

# Check the pod logs
kubectl logs -f wi-kv-test

# Sample Output
Retrieving your secret from wilab4521.
Secret value: Hello
   # Check the pod logs
   kubectl logs -f wi-kv-test
   ```
   - **Explanation:** This Kubernetes YAML file deploys a pod that runs the Python application. The pod uses the service account federated with the managed identity to access the Azure Key Vault secret. In other words, this pod will inherit the federated identity and can use it to authenticate to Azure resources. Environment variables `KEY_VAULT_NAME` and `SECRET_NAME` are passed to the pod for configuring the Key Vault client in the Python app.

### Conclusion

You now have a working pod that uses a Kubernetes Service Account federated to an Azure Managed Identity to access an Azure Key Vault Secret. This setup allows for secure access to Azure resources using managed identities, simplifying credential management and enhancing security.
