# Workload Identity: Python app on AKS reads Azure Key Vault

A Python pod on Azure Kubernetes Service (AKS) reads a secret from Azure Key Vault using
[Microsoft Entra Workload ID](https://learn.microsoft.com/azure/aks/workload-identity-overview).
The cluster, the pod and the image hold no keys, passwords or connection strings.

## Quick start

```bash
./deploy.sh    # ~10 minutes. Creates rg-workload-identity-python and runs the pod.
./destroy.sh   # Deletes the resource group, purges the Key Vault, removes the kubectl context.
```

You need the Azure CLI (signed in with `az login`) and `kubectl`. [Azure Cloud Shell](https://shell.azure.com)
has both. Set `LOCATION`, `RESOURCE_GROUP` or `NODE_VM_SIZE` to override the defaults, for example
`LOCATION=westeurope ./deploy.sh`.

At the end, `deploy.sh` prints the secret the pod read:

```text
Secret value: Hello from Azure Key Vault!
```

## What gets deployed

| Resource | Purpose |
| --- | --- |
| AKS cluster `aks-wi-demo` | OIDC issuer and workload identity enabled; 1 node, Free tier. |
| Azure Container Registry | Hosts the `wi-kv-test:1.0` image. It's built with `az acr build`, so you don't need Docker. The AKS kubelet identity gets `AcrPull`. |
| Key Vault (RBAC mode) | Holds the secret `demo-secret`. |
| User-assigned managed identity `id-wi-demo` | Gets `Key Vault Secrets User` on that one secret only. |
| Federated identity credential | Trusts tokens that the cluster issues to the `default/wi-demo-sa` service account. |

[`infra/main.bicep`](infra/main.bicep) defines the Azure resources. [`k8s/`](k8s) holds the service
account and pod, and [`src/`](src) the app.

## How it works

1. **OIDC issuer.** AKS publishes an OpenID Connect discovery document and signing keys. Microsoft Entra ID
   uses them to validate tokens that the cluster issues to Kubernetes service accounts.
2. **Federation.** The managed identity has a federated identity credential. It says, in effect: "trust tokens
   from this cluster's issuer whose subject is `system:serviceaccount:default:wi-demo-sa`."
3. **Service account.** [`wi-sa.yaml`](k8s/wi-sa.yaml) annotates `wi-demo-sa` with the managed identity's
   client ID (`azure.workload.identity/client-id`).
4. **Pod.** [`wi-pod.yaml`](k8s/wi-pod.yaml) uses that service account and carries the label
   `azure.workload.identity/use: "true"`. The workload identity webhook then injects a projected service
   account token plus `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_FEDERATED_TOKEN_FILE`.
5. **App.** [`app.py`](src/app.py) uses `DefaultAzureCredential`, which exchanges the Kubernetes token for a
   Microsoft Entra token and calls Key Vault.

## Explore

```bash
kubectl logs -f wi-kv-test                            # The app reads the secret every minute.
kubectl describe pod wi-kv-test | grep AZURE_         # Variables injected by the webhook.
kubectl get serviceaccount wi-demo-sa -o yaml         # The client-id annotation.
az identity federated-credential list --identity-name id-wi-demo -g rg-workload-identity-python -o table
```

## Clean up

```bash
./destroy.sh          # Asks for confirmation. Use --yes to skip the prompt.
```

`destroy.sh` deletes only the resource group that `deploy.sh` created (tagged `azure-demos=workload-identity-python`).
It also purges the soft-deleted Key Vault so you can redeploy right away.

## Troubleshooting

- **`AADSTS70021: No matching federated identity record found`** or **`403`** in the pod logs right after the
  deployment. New federated credentials and role assignments can take a minute or two to propagate. The app
  keeps retrying.
- **Python app fails with `ImportError: cannot import name 'DefaultAzureCredential' from partially initialized
  module`**. This happens when the app file is named `secrets.py`, which shadows the standard library
  `secrets` module that MSAL imports. That's why the app is named `app.py`.
