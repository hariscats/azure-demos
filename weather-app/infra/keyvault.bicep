param location string = resourceGroup().location

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: 'myKeyVault-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
  }
}
