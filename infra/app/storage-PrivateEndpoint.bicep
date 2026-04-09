param virtualNetworkName string
param subnetName string
@description('Specifies the storage account resource name')
param resourceName string
param location string = resourceGroup().location
param tags object = {}
param enableBlob bool = true
param enableQueue bool = false
param enableTable bool = false

resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' existing = {
  name: virtualNetworkName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: resourceName
}

// Storage DNS zone names
var blobPrivateDNSZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var queuePrivateDNSZoneName = 'privatelink.queue.${environment().suffixes.storage}'
var tablePrivateDNSZoneName = 'privatelink.table.${environment().suffixes.storage}'

// AVM module for Blob Private Endpoint with private DNS zone
module blobPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.11.0' = if (enableBlob) {
  name: '${resourceName}-blob-private-endpoint-deployment'
  params: {
    name: 'blob-private-endpoint'
    location: location
    tags: tags
    subnetResourceId: '${vnet.id}/subnets/${subnetName}'
    privateLinkServiceConnections: [
      {
        name: 'blobPrivateLinkConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
    customDnsConfigs: []
    // Attaches the private endpoint to the existing DNS zone (zone is created separately below)
    privateDnsZoneGroup: {
      name: 'blobPrivateDnsZoneGroup'
      privateDnsZoneGroupConfigs: [
        {
          name: 'storageBlobARecord'
          privateDnsZoneResourceId: enableBlob ? privateDnsZoneBlobDeployment.outputs.resourceId : ''
        }
      ]
    }
  }
}

// AVM module for Queue Private Endpoint with private DNS zone
module queuePrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.11.0' = if (enableQueue) {
  name: '${resourceName}-queue-private-endpoint-deployment'
  params: {
    name: 'queue-private-endpoint'
    location: location
    tags: tags
    subnetResourceId: '${vnet.id}/subnets/${subnetName}'
    privateLinkServiceConnections: [
      {
        name: 'queuePrivateLinkConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'queue'
          ]
        }
      }
    ]
    customDnsConfigs: []
    // Attaches the private endpoint to the existing DNS zone (zone is created separately below)
    privateDnsZoneGroup: {
      name: 'queuePrivateDnsZoneGroup'
      privateDnsZoneGroupConfigs: [
        {
          name: 'storageQueueARecord'
          privateDnsZoneResourceId: enableQueue ? privateDnsZoneQueueDeployment.outputs.resourceId : ''
        }
      ]
    }
  }
}

// AVM module for Table Private Endpoint with private DNS zone
module tablePrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.11.0' = if (enableTable) {
  name: '${resourceName}-table-private-endpoint-deployment'
  params: {
    name: 'table-private-endpoint'
    location: location
    tags: tags
    subnetResourceId: '${vnet.id}/subnets/${subnetName}'
    privateLinkServiceConnections: [
      {
        name: 'tablePrivateLinkConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'table'
          ]
        }
      }
    ]
    customDnsConfigs: []
    // Attaches the private endpoint to the existing DNS zone (zone is created separately below)
    privateDnsZoneGroup: {
      name: 'tablePrivateDnsZoneGroup'
      privateDnsZoneGroupConfigs: [
        {
          name: 'storageTableARecord'
          privateDnsZoneResourceId: enableTable ? privateDnsZoneTableDeployment.outputs.resourceId : ''
        }
      ]
    }
  }
}

// AVM module for Blob Private DNS Zone
// VNet links are created separately below to avoid concurrent UpsertPrivateDnsZone conflicts.
module privateDnsZoneBlobDeployment 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (enableBlob) {
  name: '${resourceName}-blob-private-dns-zone-deployment'
  params: {
    name: blobPrivateDNSZoneName
    location: 'global'
    tags: tags
  }
}

// AVM module for Queue Private DNS Zone
module privateDnsZoneQueueDeployment 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (enableQueue) {
  name: '${resourceName}-queue-private-dns-zone-deployment'
  params: {
    name: queuePrivateDNSZoneName
    location: 'global'
    tags: tags
  }
}

// AVM module for Table Private DNS Zone
module privateDnsZoneTableDeployment 'br/public:avm/res/network/private-dns-zone:0.7.1' = if (enableTable) {
  name: '${resourceName}-table-private-dns-zone-deployment'
  params: {
    name: tablePrivateDNSZoneName
    location: 'global'
    tags: tags
  }
}

// VNet links are created AFTER the private endpoints to serialize ARM's UpsertPrivateDnsZone operations:
//   1) DNS zone creation  →  2) DNS zone group attachment (private endpoint)  →  3) VNet link
// Creating the link concurrently with the zone or endpoint causes an ARM conflict error.
resource blobVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableBlob) {
  name: '${blobPrivateDNSZoneName}/${resourceName}-blob-link-${take(toLower(uniqueString(resourceName, virtualNetworkName)), 4)}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZoneBlobDeployment
    blobPrivateEndpoint
  ]
}

resource queueVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableQueue) {
  name: '${queuePrivateDNSZoneName}/${resourceName}-queue-link-${take(toLower(uniqueString(resourceName, virtualNetworkName)), 4)}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZoneQueueDeployment
    queuePrivateEndpoint
  ]
}

resource tableVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableTable) {
  name: '${tablePrivateDNSZoneName}/${resourceName}-table-link-${take(toLower(uniqueString(resourceName, virtualNetworkName)), 4)}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateDnsZoneTableDeployment
    tablePrivateEndpoint
  ]
}
