# syntax=docker/dockerfile:1
# Maven corre en la arquitectura del equipo (el .jar no depende de ella); solo el JRE final toma la arquitectura destino.
FROM --platform=$BUILDPLATFORM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY src ./src
RUN mvn -q -B -DskipTests package

FROM eclipse-temurin:25-jre
RUN useradd --system --uid 10001 app
USER app
WORKDIR /app
COPY --from=build /src/target/ingest-ms-*.jar app.jar
EXPOSE 8080
# Heap fijo y G1, como en el servicio de referencia; ajustable por JAVA_OPTS (perfil reducido: -Xmx512m).
ENV JAVA_OPTS="-Xss256k -Xmx512m -Xms512m -XX:+UseG1GC"
ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar app.jar"]
