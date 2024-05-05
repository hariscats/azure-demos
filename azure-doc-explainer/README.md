#### Overview
This CLI tool generates detailed explanations for Azure Kubernetes Service (AKS) operations using Azure OpenAI.

#### Prerequisites
- Python 3.6+
- Azure OpenAI access

#### Setup
1. Set environment variables:
   - `AZURE_OPENAI_API_KEY`
   - `AZURE_OPENAI_ENDPOINT`
2. Install dependencies: `pip install -r requirements.txt`

#### Usage
Run the tool with a question and optional criteria:
```bash
python src/main.py "your AKS question" --criteria "specific focus"
```

#### Example
```bash
python src/main.py "Explain AKS scaling" --criteria "performance"
```