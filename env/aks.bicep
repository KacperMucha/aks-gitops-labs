param location string = 'northeurope'
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
  name: 'peering-to-hub-vnet'
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


// Resources below are disabled for now. The extension deploys an old version of Flux.

// resource aksFluxExtension 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = {
//   name: 'flux'
//   scope: aksCluster
//   properties: {
//     extensionType: 'microsoft.flux'
//     autoUpgradeMinorVersion: true
//   }
// }

// resource aksClusterFluxConfig 'Microsoft.KubernetesConfiguration/fluxConfigurations@2023-05-01' = {
//   name: 'bootstrap'
//   scope: aksCluster
//   dependsOn: [
//     aksFluxExtension
//   ]
//   properties: {
//     scope: 'cluster'
//     namespace: 'cluster-config'
//     suspend: false
//     configurationProtectedSettings: {}
//     sourceKind: 'GitRepository'
//     gitRepository: {
//       url: 'https://github.com/Azure/gitops-flux2-kustomize-helm-mt'
//       timeoutInSeconds: 300
//       syncIntervalInSeconds: 300
//       repositoryRef: {
//         branch: 'main'
//       }
//     }
//     kustomizations: {
//       infra: {
//         path: './infrastructure'
//         timeoutInSeconds: 300
//         syncIntervalInSeconds: 300
//         retryIntervalInSeconds: 300
//         force: false
//         prune: true
//         dependsOn: []
//       }
//       apps:{
//         path: './apps/staging'
//         timeoutInSeconds: 300
//         syncIntervalInSeconds: 300
//         retryIntervalInSeconds: 300
//         force: false
//         prune: true
//         dependsOn: [
//           'infra'
//         ]
//       }
//     }
//   }
// }

output aksClusterName string = aksCluster.name
