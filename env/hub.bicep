param location string = resourceGroup().location
param virtualNetworkName string = 'vnet-hub-shared-1'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-01-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.100.10.0/24'
      ]
    }
    subnets: [
      {
        name: 'snet-mgmt'
        properties: {
          addressPrefix: '10.100.10.0/24'
        }
      }
    ]
  }
}
