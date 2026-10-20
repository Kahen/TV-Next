FROM python:3.12-alpine
WORKDIR /worker
COPY python/worker.py /worker/worker.py
COPY fixtures/catalog.json /worker/catalog.json
USER 65534:65534
ENTRYPOINT ["python3", "-I", "/worker/worker.py"]
