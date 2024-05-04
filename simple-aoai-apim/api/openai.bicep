param openaiInstanceName string
param location string
param resourceGroupName string

resource openaiInstance 'Microsoft.CognitiveServices/accounts@2022-08-01' = {
  name: openaiInstanceName
  location: location
  sku: {
    name: 'F0'
    tier: 'Free'
  }
  kind: 'TextAnalytics'
}
