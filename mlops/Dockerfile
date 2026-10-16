FROM python:3.12-slim

RUN pip install --no-cache-dir --only-binary :all: "mlflow[s3]==3.17.0"

USER 65532:65532

EXPOSE 5000
