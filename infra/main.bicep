// main.bicep - ZavaStorefront Azure infrastructure
// Scope: subscription (creates resource group + all resources)
targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (used to generate unique names).')
param environmentName string

@description('Azure region for all resources.')
param location string = 'westus3'

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------
var resourceToken = uniqueString(subscription().id, location, environmentName)
var tags = {
  'azd-env-name': environmentName
}

// ---------------------------------------------------------------------------
// Resource Group
// ---------------------------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

// ---------------------------------------------------------------------------
// Module: Core infrastructure
// ---------------------------------------------------------------------------
module core './core.bicep' = {
  name: 'core'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output RESOURCE_GROUP_ID string = rg.id
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = core.outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT
output AZURE_CONTAINER_REGISTRY_NAME string = core.outputs.AZURE_CONTAINER_REGISTRY_NAME
output WEB_APP_NAME string = core.outputs.WEB_APP_NAME
output WEB_APP_URL string = core.outputs.WEB_APP_URL
output APPLICATIONINSIGHTS_CONNECTION_STRING string = core.outputs.APPLICATIONINSIGHTS_CONNECTION_STRING
output AZURE_AI_FOUNDRY_HUB_NAME string = core.outputs.AZURE_AI_FOUNDRY_HUB_NAME
output AZURE_AI_FOUNDRY_PROJECT_NAME string = core.outputs.AZURE_AI_FOUNDRY_PROJECT_NAME
