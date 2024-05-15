# Variables
RESOURCE_GROUP="myEventHubResourceGroup"
LOCATION="eastus"
PRIMARY_NAMESPACE="primaryEventHubNamespace"
SECONDARY_NAMESPACE="secondaryEventHubNamespace"
EVENT_HUB_NAME="myEventHub"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create primary Event Hub namespace
az eventhubs namespace create --name $PRIMARY_NAMESPACE --resource-group $RESOURCE_GROUP --location $LOCATION --sku Standard

# Create secondary Event Hub namespace
az eventhubs namespace create --name $SECONDARY_NAMESPACE --resource-group $RESOURCE_GROUP --location $LOCATION --sku Standard

# Create Event Hub in primary namespace
az eventhubs eventhub create --name $EVENT_HUB_NAME --namespace-name $PRIMARY_NAMESPACE --resource-group $RESOURCE_GROUP --partition-count 2

# Create Event Hub in secondary namespace
az eventhubs eventhub create --name $EVENT_HUB_NAME --namespace-name $SECONDARY_NAMESPACE --resource-group $RESOURCE_GROUP --partition-count 2

# Retrieve connection strings for the namespaces
PRIMARY_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list --resource-group $RESOURCE_GROUP --namespace-name $PRIMARY_NAMESPACE --name RootManageSharedAccessKey --query primaryConnectionString --output tsv)
SECONDARY_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list --resource-group $RESOURCE_GROUP --namespace-name $SECONDARY_NAMESPACE --name RootManageSharedAccessKey --query primaryConnectionString --output tsv)

# Output the connection strings (for use in the Python script)
echo "Primary Event Hub Connection String: $PRIMARY_CONNECTION_STRING"
echo "Secondary Event Hub Connection String: $SECONDARY_CONNECTION_STRING"
