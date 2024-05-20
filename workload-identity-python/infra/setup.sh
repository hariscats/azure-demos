#!/bin/bash

# Optional script to provision resources automatically for a quick demo. 

# Set variables
RG=myAksDemoRg
LOC=eastus
CLUSTER_NAME=myDemoAKSCluster
UNIQUE_ID=$CLUSTER_NAME$RANDOM
ACR_NAME=$UNIQUE_ID
KEY_VAULT_NAME=$UNIQUE_ID

# Create the resource group
az group create -g $RG -l $LOC

# Create the AKS cluster with OIDC Issuer and Workload Identity enabled
az aks create -g $RG -n $CLUSTER_NAME \
--node-count 1 \
--enable-oidc-issuer \
--enable-workload-identity \
--generate-ssh-keys

# Get the cluster credentials
az aks get-credentials -g $RG -n $CLUSTER_NAME

# Get the OIDC Issuer URL
AKS_OIDC_ISSUER="$(az aks show -n $CLUSTER_NAME -g $RG --query "oidcIssuerProfile.issuerUrl" -otsv)"

# Create the managed identity
az identity create --name wi-demo-identity --resource-group $RG --location $LOC

# Get identity client ID
USER_ASSIGNED_CLIENT_ID=$(az identity show --resource-group $RG --name wi-demo-identity --query 'clientId' -o tsv)

# Create a service account to federate with the managed identity
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

# Federate the identity
az identity federated-credential create \
--name wi-demo-federated-id \
--identity-name wi-demo-identity \
--resource-group $RG \
--issuer ${AKS_OIDC_ISSUER} \
--subject system:serviceaccount:default:wi-demo-sa

# Create a key vault
az keyvault create --name $KEY_VAULT_NAME --resource-group $RG --location $LOC

# Get the current user ID
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Set the policy for the current user
az keyvault set-policy -n $KEY_VAULT_NAME --certificate-permissions get --object-id $USER_ID

# Create a secret in the Key Vault
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "Secret" --value "Hello"

# Grant access to the secret for the managed identity
az keyvault set-policy --name $KEY_VAULT_NAME --secret-permissions get --spn "${USER_ASSIGNED_CLIENT_ID}"

# Output the version ID of the secret
VERSION_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name "Secret" -o tsv --query id)
echo "Secret version ID: ${VERSION_ID##*/}"

# Create the ACR
az acr create -g $RG -n $ACR_NAME --sku Standard

# Build the Docker image in ACR
az acr build -t wi-kv-test -r $ACR_NAME .

# Link the ACR to the AKS cluster
az aks update -g $RG -n $CLUSTER_NAME --attach-acr $ACR_NAME
