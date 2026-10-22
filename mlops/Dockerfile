FROM python:3.12-slim

RUN pip install --no-cache-dir --only-binary :all: "mlflow[s3]==3.17.2" \
    && mkdir -p /mlflow-data /mlflow-artifacts \
    && chown -R 65532:65532 /mlflow-data /mlflow-artifacts

USER 65532:65532

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=3).read()"]
