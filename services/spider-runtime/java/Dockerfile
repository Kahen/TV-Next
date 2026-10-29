FROM eclipse-temurin:21-jdk-alpine@sha256:fd52084c35bbac78890d95d57707d31ffc9d7a3324199e89c06be2a9dc71bfa0 AS builder
WORKDIR /build
COPY java/Json.java java/Worker.java java/ProviderSpi.java java/ProviderFailure.java java/BundledFixtureProvider.java ./
RUN javac --release 21 -encoding UTF-8 -d /build/classes Json.java Worker.java ProviderSpi.java ProviderFailure.java BundledFixtureProvider.java \
    && jar --create --file /build/tvnext-fixture.jar --main-class Worker -C /build/classes .

FROM eclipse-temurin:21-jre-alpine@sha256:b48e02e0ea88d7bfb305335df94923bdef394905f4147dccd52e873cf17b1088
WORKDIR /worker
COPY --from=builder /build/tvnext-fixture.jar /worker/tvnext-fixture.jar
COPY fixtures/catalog.json /worker/catalog.json
USER 65534:65534
ENTRYPOINT ["java", "-Xmx48m", "-XX:MaxMetaspaceSize=40m", "-XX:ReservedCodeCacheSize=16m", "-XX:+UseSerialGC", "-jar", "/worker/tvnext-fixture.jar"]
