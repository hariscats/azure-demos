param location string = resourceGroup().location

resource apimService 'Microsoft.ApiManagement/service@2021-01-01-preview' = {
  name: 'myAPIM-${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherName: 'Your Publisher Name'
    publisherEmail: 'email@example.com'
  }
}
