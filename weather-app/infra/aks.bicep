param location string = resourceGroup().location
param clusterName string = 'myAKSCluster'
param dnsPrefix string
param nodeCount int = 3
param vnetSubnetId string // This should be passed as a parameter from your main deployment file
param acrName string // Assume ACR name is passed as a parameter
param acrResourceGroup string = resourceGroup().name // Optional: pass ACR resource group if different

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
      networkPluginMode: 'overlay'
    }
    enableRBAC: true
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2019-05-01' existing = {
  name: acrName
  scope: resourceGroup(acrResourceGroup)
}

resource acrRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, acr.id, 'acrpull')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    ) // ACRPull role definition
    principalId: aksCluster.identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    aksCluster
  ]
}
