# ---------- Stage 1: build ----------
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /app
# Cache dependencies first
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
# Then build
COPY src ./src
RUN mvn -B clean package -DskipTests -Dspring-javaformat.skip=true

# ---------- Stage 2: runtime ----------
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
# Actuator health/metrics are enabled via k8s env (SPRING_APPLICATION_JSON).
ENTRYPOINT ["java", "-jar", "app.jar"]
