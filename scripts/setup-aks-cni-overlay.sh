#!/bin/bash

# Define variables
RESOURCE_GROUP="AksNetDemo"
AKS_CLUSTER_NAME="AksCniOverlay"
LOCATION="eastus"
APP_NAME="nginx-deployment"
SERVICE_NAME="nginx-service"

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

# Function to deploy a sample application
deploy_sample_application() {
    echo "Deploying sample application..."
    kubectl create deployment $APP_NAME --image=nginx
    kubectl expose deployment $SERVICE_NAME --port=80 --type=LoadBalancer
}

# Function to display pod IP addresses
show_pod_ips() {
    echo "Pod IP addresses:"
    kubectl get pods -o wide
}

# Main script execution
create_resource_group
create_aks_cluster
get_kubectl_credentials
deploy_sample_application
show_pod_ips

echo "Script execution completed."
