## Overview
`failover.py` is a Python script designed to automate the failover process between a primary and a secondary Azure Event Hub namespace. It ensures high availability by attempting to send messages to the primary Event Hub and switching to the secondary Event Hub in case of failure. This is for demo purposes.

## Prerequisites
- Python 3.x
- Azure CLI
- Azure Event Hubs namespace and Event Hubs created for both primary and secondary namespaces

## Setup
1. Set the following environment variables with your connection strings and Event Hub name:
   ```bash
   export PRIMARY_EVENT_HUB_CONNECTION_STRING="your-primary-connection-string"
   export SECONDARY_EVENT_HUB_CONNECTION_STRING="your-secondary-connection-string"
   export EVENT_HUB_NAME="your-event-hub-name"
   ```

2. Install required Python packages:
   ```bash
   pip install azure-eventhub
   ```

## Usage
Run the script:
```bash
python failover.py
```

The script will attempt to send an event to the primary Event Hub and will switch to the secondary Event Hub if the primary is unavailable.
