# Install GitHub Actions Runner Controller on AKS

This PowerShell script installs the GitHub Actions Runner Controller on Azure Kubernetes Service (AKS). The script creates the necessary namespaces, configures the GitHub Actions Runner, and verifies the deployment.

## Prerequisites

Before running the script, ensure you have the following prerequisites:

- **Azure CLI**: Installed and configured on your local machine.
- **Kubectl**: Installed and configured to manage your AKS cluster.
- **Helm**: Installed and configured on your local machine.
- **GitHub Personal Access Token (PAT)**: Generate a PAT with appropriate permissions to access your GitHub repository.

## Script Overview

The script performs the following tasks:

1. Creates the `arc-systems` namespace and installs the GitHub Actions Runner Controller using Helm.
2. Creates the `arc-runners` namespace and installs the GitHub Actions Runner using Helm, configured with your GitHub repository details and PAT.
3. Verifies the installation and ensures the runner is properly configured and running.

## Usage

1. **Download the Script**: Save the script to a file named `install-helm.ps1`.

2. **Run the Script**: Open a PowerShell terminal and execute the script.

```powershell
.\provision_actions.ps1
```

## Script Details

### Script Variables

- `$NAMESPACE1`: The namespace for the GitHub Actions Runner Controller (default: `arc-systems`).
- `$HELM_RELEASE_NAME`: The name of the Helm release for both installations (default: `arc`).
- `$HELM_CHART1_URL`: The URL of the Helm chart for the GitHub Actions Runner Controller.
- `$NAMESPACE2`: The namespace for the GitHub Actions Runner (default: `arc-runners`).
- `$GITHUB_CONFIG_URL`: The URL of your GitHub repository.
- `$HELM_CHART2_URL`: The URL of the Helm chart for the GitHub Actions Runner.
- `$SERVICE_ACCOUNT_NAME`: The service account name for the GitHub Actions Runner (default: `gha-rs-controller`).

