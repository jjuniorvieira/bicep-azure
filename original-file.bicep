@description('The Azure region into which the resources should be deployed.')
param location string = resourceGroup().location

@allowed([
  'F1'
  'D1'
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1'
  'P2'
  'P3'
  'P4'
])
param skuName string = 'F1'

@minValue(1)
param skuCapacity int = 1
param sqlAdministratorLogin string

@secure()
param sqlAdministratorLoginPassword string

param managedIdentityName string
param roleDefinitionId string = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
param webSiteName string = 'webSite${uniqueString(resourceGroup().id)}'
param container1Name string = 'productspecs'
param productmanualsName string = 'productmanuals'
param environmentType string = 'ota'

var hostingPlanName = 'hostingplan${uniqueString(resourceGroup().id)}'
var sqlserverName = 'toywebsite${uniqueString(resourceGroup().id)}'
var storageAccountName = 'toywebsite${uniqueString(resourceGroup().id)}'
var logAnalyticsWorkspaceName = 'logAnalyticsWorkspaceName'
var cosmosDBAccountDiagnosticSettingsName = 'cosmosDBAccountDiagnosticSettingsName'

@description('The default host name of the App Service app.')
output hostname string = '${cosmosDBAccountDiagnosticSettingsName}.azurewebsites.net'

output hostname2 string = cosmosDBAccountDiagnosticSettingsName

var environmentConfigurationMap = {
  Production: {
    enableLogging: true
  }
  Test: {
    enableLogging: false
  }
}


@description('Indicates whether the web application firewall policy should be enabled.')
var enableWafPolicy = (environmentType == 'prod')

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-03-01-preview' = if (environmentConfigurationMap[environmentType].enableLogging) {
  name: logAnalyticsWorkspaceName
  location: location
}

//single line of comment

/*
* multiple lines of comment
*/

resource cosmosDBAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2017-05-01-preview' = if (environmentConfigurationMap[environmentType].enableLogging) {
  // scope: cosmosDBAccount
  name: cosmosDBAccountDiagnosticSettingsName
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    // ...
  }
}

var cosmosDBContainerDefinitions = [
  {
    name: 'customers'
    partitionKey: '/customerId'
  }
  {
    name: 'orders'
    partitionKey: '/orderId'
  }
  {
    name: 'products'
    partitionKey: '/productId'
  }
]

resource cosmosDBContainers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2020-04-01' = [for cosmosDBContainerDefinition in cosmosDBContainerDefinitions: {
  // parent: cosmosDBDatabase
  name: cosmosDBContainerDefinition.name
  properties: {
    resource: {
      id: cosmosDBContainerDefinition.name
      partitionKey: {
        kind: 'Hash'
        paths: [
          cosmosDBContainerDefinition.partitionKey
        ]
      }
    }
    options: {}
  }
}]

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageAccountName
  location: 'eastus'
  tags: {
    CostCenter: 'Marketing'
    DataClassification: 'Public'
    Owner: 'WebsiteTeam'
    Environment: 'Production'
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }

  resource blobServices 'blobServices' existing = {
    name: 'default'
  }
}

resource container1 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  parent: storageAccount::blobServices
  name: container1Name
}

resource sqlserver 'Microsoft.Sql/servers@2019-06-01-preview' = {
  name: sqlserverName
  location: location
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorLoginPassword
    version: '12.0'
  }
}

var databaseName = 'ToyCompanyWebsite'
resource sqlserverName_databaseName 'Microsoft.Sql/servers/databases@2020-08-01-preview' = {
  name: '${sqlserver.name}/${databaseName}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 1073741824
  }
}

resource sqlserverName_AllowAllAzureIPs 'Microsoft.Sql/servers/firewallRules@2014-04-01' = {
  name: '${sqlserver.name}/AllowAllAzureIPs'
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
  dependsOn: [
    sqlserver
  ]
}


resource productmanuals 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccount.name}/default/${productmanualsName}'
}
resource hostingPlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: skuName
    capacity: skuCapacity
  }
}

resource webSite 'Microsoft.Web/sites@2020-06-01' = {
  name: webSiteName
  location: location
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: AppInsights_webSiteName.properties.InstrumentationKey
        }
        {
          name: 'StorageAccountConnectionString'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value}'
        }
      ]
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${msi.id}': {}
    }
  }
}

// We don't need this anymore. We use a managed identity to access the database instead.
//resource webSiteConnectionStrings 'Microsoft.Web/sites/config@2020-06-01' = {
//  name: '${webSite.name}/connectionstrings'
//  properties: {
//    DefaultConnection: {
//      value: 'Data Source=tcp:${sqlserver.properties.fullyQualifiedDomainName},1433;Initial Catalog=${databaseName};User Id=${sqlAdministratorLogin}@${sqlserver.properties.fullyQualifiedDomainName};Password=${sqlAdministratorLoginPassword};'
//      type: 'SQLAzure'
//    }
//  }
//}

resource msi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

resource roleassignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(roleDefinitionId, resourceGroup().id)

  properties: {
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: msi.properties.principalId
    description: 'Contributor access on the storage account is required to enable the application to create blob containers and upload blobs.'
  }
}

resource AppInsights_webSiteName 'Microsoft.Insights/components@2018-05-01-preview' = {
  name: 'AppInsights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}
