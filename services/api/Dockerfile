FROM gradle:8.14.3-jdk21@sha256:21bd311ed01360c189b8870c6b6e988199ff10f72d445d02fb39d3cff9da91d7 AS build
WORKDIR /src
COPY . .
ARG TVNEXT_RELEASE_VERSION=0.1.0-SNAPSHOT
RUN gradle bootJar --no-daemon "-PreleaseVersion=${TVNEXT_RELEASE_VERSION}"

FROM eclipse-temurin:21-jre@sha256:f37956012e0cb88400e5b3689aeae2d2d735364c1922ae2225536163b5a99f56
WORKDIR /app
RUN useradd --system --uid 10001 tvnext && mkdir /data && chown tvnext /data
COPY --from=build /src/build/libs/*.jar /app/api.jar
USER 10001
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/api.jar"]
