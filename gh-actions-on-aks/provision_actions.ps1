# Define variables for the first Helm installation
$NAMESPACE1 = "arc-systems"
$HELM_RELEASE1 = "arc"
$HELM_CHART1_URL = "oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller"

# Define variables for the second Helm installation
$NAMESPACE2 = "arc-runners"
$INSTALLATION_NAME = "arc-runner-set"
$GITHUB_CONFIG_URL = "https://github.com/hariscats/azure-demos"  # Replace with your GitHub repository URL
$HELM_CHART2_URL = "oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set"
$SERVICE_ACCOUNT_NAME = "gha-rs-controller"

# Prompt user to enter the GitHub PAT securely
$GITHUB_PAT = Read-Host -Prompt "Enter your GitHub Personal Access Token" -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($GITHUB_PAT)
$GITHUB_PAT_PLAIN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

# Write the values file for the second installation
$valuesFileContent = @"
githubConfigUrl: "$GITHUB_CONFIG_URL"
githubConfigSecret:
  github_token: "$GITHUB_PAT_PLAIN"
controllerServiceAccount:
  name: "$SERVICE_ACCOUNT_NAME"
  namespace: "$NAMESPACE2"
"@

# Write the content to a values.yaml file
$valuesFilePath = "values.yaml"
$valuesFileContent | Out-File -FilePath $valuesFilePath -Encoding utf8

# Function to check if Kubernetes namespace exists
function Test-NamespaceExists {
    param (
        [string]$Namespace
    )
    $namespaceExists = kubectl get namespace $Namespace -o jsonpath='{.metadata.name}' 2>$null
    return [string]::IsNullOrEmpty($namespaceExists) -eq $false
}

# Function to check if Helm is installed
function Test-HelmInstalled {
    try {
        helm version -c | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Function to check if kubectl is installed
function Test-KubectlInstalled {
    try {
        kubectl version --client | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Check if kubectl is installed
if (-not (Test-KubectlInstalled)) {
    Write-Host "kubectl is not installed. Please install kubectl to proceed." -ForegroundColor Red
    exit 1
}

# Check if Helm is installed
if (-not (Test-HelmInstalled)) {
    Write-Host "Helm is not installed. Please install Helm to proceed." -ForegroundColor Red
    exit 1
}

# Create the first namespace if it does not exist
if (-not (Test-NamespaceExists -Namespace $NAMESPACE1)) {
    Write-Host "Creating namespace '$NAMESPACE1'..."
    kubectl create namespace $NAMESPACE1
} else {
    Write-Host "Namespace '$NAMESPACE1' already exists."
}

# Install the first Helm chart
Write-Host "Installing Helm release '$HELM_RELEASE1' in namespace '$NAMESPACE1'..."
helm install $HELM_RELEASE1 `
    --namespace "$NAMESPACE1" `
    --create-namespace `
    $HELM_CHART1_URL

# Sleep for a few seconds to allow the first deployment to initialize
Start-Sleep -Seconds 10

# Create the second namespace if it does not exist
if (-not (Test-NamespaceExists -Namespace $NAMESPACE2)) {
    Write-Host "Creating namespace '$NAMESPACE2'..."
    kubectl create namespace $NAMESPACE2
} else {
    Write-Host "Namespace '$NAMESPACE2' already exists."
}

# Install the second Helm chart
Write-Host "Installing Helm release '$INSTALLATION_NAME' in namespace '$NAMESPACE2'..."
helm install $INSTALLATION_NAME `
    --namespace "$NAMESPACE2" `
    --create-namespace `
    --set githubConfigUrl="$GITHUB_CONFIG_URL" `
    --set githubConfigSecret.github_token="$GITHUB_PAT_PLAIN" `
    --set controllerServiceAccount.name="$SERVICE_ACCOUNT_NAME" `
    --set controllerServiceAccount.namespace="$NAMESPACE2" `
    $HELM_CHART2_URL

# Sleep for a few seconds to allow the second deployment to initialize
Start-Sleep -Seconds 10

# Verify the second installation
Write-Host "Verifying the installation of GitHub Actions Runner Controller..."

# Function to check the status of the controller pod
function Check-ControllerPodStatus {
    param (
        [string]$Namespace,
        [string]$LabelSelector
    )

    try {
        $podStatus = kubectl get pods --namespace $Namespace -l $LabelSelector -o jsonpath='{.items[0].status.phase}'
        return $podStatus
    } catch {
        return $null
    }
}

# Retry logic to check the status of the controller pod
$maxRetries = 10
$retryInterval = 15
$retryCount = 0
$controllerPodStatus = $null
$labelSelector = "app.kubernetes.io/name=gha-runner-scale-set-controller"

while ($retryCount -lt $maxRetries -and -not $controllerPodStatus) {
    $controllerPodStatus = Check-ControllerPodStatus -Namespace $NAMESPACE2 -LabelSelector $labelSelector
    if ($controllerPodStatus) {
        break
    }
    Write-Host "Controller pod not found yet. Retrying in $retryInterval seconds..."
    Start-Sleep -Seconds $retryInterval
    $retryCount++
}

if ($controllerPodStatus -eq "Running") {
    Write-Host "GitHub Actions Runner Controller pod is running." -ForegroundColor Green
} else {
    Write-Host "GitHub Actions Runner Controller pod is not running. Please check the pod status." -ForegroundColor Red
    kubectl get pods --namespace $NAMESPACE2
    exit 1
}

Write-Host "GitHub Actions Runner Controller has been installed and verified successfully." -ForegroundColor Green
