#!/bin/bash
# This script deploys resources to set up a Service Bus messaging environment
# Set variables
echo "Set Variables - START"

environment="<ENVIRONMENT_NAME>"     # The name chosen will be used as a prefix for resource names.
location="<LOCATION>"                   # Azure location where resources are to be built.
organizationName="<ORGANIZATION_NAME>"      # Name of organization to be used when setting up the API Management Service.
adminEmail="<ADMIN_EMAIL_ADDRESS>"          # Email address for the administrator of the API Management Service.
storageAccountName="<STORAGE_ACCOUNT_NAME"      # Storage account used by environment applications. Standard storage account naming convention applies.
functionStorageAccountName="svcbusmsgingdev01funcstg"       # Storage account used for Azure Function App. Standard storage account naming convention applies.
serviceBusQueueName="<QUEUE_NAME>"      # Name of queue to be created in the Service Bus namespace.
tags="{'tagName':'tagValue'}"    # Tags to be applied to resources.  Replace with tag Name and Value of our choice.

resourceGroupName="$environment-rg"
tenantId="$(az account show --query tenantId -o tsv)"
currentUserObjectId=$(az ad signed-in-user show --query objectId -o tsv)
currentSubscriptionId=$(az account show --query id -o tsv)
echo "Set Variables - END"

echo "Create Resource Group - START"
az group create --name $resourceGroupName --location $location
echo "Create Resource Group - END"

echo "Log Analytics Workspace - START"
# Log Analytics Workspace
logAnalyticsWorkspaceName="$environment-logwkspc"
workspaceResourceId=$(az deployment group create \
    --resource-group $resourceGroupName \
    --name log-analystics-workspace \
    --template-file ../templates/log-analytics-workspace/log-analytics-workspace.deploy.json \
    --parameters @../templates/log-analytics-workspace/log-analytics-workspace.parameters.json \
    --parameters name=$logAnalyticsWorkspaceName location=$location tags=$tags --query properties.outputResources[0].id -o tsv)

echo "Log Analytics Workspace - END"

echo "Application Insights - START"
# Application Insights
appInsightsId=$(az deployment group create \
    --resource-group $resourceGroupName \
    --name application-insight \
    --template-file ../templates/application-insights/application-insight.deploy.json \
    --parameters @../templates/application-insights/application-insight.parameters.json \
    --parameters name="$environment-appinsights" regionId=$location tagsArray=$tags \
        logAnalyticsWorkspaceName=$logAnalyticsWorkspaceName --query id -o tsv)

echo "Application Insights - END"

echo "Key Vault - START"
# Key Vault
az deployment group create \
    --resource-group $resourceGroupName \
    --name key-vault \
    --template-file ../templates/key-vault/key-vault.deploy.json \
    --parameters @../templates/key-vault/key-vault.parameters.json \
    --parameters name="$environment-kv" location=$location tags=$tags \
        tenantId=$tenantId currentUserObjectId=$currentUserObjectId

echo "Key Vault - END"

echo "Storage Account - START"
# Storage Account
az deployment group create \
    --resource-group $resourceGroupName \
    --name storage-account \
    --template-file ../templates/storage-account/storage-account.deploy.json \
    --parameters @../templates/storage-account/storage-account.parameters.json \
    --parameters storageAccountName=$storageAccountName location=$location tags=$tags

echo "Storage Account - END"

echo "API Management - START"
# API Management
appInsightsObject="{'name':'$environment-appinsights','id':'$appInsightsId'}"
appInsightsInstrumentationKey=$(az resource show -g $resourceGroupName -n "$environment-appinsights" --resource-type "microsoft.insights/components" --query properties.InstrumentationKey)

az deployment group create \
    --resource-group $resourceGroupName \
    --name api-management \
    --template-file ../templates/api-management/api-management.deploy.json \
    --parameters @../templates/api-management/api-management.parameters.json \
    --parameters apimName="$environment-apim" location=$location tagsByResource=$tags \
        organizationName=$organizationName adminEmail=$adminEmail \
        appInsightsObject=$appInsightsObject appInsightsInstrumentationKey=$appInsightsInstrumentationKey 

echo "API Management - END"

echo "Service Bus - START"
# Service Bus namespace and queue(s)
az deployment group create \
    --resource-group $resourceGroupName \
    --name service-bus \
    --template-file ../templates/service-bus/service-bus.deploy.json \
    --parameters @../templates/service-bus/service-bus.parameters.json \
    --parameters serviceBusNamespaceName="$environment-nmspc" location=$location tags=$tags \
        serviceBusQueueName=$serviceBusQueueName

echo "Service Bus - END"

echo "App Service - START"
# App Service Plan and App(s)
az deployment group create \
    --resource-group $resourceGroupName \
    --name app-service \
    --template-file ../templates/app-service/app-service.deploy.json \
    --parameters @../templates/app-service/app-service.parameters.json \
    --parameters name="$environment-apim" location=$location tags=$tags \
        subscriptionId=$currentSubscriptionId \
        hostingPlanName="$environment-appsvcplan" \
        serverFarmResourceGroup=$resourceGroupName

echo "App Service - END"

echo "Azure Function App - START"
# Azure Function App
az deployment group create \
    --resource-group $resourceGroupName \
    --name azure-function \
    --template-file ../templates/azure-function/azure-function.deploy.json \
    --parameters @../templates/azure-function/azure-function.parameters.json \
    --parameters name="$environment-func01" location=$location tags=$tags \
        subscriptionId=$currentSubscriptionId \
        hostingPlanName="$environment-appsvcplan" \
        serverFarmResourceGroup=$resourceGroupName \
        storageAccountName=$functionStorageAccountName

echo "Azure Function App - END"

echo "Environment Setup Complete!"