// core.bicep - All resources scoped to the resource group
targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Azure region for all resources.')
param location string = 'westus3'

@description('Unique string token for resource naming.')
param resourceToken string

// ---------------------------------------------------------------------------
// User-Assigned Managed Identity
// ---------------------------------------------------------------------------
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'azid${resourceToken}'
  location: location
}

// ---------------------------------------------------------------------------
// Log Analytics Workspace
// ---------------------------------------------------------------------------
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'azlaw${resourceToken}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ---------------------------------------------------------------------------
// Application Insights
// ---------------------------------------------------------------------------
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'azai${resourceToken}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ---------------------------------------------------------------------------
// Azure Container Registry
// ---------------------------------------------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'azacr${resourceToken}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// ---------------------------------------------------------------------------
// App Service Plan (Linux)
// ---------------------------------------------------------------------------
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: 'azasp${resourceToken}'
  location: location
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {
    reserved: true   // Required for Linux
  }
}

// ---------------------------------------------------------------------------
// App Service (Web App) — Linux container
// ---------------------------------------------------------------------------
resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: 'azapp${resourceToken}'
  location: location
  tags: {
    'azd-service-name': 'storefront'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acr.properties.loginServer}/zavastorefront:latest'
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: uami.properties.clientId
      cors: {
        allowedOrigins: [ 'https://portal.azure.com' ]
        supportCredentials: false
      }
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: uami.properties.clientId
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${acr.properties.loginServer}'
        }
        {
          name: 'AzureAIFoundry__Endpoint'
          // Deployment name is encoded in the URL for Azure.AI.Inference with Azure OpenAI-style endpoints
          value: '${aiFoundry.properties.endpoint}openai/deployments/phi-4'
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Diagnostic settings for the App Service
// ---------------------------------------------------------------------------
resource webAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'appservice-diagnostics'
  scope: webApp
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// RBAC: AcrPull for the UAMI on ACR (no passwords)
// ---------------------------------------------------------------------------
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, uami.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Azure AI Foundry — Hub (backed by an AI Services account)
// ---------------------------------------------------------------------------
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-09-01' = {
  name: 'azais${resourceToken}'
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    allowProjectManagement: true
    customSubDomainName: 'azais${resourceToken}'
    disableLocalAuth: true        // Disables API key auth; Entra ID is the only supported method
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ---------------------------------------------------------------------------
// Azure AI Foundry Project
// ---------------------------------------------------------------------------
resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-09-01' = {
  parent: aiFoundry
  name: 'azprj${resourceToken}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'ZavaStorefront AI Project'
  }
}

// GPT-4o model deployment (gpt-4 turbo-2024-04-09 deprecated 2025-11-14)
resource gpt4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-09-01' = {
  parent: aiFoundry
  name: 'gpt-4o'
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
  }
}

// Phi-4 model deployment (Microsoft model available in westus3)
resource phi4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-09-01' = {
  parent: aiFoundry
  name: 'phi-4'
  sku: {
    name: 'GlobalStandard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'Microsoft'
      name: 'Phi-4'
      version: '7'
    }
  }
  dependsOn: [
    gpt4Deployment
  ]
}

// ---------------------------------------------------------------------------
// Supporting resources for AI Hub: Key Vault (RBAC auth, public access)
// ---------------------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'azkv${resourceToken}'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
  }
}

// Key Vault Secrets Officer role for UAMI
var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
resource kvSecretsOfficerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, uami.id, kvSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsOfficerRoleId)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// RBAC: Azure AI User for UAMI on AI Foundry (enables token-based auth, no API key)
// ---------------------------------------------------------------------------
var azureAiUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
resource aiFoundryUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundry.id, uami.id, azureAiUserRoleId)
  scope: aiFoundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiUserRoleId)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.properties.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.name
output WEB_APP_NAME string = webApp.name
output WEB_APP_URL string = 'https://${webApp.properties.defaultHostName}'
output APPLICATIONINSIGHTS_CONNECTION_STRING string = appInsights.properties.ConnectionString
output AZURE_AI_FOUNDRY_HUB_NAME string = aiFoundry.name
output AZURE_AI_FOUNDRY_PROJECT_NAME string = aiProject.name
output AZURE_AI_FOUNDRY_HUB_ENDPOINT string = aiFoundry.properties.endpoint
output AZURE_AI_FOUNDRY_PROJECT_ENDPOINT string = aiProject.properties.endpoints['AI Foundry API']
