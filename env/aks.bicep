param location string = resourceGroup().location
param keyVaultName string = 'kv-aksgitops-dev-1'
param managedIdentityName string = 'id-aksgitops-dev-1'
param virtualNetworkName string = 'vnet-aksgitops-dev-1'
param clusterName string = 'aks-aksgitops-dev-1'
param kubernetesVersion string = '1.27.3'
@secure()
param clusterAdminUserName string
@secure()
param sshPublicKey string

var aksSubnetName = 'snet-aks'

resource hubVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: 'vnet-hub-shared-1'
}

resource aksVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-01-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.100.20.0/24'
      ]
    }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: '10.100.20.0/25'
        }
      }
    ]
  }
}

resource hubVnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  name: '${aksVirtualNetwork.name}-to-${hubVirtualNetwork.name}'
  parent: aksVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVirtualNetwork.id
    }
  }
}

resource aksVnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  name: '${hubVirtualNetwork.name}-to-${aksVirtualNetwork.name}'
  parent: hubVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: aksVirtualNetwork.id
    }
  }
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-05-02-preview' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: clusterName
    enableRBAC: true
    networkProfile: {
      networkPolicy: 'azure'
      networkPlugin: 'azure'
    }
    addonProfiles: {
      azurePolicy: {
        enabled: true
      }
    }
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 1
        vmSize: 'Standard_B2s'
        osType: 'Linux'
        mode: 'System'
        enableAutoScaling: true
        minCount: 1
        maxCount: 2
        // reason for specifying subnet name via a variable instead of an object reference (virtualNetwork.properties.subnets[0].id):
        // https://github.com/Azure/AKS/issues/695
        vnetSubnetID: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, aksSubnetName)
      }
    ]
    linuxProfile: {
      adminUsername: clusterAdminUserName
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

resource fluxPatSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' existing = {
  name: 'flux-pat'
  parent: keyVault
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

resource managedIdentityKeyVaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, resourceGroup().id, 'ManagedIdentityKeyVaultAccess')
  scope: fluxPatSecret
  properties: {
    principalType: 'ServicePrincipal'
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
  }
}

resource managedIdentityAksClusterUserAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, resourceGroup().id, 'ManagedIdentityAksClusterUserAccess')
  scope: aksCluster
  properties: {
    principalType: 'ServicePrincipal'
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4abbcc35-e782-43d8-92c5-2d3f1bd2253f') // Azure Kubernetes Service Cluster User Role
  }
}

resource fluxBootstrapScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'ds-fluxbootstrap-dev-1'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${managedIdentity.name}': {}
    }
  }
  properties: {
    azPowerShellVersion: '10.3.0'
    retentionInterval: 'PT1H'
    scriptContent: loadTextContent('Initialize-Flux.ps1')
  }
}

output secretVersion string = fluxBootstrapScript.properties.outputs.secretVersion
output fluxVersion string = fluxBootstrapScript.properties.outputs.fluxVersion
output kubectlVersion string = fluxBootstrapScript.properties.outputs.kubectlVersion

output aksClusterName string = aksCluster.name
