param location string = 'northeurope'
param virtualNetworkName string = 'vnet-gl-1'
param clusterName string = 'aks-gl-1'
param kubernetesVersion string = '1.23.8'
@secure()
param clusterAdminUserName string
@secure()
param sshPublicKey string


resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-01-01' = {
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
        name: 'snet-aks'
        properties: {
          addressPrefix: '10.100.20.0/25'
        }
      }
    ]
  }
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2022-07-02-preview' = {
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
        vnetSubnetID: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, virtualNetwork.properties.subnets[0].name) // virtualNetwork.properties.subnets[0].id
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

resource aksFluxExtension 'Microsoft.KubernetesConfiguration/extensions@2022-07-01' = {
  name: 'flux'
  scope: aksCluster
  properties: {
    extensionType: 'microsoft.flux'
    autoUpgradeMinorVersion: true
  }
}

resource aksClusterFluxConfig 'Microsoft.KubernetesConfiguration/fluxConfigurations@2022-07-01' = {
  name: 'bootstrap'
  scope: aksCluster
  dependsOn: [
    aksFluxExtension
  ]
  properties: {
    scope: 'cluster'
    namespace: 'cluster-config'
    suspend: false
    configurationProtectedSettings: {}
    sourceKind: 'GitRepository'
    gitRepository: {
      url: 'https://github.com/Azure/gitops-flux2-kustomize-helm-mt'
      timeoutInSeconds: 300
      syncIntervalInSeconds: 300
      repositoryRef: {
        branch: 'main'
      }
    }
    kustomizations: {
      infra: {
        name: 'infra'
        path: './infrastructure'
        timeoutInSeconds: 300
        syncIntervalInSeconds: 300
        retryIntervalInSeconds: 300
        force: false
        prune: true
        dependsOn: []
      }
      apps:{
        name: 'apps'
        path: './apps/staging'
        timeoutInSeconds: 300
        syncIntervalInSeconds: 300
        retryIntervalInSeconds: 300
        force: false
        prune: true
        dependsOn: [
          'infra'
        ]
      }
    }
  }
}
