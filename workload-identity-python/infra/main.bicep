// Infrastructure for the workload-identity-python demo:
// AKS (OIDC issuer + workload identity), ACR, Key Vault (RBAC) with a demo secret,
// and a user-assigned managed identity federated with a Kubernetes service account.

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Name of the AKS cluster (also used as the kubectl context name).')
param clusterName string = 'aks-wi-demo'

@description('VM size of the AKS nodes.')
param nodeVmSize string = 'Standard_D2s_v5'

@description('Number of AKS nodes.')
@minValue(1)
param nodeCount int = 1

@description('Namespace of the Kubernetes service account that is federated with the managed identity.')
param serviceAccountNamespace string = 'default'

@description('Name of the Kubernetes service account that is federated with the managed identity.')
param serviceAccountName string = 'wi-demo-sa'

@description('Name of the Key Vault secret that the sample app reads.')
param secretName string = 'demo-secret'

var suffix = uniqueString(resourceGroup().id)
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

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
    // The OIDC issuer publishes the keys that Microsoft Entra ID uses to validate
    // the cluster's service account tokens.
    oidcIssuerProfile: {
      enabled: true
    }
    // Installs the webhook that injects the federated token and AZURE_* variables into pods.
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: 'acr${suffix}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// Lets the AKS nodes (kubelet identity) pull images from the registry.
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aks.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: 'kv-${suffix}'
  location: location
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    softDeleteRetentionInDays: 7
  }
}

// Demo value only: never put real secrets in templates.
resource secret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: secretName
  properties: {
    value: 'Hello from Azure Key Vault!'
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-wi-demo'
  location: location
}

// Trust tokens that the cluster's OIDC issuer issues to this service account.
resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: identity
  name: 'aks-${serviceAccountNamespace}-${serviceAccountName}'
  properties: {
    issuer: aks.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${serviceAccountNamespace}:${serviceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// Least privilege: the identity can read this one secret and nothing else in the vault.
resource secretReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secret.id, identity.id, keyVaultSecretsUserRoleId)
  scope: secret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output clusterName string = aks.name
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output keyVaultUri string = keyVault.properties.vaultUri
output secretName string = secretName
output identityClientId string = identity.properties.clientId
