#!/bin/bash

echo "--------------------------------------------------"
echo "Environment Vars.................................."

echo "--------------------------------------------------"
echo "Installing JAVA..................................."
/scripts/install_java.sh

echo "--------------------------------------------------"
echo "Validations......................................."
/scripts/validations.sh || exit 1

echo "--------------------------------------------------"
echo "Image Setup......................................."
/scripts/image_setup.sh

echo "--------------------------------------------------"
echo "Installing Oracle Database Software..............."
if [ ${DB_INSTALL_VERSION} == "12" ]; then
    /scripts/install_oracle12ee.sh
fi
if [ ${DB_INSTALL_VERSION} == "18" ]; then
    /scripts/install_oracle18ee.sh
fi
if [ ${DB_INSTALL_VERSION} == "19" ]; then
    /scripts/install_oracle19ee.sh
fi

if [ ${INSTALL_SQLCL} == "true" ]; then
    /scripts/install_sqlcl.sh
fi

# Pre-extract APEX, ORDS, Swagger UI files into image layer (no DB operations)
if [ "${INSTALL_APEX}" == "true" ]; then
    echo "--------------------------------------------------"
    echo "Pre-extracting APEX files........................."
    rm -rf ${ORACLE_HOME}/apex
    unzip /files/apex*.zip -d ${ORACLE_HOME}/

    echo "Pre-extracting ORDS files........................."
    mkdir -p ${ORDS_HOME}
    unzip -o /files/ords*.zip -d ${ORDS_HOME}
    chmod +x ${ORDS_HOME}/bin/ords
    mkdir -p ${ORDS_CONFIG}
    chown -R oracle:oinstall ${ORDS_HOME}

    if [ "${INSTALL_SWAGGER}" == "true" ]; then
        echo "Pre-extracting Swagger UI files..................."
        cd /files
        unzip -o swagger-ui*.zip
        mkdir -p /opt/swagger-ui
        mv swagger-ui*/dist/* /opt/swagger-ui/
        rm -rf swagger-ui*/
    fi
fi

/scripts/install_ssh.sh

# Move Oracle product outside ORACLE_BASE for VOLUME support
if [ -d ${ORACLE_BASE}/product ] && [ ! -L ${ORACLE_BASE}/product ]; then
    mv ${ORACLE_BASE}/product /u01/app/oracle-product
    ln -s /u01/app/oracle-product ${ORACLE_BASE}/product
fi

yum clean all
rm -rf /tmp/* /var/tmp/*
# /files/ is preserved — DB-dependent components install on first container start
echo "--------------------------------------------------"
echo "Build phase DONE.................................."
