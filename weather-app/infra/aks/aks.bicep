param location string = resourceGroup().location
param clusterName string = 'myAKSCluster'
param dnsPrefix string
param nodeCount int = 3
param vnetSubnetId string // This should be passed as a parameter from your main deployment file

resource aksCluster 'Microsoft.ContainerService/managedClusters@2022-03-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: nodeCount
        vmSize: 'Standard_DS2_v2'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: vnetSubnetId
        mode: 'System'
      }
    ]
    networkProfile: {
      serviceCidr: '10.0.0.0/16'
      networkPlugin: 'azure'
      networkPluginMode: 'overlay' // Specified as per documentation for particular network requirements
    }
    enableRBAC: true
  }
}
