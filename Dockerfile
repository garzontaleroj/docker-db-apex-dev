FROM oraclelinux:7.9

LABEL maintainer="Juan Pablo Garzon Talero <garzontaleroj@gmail.com>"

RUN yum install -y wget shadow-utils tar gzip unzip hostname && \
    mkdir -p /files && \
    wget -O /usr/local/bin/gosu https://github.com/tianon/gosu/releases/download/1.14/gosu-amd64 && \
    chmod +x /usr/local/bin/gosu && \
    cp /usr/local/bin/gosu /files/gosu-amd64 && \
    yum clean all && rm -rf /var/cache/yum

# copiar scripts y archivos
ADD scripts /scripts/
ADD files /files/
RUN chmod +x /scripts/*.sh

# Instalar JDK 17
RUN mkdir -p /opt/java && \
    tar -xzf /files/OpenJDK17U-jdk_x64_linux_hotspot_17.0.18_8.tar.gz -C /opt/java --strip-components=1 && \
    /opt/java/bin/java -version

ENV JAVA_HOME=/opt/java
ENV PATH="/usr/local/bin:$JAVA_HOME/bin:${PATH}"

# validación rápida
RUN gosu --version

# environment variables
ENV INSTALL_APEX=true \
    INSTALL_SQLCL=true \
    INSTALL_SQLDEVWEB=true \
    INSTALL_LOGGER=true \
    INSTALL_OOSUTILS=true \
    INSTALL_AOP=true \
    INSTALL_AME=true \
    INSTALL_SWAGGER=true \
    INSTALL_CA_CERTS_WALLET=true \
    DBCA_TOTAL_MEMORY=2048 \
    ORACLE_SID=orcl \
    SERVICE_NAME=orcl \
    DB_INSTALL_VERSION=19 \
    ORACLE_BASE=/u01/app/oracle \
    ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome \
    ORACLE_HOME12=/u01/app/oracle/product/12.2.0.1/dbhome \
    ORACLE_HOME18=/u01/app/oracle/product/18.0.0/dbhome \
    ORACLE_HOME19=/u01/app/oracle/product/19.0.0/dbhome \
    ORACLE_INVENTORY=/u01/app/oraInventory \
    PASS=oracle \
    ORDS_HOME=/u01/ords \
    ORDS_CONFIG=/u01/ords/config \
    TOMCAT_HOME=/opt/tomcat \
    APEX_PASS=OrclAPEX1999! \
    APEX_ADDITIONAL_LANG= \
    APEX_PATCH_SET_BUNDLE_FILE= \
    TIME_ZONE=UTC

# ejecutar instalación principal
RUN /scripts/install_main.sh

EXPOSE 22 1521 8080
VOLUME ["${ORACLE_BASE}"]
ENTRYPOINT ["/scripts/entrypoint.sh"]
