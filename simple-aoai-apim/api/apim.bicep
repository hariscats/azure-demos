param openAiApiKey string
param apimServiceName string
param location string

resource apimService 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: apimServiceName
  location: location
  properties: {
    publisherEmail: 'admin@example.com'
    publisherName: 'Demo Publisher'
    sku: {
      name: 'Developer'
      capacity: 1
    }
  }
}

resource openaiApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  name: '${apimService.name}/openai'
  parent: apimService
  properties: {
    displayName: 'OpenAI API'
    description: 'API for OpenAI'
    serviceUrl: 'https://api.openai.com/v1/'
    protocols: [
      'https'
    ]
    authenticationSettings: {
      oAuth2: {
        authorizationServerId: '${apimService.name}/authorizationServers/default'
        scope: 'openid'
        identityProvider: {
          clientId: 'openaiClientId'
          clientSecret: 'openaiClientSecret'
          type: 'aad'
        }
      }
    }
  }
}
