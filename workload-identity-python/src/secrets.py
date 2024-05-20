import os
import time
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential

keyVaultName = os.environ["KEY_VAULT_NAME"]
secretName = os.environ["SECRET_NAME"]
KVUri = f"https://{keyVaultName}.vault.azure.net"

credential = DefaultAzureCredential()
client = SecretClient(vault_url=KVUri, credential=credential)

while True:
    print(f"Retrieving your secret from {keyVaultName}.")
    retrieved_secret = client.get_secret(secretName)
    print(f"Secret value: {retrieved_secret.value}")
    time.sleep(5)