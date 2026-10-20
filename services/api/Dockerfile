FROM gradle:8.14.3-jdk21 AS build
WORKDIR /src
COPY . .
RUN gradle bootJar --no-daemon

FROM eclipse-temurin:21-jre
WORKDIR /app
RUN useradd --system --uid 10001 tvnext
COPY --from=build /src/build/libs/*.jar /app/api.jar
USER 10001
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/api.jar"]
