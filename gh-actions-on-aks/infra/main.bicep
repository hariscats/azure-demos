// Infrastructure for the gh-actions-on-aks demo: a small AKS cluster that hosts
// GitHub Actions Runner Controller (ARC). ARC itself is installed with Helm by deploy.sh.

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the AKS cluster (also used as the kubectl context name).')
param clusterName string = 'aks-gh-actions'

@description('VM size of the AKS nodes.')
param nodeVmSize string = 'Standard_D2s_v5'

@description('Number of AKS nodes.')
@minValue(1)
param nodeCount int = 1

resource aks 'Microsoft.ContainerService/managedClusters@2025-07-01' = {
  name: clusterName
  location: location
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: clusterName
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
    }
  }
}

output clusterName string = aks.name
