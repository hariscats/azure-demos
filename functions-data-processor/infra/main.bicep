param location string = 'East US' // Set default location; can be overridden during deployment
param functionName string = 'DataCleansingFunctionApp'

// Generate a unique storage account name using uniqueString()
var storageAccountName = 'st${uniqueString(resourceGroup().id)}'

// Define Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
  }
}

// Define Blob Service as an implicit parent for containers
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2021-06-01' = {
  name: '${storageAccount.name}/default'
  dependsOn: [
    storageAccount
  ]
}

// Define Containers within the Blob Service
resource rawContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  name: '${blobService.name}/raw-data'
  properties: {
    publicAccess: 'None'
  }
}

resource reportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-06-01' = {
  name: '${blobService.name}/reports'
  properties: {
    publicAccess: 'None'
  }
}

// Resource - Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: functionName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableIpMasking: false
    RetentionInDays: 30
  }
}

// Resource - Function App
resource functionApp 'Microsoft.Web/sites@2021-02-01' = {
  name: functionName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: serverFarm.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${appInsights.properties.InstrumentationKey}'
        }
      ]
    }
  }
  dependsOn: [
    storageAccount
    appInsights
  ]
}

// Resource - App Service Plan (Consumption Plan for Azure Functions)
resource serverFarm 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: '${functionName}Plan'
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false
  }
}
