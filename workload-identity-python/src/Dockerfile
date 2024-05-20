FROM python:3.7

ENV PYTHONUNBUFFERED=1

RUN mkdir /app
WORKDIR /app
ADD secrets.py /app/
RUN pip install azure-identity azure-keyvault-secrets

CMD ["python", "/app/kv_secrets.py"]