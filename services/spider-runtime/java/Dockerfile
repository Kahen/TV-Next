FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /build
COPY java/Json.java java/Worker.java ./
RUN javac --release 21 -encoding UTF-8 -d /build/classes Json.java Worker.java

FROM eclipse-temurin:21-jre-alpine
WORKDIR /worker
COPY --from=builder /build/classes /worker/classes
COPY fixtures/catalog.json /worker/catalog.json
USER 65534:65534
ENTRYPOINT ["java", "-Xmx48m", "-XX:MaxMetaspaceSize=40m", "-XX:ReservedCodeCacheSize=16m", "-XX:+UseSerialGC", "-cp", "/worker/classes", "Worker"]
