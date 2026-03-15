#!/bin/bash

create_sdw_admin_user() {
    echo "Creating SQL Developer Web Admin User."

    echo 'create user SDW_ADMIN identified by "'${PASS}'" default tablespace USERS temporary tablespace TEMP' >create_sdw_admin_user.sql
    echo "/" >>create_sdw_admin_user.sql
    echo "alter user SDW_ADMIN quota unlimited on USERS" >>create_sdw_admin_user.sql
    echo "/" >>create_sdw_admin_user.sql
    echo "grant connect, dba, pdb_dba to SDW_ADMIN;" >>create_sdw_admin_user.sql
    echo "/" >>create_sdw_admin_user.sql

    echo "EXIT" | ${ORACLE_HOME}/bin/sqlplus -s -l sys/${PASS} AS SYSDBA @create_sdw_admin_user
}

enable_ords_sdw_admin() {
    echo "Enable ORDS for SQL Developer Web Admin User."

    echo "BEGIN" >enable_ords_sdw_admin.sql
    echo "  ORDS.enable_schema(" >>enable_ords_sdw_admin.sql
    echo "    p_enabled             => TRUE," >>enable_ords_sdw_admin.sql
    echo "    p_schema              => 'SDW_ADMIN'," >>enable_ords_sdw_admin.sql
    echo "    p_url_mapping_type    => 'BASE_PATH'," >>enable_ords_sdw_admin.sql
    echo "    p_url_mapping_pattern => 'sdw_admin'," >>enable_ords_sdw_admin.sql
    echo "    p_auto_rest_auth      => FALSE" >>enable_ords_sdw_admin.sql
    echo "  );" >>enable_ords_sdw_admin.sql
    echo "  COMMIT;" >>enable_ords_sdw_admin.sql
    echo "END;" >>enable_ords_sdw_admin.sql
    echo "/" >>enable_ords_sdw_admin.sql

    echo "EXIT" | ${ORACLE_HOME}/bin/sqlplus -s -l sdw_admin/${PASS} @enable_ords_sdw_admin
}

source /etc/profile

echo "--------------------------------------------------"
echo "Installing ORDS (standalone mode)................."

# Extract ORDS
mkdir -p ${ORDS_HOME}
unzip -o /files/ords*.zip -d ${ORDS_HOME}
chmod +x ${ORDS_HOME}/bin/ords

# Create config directory
mkdir -p ${ORDS_CONFIG}

# Install ORDS into database (silent mode)
cd ${ORDS_HOME}
echo ${PASS} | ${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} install \
  --admin-user SYS \
  --db-hostname localhost \
  --db-port 1521 \
  --db-servicename ${SERVICE_NAME} \
  --feature-sdw ${INSTALL_SQLDEVWEB} \
  --proxy-user \
  --password-stdin

# Configure ORDS standalone settings
${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set jdbc.InitialLimit 6
${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set jdbc.MinLimit 6
${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set jdbc.MaxLimit 40
${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set jdbc.MaxConnectionReuseCount 10000

if [ "${INSTALL_SQLDEVWEB}" == "true" ]; then
    ${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set restEnabledSql.active true
    ${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set database.api.enabled true
    ${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set security.verifySSL false
fi

# Configure standalone static files (for Swagger UI)
${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set standalone.static.path /opt/swagger-ui
${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set standalone.static.context.path /swagger-ui

# Set ownership
chown -R oracle:oinstall ${ORDS_HOME}

# Apply APEX patch images if present
if [ ! -z "${APEX_PATCH_SET_BUNDLE_FILE}" ]; then
    if ls /files/apexpatch/*/images 1> /dev/null 2>&1; then
        cp -rf /files/apexpatch/*/images/* ${ORACLE_HOME}/apex/images/
    fi
fi

# SQL Developer Web user setup
if [ "${INSTALL_SQLDEVWEB}" == "true" ]; then
    cd /files
    create_sdw_admin_user
    enable_ords_sdw_admin
fi

echo "--------------------------------------------------"
echo "ORDS standalone installation completed."
