// Infrastructure for the cni-overlay demo: an AKS cluster that uses Azure CNI Overlay.
// Nodes get IPs from the (AKS-managed) virtual network subnet, while pods get IPs
// from a private overlay CIDR that doesn't consume any VNet address space.

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the AKS cluster (also used as the kubectl context name).')
param clusterName string = 'aks-cni-overlay'

@description('VM size of the AKS nodes.')
param nodeVmSize string = 'Standard_D2s_v5'

@description('Number of AKS nodes.')
@minValue(1)
param nodeCount int = 2

@description('Private CIDR that pod IPs are allocated from. It must not overlap the VNet or the service CIDR.')
param podCidr string = '192.168.0.0/16'

@description('CIDR that Kubernetes service (cluster) IPs are allocated from.')
param serviceCidr string = '10.0.0.0/16'

@description('Cluster IP of the cluster DNS service. It must be inside serviceCidr.')
param dnsServiceIP string = '10.0.0.10'

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
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      loadBalancerSku: 'standard'
    }
  }
}

output clusterName string = aks.name
output nodeResourceGroup string = aks.properties.nodeResourceGroup
