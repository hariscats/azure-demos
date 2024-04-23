#### Overview
This script automates the provisioning and readiness testing of a GPU node in AKS. The node pool has Cluster Autoscaler and the scale down mode set to Deallocate to further test node reprovisioning after scale down.

#### Prerequisites
- Azure CLI
- kubectl
- Bash environment or WSL

#### Configuration
Set the following environment variables appropriate to your Azure setup, or directly modify them in the script:
- `RESOURCE_GROUP`: Azure Resource Group containing the AKS cluster.
- `CLUSTER_NAME`: Name of the AKS cluster.
- `NODE_POOL_NAME`: Name for the new node pool.
- `NODE_VM_SIZE`: VM size (e.g., `Standard_NC6s_v3`).

#### Usage
1. Optionally set environment variables:
    ```bash
    export RESOURCE_GROUP="yourResourceGroup"
    export CLUSTER_NAME="yourClusterName"
    export NODE_POOL_NAME="yourNodePoolName"
    export NODE_VM_SIZE="Standard_NC6s_v3"
    ```
2. Execute the script:
    ```bash
    ./provision_gpu_node.sh
    ```

#### Script Functions
- **Node Pool Addition**: Adds a GPU node pool and logs the time taken.
- **Readiness Check**: Monitors node readiness and logs the duration.

#### Considerations
Ensure appropriate permissions and be aware of cost implications associated with GPU provisioning and autoscaling.
