FROM node:22-alpine
WORKDIR /worker
COPY node/worker.mjs /worker/worker.mjs
COPY fixtures/catalog.json /worker/catalog.json
USER 65534:65534
ENTRYPOINT ["node", "/worker/worker.mjs"]
