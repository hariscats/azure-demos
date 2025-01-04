import argparse
import sys
import logging
from openai_client import get_explanation

def configure_logging():
    """
    Configures logging for the application.
    """
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

def parse_arguments():
    """
    Parses command-line arguments and returns them.
    """
    parser = argparse.ArgumentParser(
        description="Generate detailed step-by-step explanations from Azure documentation using Azure OpenAI."
    )
    parser.add_argument(
        "text",
        type=str,
        help="Text of the documentation to explain."
    )
    parser.add_argument(
        "--criteria",
        type=str,
        default="",
        help="Specific criteria or focus areas for the explanation."
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.7,
        help="Controls the randomness of the generated text (0.0-1.0)."
    )
    parser.add_argument(
        "--max_tokens",
        type=int,
        default=500,
        help="Maximum number of tokens to generate in the explanation."
    )
    return parser.parse_args()

def main():
    """
    Main function that orchestrates the CLI interaction and prints the explanation.
    """
    configure_logging()
    args = parse_arguments()

    # Basic validation on text input
    if not args.text.strip():
        logging.error("No valid text provided for explanation.")
        sys.exit(1)

    # Generate explanation
    logging.info("Requesting explanation from Azure OpenAI...")
    explanation = get_explanation(
        text=args.text,
        criteria=args.criteria,
        temperature=args.temperature,
        max_tokens=args.max_tokens
    )

    # Print result to stdout
    print("Detailed Explanation:\n", explanation)

if __name__ == "__main__":
    main()
