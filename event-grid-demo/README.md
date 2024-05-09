# EventGridDemo

## Overview
`EventGridDemo` is a basic C# console app that demonstrates how to publish events to Azure Event Grid using the Azure SDK for .NET for a customer demo. This will also include Bicep files to provision necessary Azure resources.

## Prerequisites
- .NET 6.0 SDK or later
- Azure CLI
- Azure subscription

## Project Structure
- `src/`: Contains the source code for the application.
  - `EventGridDemo/`: Main project folder with C# files.
- `infra/`: Contains Bicep files for Azure resource provisioning.

## Setup
1. Clone the repository:
   ```bash
   git clone <repository-url>
   ```
2. Navigate to the project directory:
   ```bash
   cd EventGridDemo
   ```
3. Restore dependencies:
   ```bash
   dotnet restore
   ```

## Deploy Azure Resources
1. Login to Azure:
   ```bash
   az login
   ```
2. Deploy resources using Bicep:
   ```bash
   az deployment group create --resource-group <your-resource-group> --template-file ./infra/main.bicep
   ```

## Running the Application
1. Navigate to the `src/EventGridDemo` directory:
   ```bash
   cd src/EventGridDemo
   ```
2. Run the application:
   ```bash
   dotnet run
   ```