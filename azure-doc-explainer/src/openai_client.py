import os
from openai import AzureOpenAI

def setup_client():
    client = AzureOpenAI(
        api_key=os.getenv("AZURE_OPENAI_API_KEY"),
        api_version="2024-02-01",
        azure_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT")
    )
    return client

def get_explanation(text, criteria, deployment_name="gpt35", max_tokens=500):
    client = setup_client()
    
    # Constructing the prompt
    few_shot_examples = """
Example 1: Describe how Azure Kubernetes Service (AKS) automates the deployment, scaling, and operations of Kubernetes containers.
Step-by-step explanation: AKS simplifies Kubernetes management by automating three key tasks: deployment, scaling, and operations. Firstly, AKS automates the deployment of new containers by managing the Kubernetes cluster's underlying infrastructure, such as virtual machines and networking settings. Secondly, it supports automatic scaling by adjusting the number of active nodes based on the workload needs, thus ensuring optimal resource use and cost efficiency. Lastly, AKS handles day-to-day operations such as upgrades and maintenance, allowing developers to focus on their applications rather than infrastructure management.

Example 2: Explain the process of setting up network policies in Azure Kubernetes Service.
Step-by-step explanation: Setting up network policies in AKS involves several clear steps. Begin by enabling network policy during the AKS cluster creation by selecting a compatible network plugin like Azure CNI or Calico. Once the cluster is set up, define network policy rules that specify allowed communications between different pods within the cluster. These rules are applied by creating a YAML file that outlines the desired policies, and then deploying this file using the kubectl apply command. This configuration helps secure pod-to-pod communications, restricting traffic flow only to authorized services within the cluster.

Example 3: How does AKS integrate with Entra ID for authentication and authorization?
Step-by-step explanation: AKS integration with Entra ID for authentication and authorization is a multi-step process. First, you configure Entra ID as an identity provider by linking it with your AKS cluster during the setup phase. Next, enable role-based access control (RBAC) in AKS to use Azure AD user identities and groups for access control. Assign roles and permissions to Azure AD users and groups that dictate what actions they can perform within the AKS cluster. This setup not only centralizes user management but also enhances security by ensuring that only authorized users have access to cluster resources.

Example 4: Detail the procedure for upgrading an AKS cluster.
Step-by-step explanation: Upgrading an AKS cluster is critical for security and feature enhancements and involves the following steps: First, check the current version of your AKS cluster and the availability of newer versions using the Azure CLI. Next, plan your upgrade strategy by reviewing the release notes for potential breaking changes and determining the best time to perform the upgrade to minimize disruption. Execute the upgrade using the Azure CLI command `az aks upgrade` specifying your cluster name and the desired Kubernetes version. Finally, after the upgrade, verify the cluster's health and functionality to ensure that applications are running as expected without issues.

"""
    prompt = f"{few_shot_examples}\n\nDocument: {text}\nCriteria: {criteria}\nProvide a detailed step-by-step explanation:"
    
    print('Sending a request for detailed explanation...')
    try:
        response = client.completions.create(
            model=deployment_name,
            prompt=prompt,
            max_tokens=max_tokens
        )
        return response.choices[0].text.strip()
    except Exception as e:
        return f"An error occurred: {str(e)}"
