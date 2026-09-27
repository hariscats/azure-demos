"""Reads a Key Vault secret with Microsoft Entra Workload ID.

The workload identity webhook injects AZURE_CLIENT_ID, AZURE_TENANT_ID and
AZURE_FEDERATED_TOKEN_FILE into the pod, and DefaultAzureCredential exchanges
the pod's Kubernetes service account token for a Microsoft Entra token.
No secrets or keys are stored in the cluster or the image.

Note: this file must not be named secrets.py, because that would shadow the
standard library `secrets` module that azure-identity (MSAL) imports.
"""

import os
import time

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient


def main() -> None:
    vault_url = os.environ["KEY_VAULT_URL"]
    secret_name = os.environ["SECRET_NAME"]
    client = SecretClient(vault_url=vault_url, credential=DefaultAzureCredential())

    while True:
        print(f"Retrieving secret '{secret_name}' from {vault_url}")
        try:
            secret = client.get_secret(secret_name)
        except Exception as exc:  # pylint: disable=broad-exception-caught
            # New role assignments and federated credentials can take a minute to propagate.
            print(f"Couldn't read the secret yet, retrying in 10 seconds: {exc}")
            time.sleep(10)
            continue
        print(f"Secret value: {secret.value}")
        time.sleep(60)


if __name__ == "__main__":
    main()
