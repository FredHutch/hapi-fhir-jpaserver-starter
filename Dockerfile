FROM tomcat:9.0-jdk8

# Remove the default ROOT application
RUN rm -rf /usr/local/tomcat/webapps/ROOT

# Copy the renamed WAR file to the webapps directory
COPY ROOT.war /usr/local/tomcat/webapps/

EXPOSE 8080

CMD ["catalina.sh", "run"]
