import argparse
from openai_client import get_explanation

def main():
    parser = argparse.ArgumentParser(description="Generate detailed step-by-step explanations from Azure documentation using Azure OpenAI.")
    parser.add_argument("text", type=str, help="Text of the documentation to explain.")
    parser.add_argument("--criteria", type=str, default="", help="Specific criteria or focus areas for the explanation.")
    args = parser.parse_args()

    explanation = get_explanation(args.text, args.criteria)
    print("Detailed Explanation:\n", explanation)

if __name__ == "__main__":
    main()
