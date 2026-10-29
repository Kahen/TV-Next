FROM eclipse-temurin:21-jdk-alpine@sha256:fd52084c35bbac78890d95d57707d31ffc9d7a3324199e89c06be2a9dc71bfa0 AS builder
WORKDIR /build
COPY java/Json.java java/ProviderFailure.java jvm-spider/ApprovedSpiderLoader.java jvm-spider/JvmSpiderWorker.java jvm-spider/VerificationSmoke.java ./
COPY jvm-spider/api ./api
COPY jvm-spider/fixtures ./fixtures
RUN mkdir host providers \
    && javac --release 21 -encoding UTF-8 -d host $(find api -name '*.java') Json.java ProviderFailure.java ApprovedSpiderLoader.java JvmSpiderWorker.java VerificationSmoke.java \
    && jar --create --file host.jar --date=2020-01-01T00:00:00Z -C host . \
    && javac --release 21 -encoding UTF-8 -cp host.jar -d providers $(find fixtures -name '*.java') \
    && jar --create --file approved.jar --date=2020-01-01T00:00:00Z -C providers .

FROM python:3.12-alpine@sha256:5789aa194f757888f41fa3d48e14b6feaa1b57c0af0b56fcb1372d6474d3bff0 AS preflight
COPY --from=builder /build/approved.jar /approved.jar
COPY jar_inspect.py jvm-spider/preflight.py /
RUN python /preflight.py

FROM eclipse-temurin:21-jre-alpine@sha256:b48e02e0ea88d7bfb305335df94923bdef394905f4147dccd52e873cf17b1088
WORKDIR /worker
COPY --from=builder /build/host.jar /worker/host.jar
COPY --from=preflight /approved.jar /approved.json /worker/
USER 65534:65534
ENTRYPOINT ["java", "-Xmx48m", "-XX:MaxMetaspaceSize=40m", "-XX:ReservedCodeCacheSize=16m", "-XX:+UseSerialGC", "-cp", "/worker/host.jar", "JvmSpiderWorker"]
