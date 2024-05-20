FROM --platform=linux/amd64 python:3.10-slim

ENV PYTHONUNBUFFERED=1

RUN mkdir /app
WORKDIR /app
ADD secrets.py /app/
RUN pip install azure-identity azure-keyvault-secrets

CMD ["python", "/app/secrets.py"]