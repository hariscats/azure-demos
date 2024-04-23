#!/bin/bash

# Function to log messages with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Default values for the variables
: ${RESOURCE_GROUP:="myDefaultResourceGroup"}
: ${CLUSTER_NAME:="myDefaultAKSCluster"}
: ${NODE_POOL_NAME:="myDefaultNodePool"}
: ${NODE_VM_SIZE:="Standard_NC6s_v3"}

# Time the node pool addition
node_pool_start_time=$(date +%s)

# Add nodepool to AKS
log "Starting the GPU node provisioning process."

output=$(az aks nodepool add --resource-group $RESOURCE_GROUP \
                             --cluster-name $CLUSTER_NAME \
                             --name $NODE_POOL_NAME \
                             --node-count 1 \
                             --node-vm-size $NODE_VM_SIZE \
                             --os-sku AzureLinux \
                             --os-type Linux \
                             --node-taints sku=gpu:NoSchedule \
                             --node-osdisk-type Managed \
                             --eviction-policy Deallocate \
                             --enable-cluster-autoscaler \
                             --min-count 1 \
                             --max-count 3 2>&1)

status=$?

node_pool_end_time=$(date +%s)
node_pool_duration=$((node_pool_end_time - node_pool_start_time))

# Check for command success
if [ $status -ne 0 ]; then
    log "Error adding nodepool to AKS: $output"
    exit 1
else
    log "Nodepool added successfully. Time taken: ${node_pool_duration} seconds."
fi

# Checking node readiness
log "Checking for node readiness..."

# Time the readiness check
readiness_start_time=$(date +%s)

# Loop to check if the nodes are ready
while true; do
    # Check nodes in the node pool
    ready_nodes=$(kubectl get nodes -l agentpool=$NODE_POOL_NAME -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}')
    # Count how many nodes are ready
    ready_count=0
    for node_status in $ready_nodes; do
        if [ "$node_status" = "True" ]; then
            ((ready_count++))
        fi
    done

    if [ "$ready_count" -eq 1 ]; then # Assumes 1 node as per node-count above
        readiness_end_time=$(date +%s)
        readiness_duration=$((readiness_end_time - readiness_start_time))
        log "All nodes in the node pool are ready. Time taken: ${readiness_duration} seconds."
        break
    else
        log "Waiting for nodes to become ready..."
        sleep 10 # Wait for 10 seconds before checking again
    fi
done
