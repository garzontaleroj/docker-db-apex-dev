#!/bin/bash
#
# First-run setup: creates the Oracle database and installs all DB-dependent
# components (APEX, ORDS, Logger, OOS Utils, AOP, AME, Swagger, CA Wallet).
# Runs once on the first container start; subsequent starts skip this.
#

FIRST_RUN_MARKER="${ORACLE_BASE}/.first_run_complete"

if [ -f "$FIRST_RUN_MARKER" ]; then
    echo "First-run setup already completed. Skipping."
    exit 0
fi

set -e

echo "=================================================="
echo "FIRST RUN SETUP — Creating database & components  "
echo "=================================================="

# Source Oracle environment
. /.oracle_env 2>/dev/null || true
export ORACLE_HOME ORACLE_BASE ORACLE_SID

# Helper: run SQL as SYS DBA via gosu oracle
run_sql_sys() {
    gosu oracle bash -c ". /.oracle_env && echo \"$1\" | \${ORACLE_HOME}/bin/sqlplus -s / as sysdba"
}

# Helper: run SQL as a specific user via gosu oracle
run_sql_user() {
    local user=$1
    local pass=$2
    local sql=$3
    gosu oracle bash -c ". /.oracle_env && echo \"$sql\" | \${ORACLE_HOME}/bin/sqlplus -s ${user}/${pass}"
}

# ---------------------------------------------------
# 1. Create Oracle Database
# ---------------------------------------------------
echo "--------------------------------------------------"
echo "Starting listener for database creation..."
gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/lsnrctl start" || true

echo "Creating database SID: ${ORACLE_SID} ..."
gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ${SERVICE_NAME} -sid ${ORACLE_SID} -responseFile NO_VALUE -characterSet AL32UTF8 \
  -datafileDestination \${ORACLE_BASE}/oradata/ -totalMemory ${DBCA_TOTAL_MEMORY} \
  -emConfiguration NONE -sysPassword ${PASS} -systemPassword ${PASS}" || true

# Verify database was actually created
gosu oracle bash -c ". /.oracle_env && echo 'SELECT status FROM v\$instance;' | \${ORACLE_HOME}/bin/sqlplus -s -l / as sysdba" | grep -qi OPEN
echo "Database instance verified OPEN."

# Configure listener registration
run_sql_sys "ALTER SYSTEM SET LOCAL_LISTENER='(ADDRESS = (PROTOCOL = TCP)(HOST = $(hostname))(PORT = 1521))' SCOPE=BOTH;"
run_sql_sys "ALTER SYSTEM REGISTER;"
gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/lsnrctl reload"

# Set password policy
run_sql_sys "ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME UNLIMITED;"

echo "Database ${ORACLE_SID} created successfully."

# ---------------------------------------------------
# 2. Install APEX
# ---------------------------------------------------
if [ "${INSTALL_APEX}" == "true" ]; then
    echo "--------------------------------------------------"
    echo "Installing APEX..................................."

    # Resolve the real path (follows symlinks)
    ORACLE_HOME_REAL=$(readlink -f ${ORACLE_HOME})
    APEX_DIR="${ORACLE_HOME_REAL}/apex"

    # Verify APEX files exist
    echo "Checking APEX directory: ${APEX_DIR}"
    if [ ! -d "${APEX_DIR}" ]; then
        echo "ERROR: APEX directory not found at ${APEX_DIR}"
        echo "Listing ${ORACLE_HOME_REAL}/:"
        ls -la ${ORACLE_HOME_REAL}/ | head -20
        exit 1
    fi
    echo "APEX directory contents (top-level):"
    ls ${APEX_DIR}/*.sql 2>/dev/null | head -10 || echo "  (no .sql files found!)"

    if [ ! -f "${APEX_DIR}/apexins.sql" ]; then
        echo "ERROR: apexins.sql not found in ${APEX_DIR}"
        echo "Full listing:"
        ls -la ${APEX_DIR}/
        exit 1
    fi

    # Disable HTTP on XDB
    run_sql_sys "EXEC DBMS_XDB.SETHTTPPORT(0);"

    # Create APEX tablespace
    DATAFILE_SID=${ORACLE_SID^^}
    run_sql_sys "CREATE TABLESPACE apex DATAFILE '${ORACLE_BASE}/oradata/${DATAFILE_SID}/apex01.dbf' SIZE 100M AUTOEXTEND ON NEXT 10M;"

    # Install APEX — NO piped stdin, NO -s/-l flags
    # apexins.sql has its own EXIT; redirect stdin from /dev/null
    echo "Running apexins.sql (this takes 10-20 minutes)..."
    gosu oracle bash -c ". /.oracle_env && cd ${APEX_DIR} && \${ORACLE_HOME}/bin/sqlplus / as sysdba @apexins.sql APEX APEX TEMP /i/" < /dev/null

    # Verify APEX was installed
    echo "Verifying APEX installation..."
    APEX_SCHEMA=$(gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/sqlplus -s / as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF TRIMSPOOL ON
SELECT ao.owner FROM all_objects ao WHERE ao.object_name = 'WWV_FLOW' AND ao.object_type = 'PACKAGE' AND ao.owner LIKE 'APEX_%';
EXIT;
EOF" | tr -d '[:space:]')

    if [ -z "${APEX_SCHEMA}" ]; then
        echo "ERROR: APEX installation failed — no APEX schema found."
        echo "Checking for any APEX-related users..."
        run_sql_sys "SELECT username FROM dba_users WHERE username LIKE 'APEX%';"
        exit 1
    fi
    echo "APEX schema detected: ${APEX_SCHEMA}"

    # Change APEX admin password
    echo "Setting APEX admin password..."
    gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/sqlplus -s / as sysdba <<EOSQL
ALTER SESSION SET CURRENT_SCHEMA=${APEX_SCHEMA};
BEGIN
    wwv_flow_security.g_security_group_id := 10;
    wwv_flow_security.g_user              := 'admin';
    wwv_flow_fnd_user_int.create_or_update_user( p_user_id  => NULL,
                                                 p_username => 'admin',
                                                 p_email    => 'admin',
                                                 p_password => '${APEX_PASS}' );
    COMMIT;
END;
/
EXIT;
EOSQL"

    # Configure APEX REST users — apex_rest_config needs passwords on stdin
    echo "Configuring APEX REST users..."
    gosu oracle bash -c ". /.oracle_env && cd ${APEX_DIR} && printf '%s\n%s\n' '${PASS}' '${PASS}' | \${ORACLE_HOME}/bin/sqlplus -s / as sysdba @apex_rest_config.sql"
    run_sql_sys "ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;"
    run_sql_sys "ALTER USER APEX_PUBLIC_USER IDENTIFIED BY ${PASS};"

    # Create network ACL
    gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/sqlplus -s / as sysdba <<EOSQL
BEGIN
  BEGIN
    dbms_network_acl_admin.drop_acl(acl => 'all-network-PUBLIC.xml');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  dbms_network_acl_admin.create_acl(acl         => 'all-network-PUBLIC.xml',
                                    description => 'Allow all network traffic',
                                    principal   => 'PUBLIC',
                                    is_grant    => TRUE,
                                    privilege   => 'connect');
  dbms_network_acl_admin.add_privilege(acl       => 'all-network-PUBLIC.xml',
                                       principal => 'PUBLIC',
                                       is_grant  => TRUE,
                                       privilege => 'resolve');
  dbms_network_acl_admin.assign_acl(acl  => 'all-network-PUBLIC.xml',
                                    host => '*');
  COMMIT;
END;
/
EXIT;
EOSQL"

    # Load APEX images
    if [ -f "${APEX_DIR}/apxldimg.sql" ]; then
        echo "Loading APEX images..."
        gosu oracle bash -c ". /.oracle_env && cd ${APEX_DIR} && \${ORACLE_HOME}/bin/sqlplus / as sysdba @apxldimg.sql ${ORACLE_HOME_REAL}" < /dev/null
    else
        echo "WARNING: apxldimg.sql not found — skipping image load"
    fi

    echo "APEX installation completed."

    # ---------------------------------------------------
    # 3. Install ORDS
    # ---------------------------------------------------
    echo "--------------------------------------------------"
    echo "Installing ORDS..................................."

    # ORDS was pre-extracted to ${ORDS_HOME} during build
    # Install ORDS into database (silent mode)
    # --proxy-user + --password-stdin requires TWO passwords: admin then proxy user
    cd ${ORDS_HOME}
    gosu oracle bash -c ". /.oracle_env && cd ${ORDS_HOME} && printf '%s\n%s\n' '${PASS}' '${PASS}' | ${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} install \
      --admin-user SYS \
      --db-hostname localhost \
      --db-port 1521 \
      --db-servicename ${SERVICE_NAME} \
      --feature-sdw ${INSTALL_SQLDEVWEB} \
      --proxy-user \
      --password-stdin"

    # Configure ORDS standalone settings
    gosu oracle bash -c "${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set jdbc.InitialLimit 6"
    gosu oracle bash -c "${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set jdbc.MinLimit 6"
    gosu oracle bash -c "${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set jdbc.MaxLimit 40"
    gosu oracle bash -c "${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set jdbc.MaxConnectionReuseCount 10000"

    if [ "${INSTALL_SQLDEVWEB}" == "true" ]; then
        gosu oracle bash -c "${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set restEnabledSql.active true"
        gosu oracle bash -c "${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set database.api.enabled true"
        gosu oracle bash -c "${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set security.verifySSL false"
    fi

    # Configure Swagger UI static path
    if [ "${INSTALL_SWAGGER}" == "true" ]; then
        gosu oracle bash -c "${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set standalone.static.path /opt/swagger-ui"
        gosu oracle bash -c "${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} config set standalone.static.context.path /swagger-ui"
    fi

    chown -R oracle:oinstall ${ORDS_HOME}

    # SQL Developer Web user
    if [ "${INSTALL_SQLDEVWEB}" == "true" ]; then
        echo "Creating SQL Developer Web admin user..."
        gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/sqlplus -s -l / as sysdba <<EOSQL
CREATE USER SDW_ADMIN IDENTIFIED BY \"${PASS}\" DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP;
ALTER USER SDW_ADMIN QUOTA UNLIMITED ON USERS;
GRANT CONNECT, DBA, PDB_DBA TO SDW_ADMIN;
EXIT;
EOSQL"
        gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/sqlplus -s -l sdw_admin/${PASS} <<EOSQL
BEGIN
  ORDS.enable_schema(
    p_enabled             => TRUE,
    p_schema              => 'SDW_ADMIN',
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'sdw_admin',
    p_auto_rest_auth      => FALSE
  );
  COMMIT;
END;
/
EXIT;
EOSQL"
    fi

    echo "ORDS installation completed."

    # ---------------------------------------------------
    # 4. Install optional APEX components
    # ---------------------------------------------------
    if [ "${INSTALL_AOP}" == "true" ]; then
        echo "--------------------------------------------------"
        echo "Installing AOP...................................."
        /scripts/install_aop.sh || echo "WARNING: AOP install failed, continuing..."
    fi
    if [ "${INSTALL_AME}" == "true" ]; then
        echo "--------------------------------------------------"
        echo "Installing AME...................................."
        /scripts/install_ame.sh || echo "WARNING: AME install failed, continuing..."
    fi
    if [ "${INSTALL_SWAGGER}" == "true" ]; then
        echo "--------------------------------------------------"
        echo "Installing Swagger UI preferences................"
        /scripts/install_swagger.sh || echo "WARNING: Swagger install failed, continuing..."
    fi
    if [ "${INSTALL_CA_CERTS_WALLET}" == "true" ]; then
        echo "--------------------------------------------------"
        echo "Installing CA Certificates Wallet................"
        /scripts/install_ca_wallet.sh || echo "WARNING: CA Wallet install failed, continuing..."
    fi
fi

# ---------------------------------------------------
# 5. Install Logger
# ---------------------------------------------------
if [ "${INSTALL_LOGGER}" == "true" ]; then
    echo "--------------------------------------------------"
    echo "Installing Logger................................."
    /scripts/install_logger.sh || echo "WARNING: Logger install failed, continuing..."
fi

# ---------------------------------------------------
# 6. Install OOS Utils
# ---------------------------------------------------
if [ "${INSTALL_OOSUTILS}" == "true" ]; then
    echo "--------------------------------------------------"
    echo "Installing OOS Utils.............................."
    /scripts/install_oosutils.sh || echo "WARNING: OOS Utils install failed, continuing..."
fi

# ---------------------------------------------------
# 7. Stop DB for clean handoff to entrypoint
# ---------------------------------------------------
echo "--------------------------------------------------"
echo "Stopping database for clean startup handoff......."
gosu oracle bash -c ". /.oracle_env && echo 'shutdown immediate;' | \${ORACLE_HOME}/bin/sqlplus -s -l / as sysdba"
gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/lsnrctl stop" || true

# ---------------------------------------------------
# 8. Cleanup and mark complete
# ---------------------------------------------------
echo "--------------------------------------------------"
echo "Cleaning up installation files..."
rm -f /files/*.zip 2>/dev/null || true

# Write marker file
touch ${FIRST_RUN_MARKER}
echo "=================================================="
echo "FIRST RUN SETUP COMPLETE"
echo "=================================================="
