#!/bin/bash

# Define variables
RESOURCE_GROUP="AksNetDemo"
AKS_CLUSTER_NAME="AksCniOverlay"
LOCATION="eastus"

# Function to create a resource group
create_resource_group() {
    echo "Creating resource group..."
    az group create --name $RESOURCE_GROUP --location $LOCATION
}

# Function to create an AKS cluster
create_aks_cluster() {
    echo "Creating AKS cluster..."
    az aks create \
        --resource-group $RESOURCE_GROUP \
        --name $AKS_CLUSTER_NAME \
        --network-plugin azure \
        --network-plugin-mode overlay \
        --pod-cidr 192.168.0.0/16 \
        --node-count 2 \
        --enable-addons monitoring \
        --generate-ssh-keys
}

# Function to get credentials for kubectl
get_kubectl_credentials() {
    echo "Getting AKS credentials for kubectl..."
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME
}


# Main script execution
create_resource_group
create_aks_cluster
get_kubectl_credentials

echo "Script execution completed."
