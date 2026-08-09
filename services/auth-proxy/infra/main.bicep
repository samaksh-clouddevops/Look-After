@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name used for resource naming')
param namePrefix string = 'lookafter'

@description('Container image (Docker Hub private repo)')
param containerImage string

@description('Firebase project ID')
param firebaseProjectId string = 'lifeos-dummy'

@description('Min replicas (0 = scale to zero / free-grant friendly)')
param minReplicas int = 0

@description('Max replicas')
param maxReplicas int = 3

@description('Local-only dev auth (Bearer dev:<uid>). Never enable in production.')
param allowInsecureDevAuth bool = false

@description('Docker Hub username for pulling a private image')
param dockerHubUsername string = ''

@secure()
@description('Docker Hub access token for pulling a private image')
param dockerHubPassword string = ''

var uniqueSuffix = uniqueString(resourceGroup().id)
var useDockerHubRegistry = !empty(dockerHubUsername) && !empty(dockerHubPassword)
var envName = '${namePrefix}-env-${uniqueSuffix}'
var appName = '${namePrefix}-auth-${uniqueSuffix}'

// Consumption environment only — no Log Analytics workspace.
resource containerEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  properties: {
    zoneRedundant: false
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: useDockerHubRegistry
        ? [
            {
              server: 'index.docker.io'
              username: dockerHubUsername
              passwordSecretRef: 'dockerhub-password'
            }
          ]
        : []
      secrets: concat(
        [
          {
            name: 'admin-api-key'
            value: 'bootstrap-admin-replace-me'
          }
          {
            name: 'glm-api-key'
            value: 'bootstrap-glm-replace-me'
          }
          {
            name: 'openai-api-key'
            value: 'bootstrap-openai-replace-me'
          }
          {
            name: 'firebase-sa'
            value: '{"type":"service_account","project_id":"${firebaseProjectId}"}'
          }
          {
            name: 'product-keys-json'
            value: '[]'
          }
        ],
        useDockerHubRegistry
          ? [
              {
                name: 'dockerhub-password'
                value: dockerHubPassword
              }
            ]
          : []
      )
    }
    template: {
      containers: [
        {
          name: 'auth-proxy'
          image: containerImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'PORT'
              value: '8080'
            }
            {
              name: 'FIREBASE_PROJECT_ID'
              value: firebaseProjectId
            }
            {
              name: 'DATA_DIR'
              value: '/tmp/lookafter-data'
            }
            {
              name: 'RATE_LIMIT_PER_MINUTE'
              value: '30'
            }
            {
              name: 'DAILY_TOKEN_BUDGET'
              value: '200000'
            }
            {
              name: 'AUTH_DEV_ALLOW_INSECURE'
              value: allowInsecureDevAuth ? 'true' : 'false'
            }
            // Set via Container App secrets (Portal or `az containerapp secret set`):
            //   admin-api-key      → ADMIN_API_KEY
            //   glm-api-key        → GLM_API_KEY
            //   openai-api-key     → OPENAI_API_KEY
            //   firebase-sa        → FIREBASE_SERVICE_ACCOUNT_JSON
            //   product-keys-json  → PRODUCT_KEYS_JSON
            {
              name: 'ADMIN_API_KEY'
              secretRef: 'admin-api-key'
            }
            {
              name: 'GLM_API_KEY'
              secretRef: 'glm-api-key'
            }
            {
              name: 'OPENAI_API_KEY'
              secretRef: 'openai-api-key'
            }
            {
              name: 'FIREBASE_SERVICE_ACCOUNT_JSON'
              secretRef: 'firebase-sa'
            }
            {
              name: 'PRODUCT_KEYS_JSON'
              secretRef: 'product-keys-json'
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppName string = containerApp.name
output containerAppResourceId string = containerApp.id
