param location string = resourceGroup().location
param vnetName string = 'myVnet'
param vnetAddressPrefix string = '10.1.0.0/16'
param aksSubnetName string = 'aksSubnet'
param aksSubnetPrefix string = '10.1.1.0/24'

// Define the virtual network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

// Define the subnet as a child resource of the virtual network
resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' = {
  name: aksSubnetName
  properties: {
    addressPrefix: aksSubnetPrefix
  }
  parent: virtualNetwork
}

// Output the subnet ID
output aksSubnetId string = aksSubnet.id
