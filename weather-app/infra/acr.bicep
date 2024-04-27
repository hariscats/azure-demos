param location string = resourceGroup().location
param sku string = 'Standard' // Options are Basic, Standard, Premium

var uniqueSuffix = uniqueString(resourceGroup().id)
var acrName = 'myacr${uniqueSuffix}'

resource acr 'Microsoft.ContainerRegistry/registries@2019-05-01' = {
  name: acrName
  location: location
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: true
  }
}
