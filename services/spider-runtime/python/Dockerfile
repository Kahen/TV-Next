FROM python:3.12-alpine@sha256:5789aa194f757888f41fa3d48e14b6feaa1b57c0af0b56fcb1372d6474d3bff0
WORKDIR /worker
COPY python/worker.py /worker/worker.py
COPY fixtures/catalog.json /worker/catalog.json
USER 65534:65534
ENTRYPOINT ["python3", "-I", "/worker/worker.py"]
