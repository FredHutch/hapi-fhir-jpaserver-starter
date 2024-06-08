FROM docker.io/library/maven:3.9.6-eclipse-temurin-17 AS build-hapi


ARG JDBC_URL
ENV JDBC_URL=${JDBC_URL}
ARG DB_USER
ENV DB_USER=${DB_USER}
ARG DB_PASSWORD
ENV DB_PASSWORD=${DB_PASSWORD}


RUN apt-get update -y && apt-get install -y gettext-base

WORKDIR /tmp/hapi-fhir-jpaserver-starter

ARG OPENTELEMETRY_JAVA_AGENT_VERSION=1.33.3
RUN curl -LSsO https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OPENTELEMETRY_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar

COPY pom.xml .
COPY server.xml .
RUN mvn -ntp dependency:go-offline

COPY src/ /tmp/hapi-fhir-jpaserver-starter/src/
RUN cp /tmp/hapi-fhir-jpaserver-starter/src/main/resources/application.yaml /tmp/hapi-fhir-jpaserver-starter/src/main/resources/application.yaml.orig
RUN cat /tmp/hapi-fhir-jpaserver-starter/src/main/resources/application.yaml.orig | envsubst > /tmp/hapi-fhir-jpaserver-starter/src/main/resources/application.yaml
RUN mvn clean install -DskipTests -Djdk.lang.Process.launchMechanism=vfork

FROM build-hapi AS build-distroless
RUN mvn package -DskipTests spring-boot:repackage -Pboot
RUN mkdir /app && cp /tmp/hapi-fhir-jpaserver-starter/target/ROOT.war /app/main.war


########### bitnami tomcat version is suitable for debugging and comes with a shell
########### it can be built using eg. `docker build --target tomcat .`
FROM bitnami/tomcat:10.1 AS tomcat

RUN rm -rf /opt/bitnami/tomcat/webapps/ROOT && \
    mkdir -p /opt/bitnami/hapi/data/hapi/lucenefiles && \
    chmod 775 /opt/bitnami/hapi/data/hapi/lucenefiles

USER root
RUN mkdir -p /target && chown -R 1001:1001 target
USER 1001

COPY --chown=1001:1001 catalina.properties /opt/bitnami/tomcat/conf/catalina.properties
COPY --chown=1001:1001 server.xml /opt/bitnami/tomcat/conf/server.xml
COPY --from=build-hapi --chown=1001:1001 /tmp/hapi-fhir-jpaserver-starter/target/ROOT.war /opt/bitnami/tomcat/webapps/ROOT.war
COPY --from=build-hapi --chown=1001:1001 /tmp/hapi-fhir-jpaserver-starter/opentelemetry-javaagent.jar /app

ENV ALLOW_EMPTY_PASSWORD=yes

########### distroless brings focus on security and runs on plain spring boot - this is the default image
FROM gcr.io/distroless/java17-debian12:nonroot AS default
# 65532 is the nonroot user's uid
# used here instead of the name to allow Kubernetes to easily detect that the container
# is running as a non-root (uid != 0) user.
USER 65532:65532
WORKDIR /app

COPY --chown=nonroot:nonroot --from=build-distroless /app /app
COPY --chown=nonroot:nonroot --from=build-hapi /tmp/hapi-fhir-jpaserver-starter/opentelemetry-javaagent.jar /app

ENTRYPOINT ["java", "--class-path", "/app/main.war", "-Dloader.path=main.war!/WEB-INF/classes/,main.war!/WEB-INF/,/app/extra-classes", "org.springframework.boot.loader.PropertiesLauncher"]
