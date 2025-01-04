import os
import logging
from openai import AzureOpenAI

def setup_client():
    """
    Sets up an Azure OpenAI client based on environment variables.

    Returns:
        AzureOpenAI: The configured Azure OpenAI client object.
    """
    api_key = os.getenv("AZURE_OPENAI_API_KEY")
    endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
    api_version = os.getenv("API_VERSION")

    # Basic validation to ensure environment variables are set.
    if not api_key or not endpoint:
        raise EnvironmentError(
            "AZURE_OPENAI_API_KEY and AZURE_OPENAI_ENDPOINT must be set in your environment."
        )

    # Note: Adjust api_version if needed to match the actual supported version in your environment.
    client = AzureOpenAI(
        api_key=api_key,
        api_version=api_version,
        azure_endpoint=endpoint
    )
    return client

def get_explanation(
    text: str,
    criteria: str = "",
    temperature: float = 0.7,
    max_tokens: int = 500,
    deployment_name: str = "gpt-35-turbo"
) -> str:
    """
    Generates a detailed step-by-step explanation of a given document.

    Args:
        text (str): Text of the document to explain.
        criteria (str): Specific criteria or focus areas for the explanation.
        temperature (float): Controls randomness (0.0-1.0). Higher values = more creative output.
        max_tokens (int): Maximum number of tokens in the output.
        deployment_name (str): Name of the Azure OpenAI deployment/model to use.

    Returns:
        str: The generated explanation or an error message if something went wrong.
    """
    client = setup_client()

    # You can store or load these examples from a separate file to keep your code clean.
    few_shot_examples = """
Example 1: Describe how Azure Kubernetes Service (AKS) automates the deployment, scaling, and operations of Kubernetes containers.
Step-by-step explanation: AKS simplifies Kubernetes management by automating three key tasks: deployment, scaling, and operations. Firstly, AKS automates the deployment of new containers by managing the Kubernetes cluster's underlying infrastructure, such as virtual machines and networking settings. Secondly, it supports automatic scaling by adjusting the number of active nodes based on the workload needs, thus ensuring optimal resource use and cost efficiency. Lastly, AKS handles day-to-day operations such as upgrades and maintenance, allowing developers to focus on their applications rather than infrastructure management.

Example 2: Explain the process of setting up network policies in Azure Kubernetes Service.
Step-by-step explanation: Setting up network policies in AKS involves several clear steps. Begin by enabling network policy during the AKS cluster creation by selecting a compatible network plugin like Azure CNI or Calico. Once the cluster is set up, define network policy rules that specify allowed communications between different pods within the cluster. These rules are applied by creating a YAML file that outlines the desired policies, and then deploying this file using the kubectl apply command. This configuration helps secure pod-to-pod communications, restricting traffic flow only to authorized services within the cluster.

Example 3: How does AKS integrate with Entra ID for authentication and authorization?
Step-by-step explanation: AKS integration with Entra ID for authentication and authorization is a multi-step process. First, you configure Entra ID as an identity provider by linking it with your AKS cluster during the setup phase. Next, enable role-based access control (RBAC) in AKS to use Azure AD user identities and groups for access control. Assign roles and permissions to Azure AD users and groups that dictate what actions they can perform within the AKS cluster. This setup not only centralizes user management but also enhances security by ensuring that only authorized users have access to cluster resources.
"""

    prompt = (
        f"{few_shot_examples}\n\n"
        f"Document: {text}\n"
        f"Criteria: {criteria}\n"
        "Provide a detailed step-by-step explanation:"
    )

    logging.info("Sending prompt to Azure OpenAI for explanation...")

    try:
        logging.info("Sending prompt to Azure OpenAI for chat completion...")
        completion = client.chat.completions.create(
        model=deployment_name,
        messages=prompt,
        max_tokens=max_tokens,
        temperature=temperature,
        top_p=0.95,
        frequency_penalty=0,
        presence_penalty=0,
        stop=None,
        stream=False
    )
        return completion.to_json()
    except Exception as e:
        logging.error("An error occurred while generating the chat completion: %s", e)
        return f"An error occurred: {str(e)}"
