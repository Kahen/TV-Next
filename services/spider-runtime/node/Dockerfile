FROM node:22-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914
WORKDIR /worker
COPY node/worker.mjs /worker/worker.mjs
COPY fixtures/catalog.json /worker/catalog.json
USER 65534:65534
ENTRYPOINT ["node", "/worker/worker.mjs"]
