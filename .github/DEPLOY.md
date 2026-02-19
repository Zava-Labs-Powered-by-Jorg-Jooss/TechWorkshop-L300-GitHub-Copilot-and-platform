# Deployment Workflow Setup

The [deploy.yml](workflows/deploy.yml) workflow builds and pushes a container image
using **ACR Tasks** (no local Docker required) and deploys it to App Service on every push
to `main`.

Authentication uses **OIDC federated credentials** — no long-lived passwords are stored in GitHub.

---

## 1. Create an Azure AD app registration with federated credentials

```bash
# Create the app registration
az ad app create --display-name "ZavaStorefront GitHub Actions"

# Note the appId from the output, then create a service principal
az ad sp create --id <appId>

# Add a federated credential (replace <org> and <repo>)
az ad app federated-credential create \
  --id <appId> \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<org>/<repo>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

---

## 2. Assign the required Azure roles

Use the `objectId` of the service principal (not the `appId`):

```bash
SP_OBJECT_ID=$(az ad sp show --id <appId> --query id -o tsv)
SUBSCRIPTION_ID=<your-subscription-id>
RESOURCE_GROUP=rg-dev

# ACR — push images
ACR_ID=$(az acr show -n <registryName> -g $RESOURCE_GROUP --query id -o tsv)
az role assignment create --assignee-object-id $SP_OBJECT_ID \
  --role AcrPush --scope $ACR_ID --assignee-principal-type ServicePrincipal

# App Service — update container settings
WEBAPP_ID=$(az webapp show -n <appName> -g $RESOURCE_GROUP --query id -o tsv)
az role assignment create --assignee-object-id $SP_OBJECT_ID \
  --role "Website Contributor" --scope $WEBAPP_ID \
  --assignee-principal-type ServicePrincipal
```

---

## 3. Configure GitHub Secrets

In your repository go to **Settings → Secrets and variables → Actions → Secrets**
and add:

| Secret | Value |
|--------|-------|
| `AZURE_CLIENT_ID` | App registration `appId` |
| `AZURE_TENANT_ID` | Your Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Your Azure subscription ID |

---

## 4. Configure GitHub Variables

In **Settings → Secrets and variables → Actions → Variables** add:

| Variable | Value | Where to find it |
|----------|-------|-----------------|
| `AZURE_CONTAINER_REGISTRY_NAME` | ACR name (without `.azurecr.io`) | `az acr list -g rg-dev --query "[].name" -o tsv` |
| `AZURE_APP_SERVICE_NAME` | Web app name | `azd env get-values \| grep WEB_APP_NAME` |
| `AZURE_RESOURCE_GROUP` | `rg-dev` | Fixed from Bicep |
