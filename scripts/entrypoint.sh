#!/bin/bash

# set environment
. /scripts/setenv.sh

# add hostname
echo "127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4" > /etc/hosts
echo "::1         localhost localhost.localdomain localhost6 localhost6.localdomain6" >> /etc/hosts
echo "127.0.0.1   $HOSTNAME" >> /etc/hosts

# set timezone
ln -s -f /usr/share/zoneinfo/${TIME_ZONE} /etc/localtime

# start all components
# ssh
/usr/sbin/sshd
# set oracle home
if [ ${DB_INSTALL_VERSION} == "12" ]; then
    export ORACLE_HOME=${ORACLE_HOME12}
fi
if [ ${DB_INSTALL_VERSION} == "18" ]; then
    export ORACLE_HOME=${ORACLE_HOME18}
fi
if [ ${DB_INSTALL_VERSION} == "19" ]; then
    export ORACLE_HOME=${ORACLE_HOME19}
fi

# First run: create database and install all DB-dependent components
if [ ! -f "${ORACLE_BASE}/.first_run_complete" ]; then
    echo "First run detected — running database setup..."
    if ! /scripts/first_run_setup.sh; then
        echo "ERROR: First run setup failed. Check logs above."
        echo "Container will stay running for debugging. Connect with: docker exec -it <container> bash"
        trap "exit 1" INT TERM
        while true; do sleep 1; done
    fi
fi

# Start Oracle
gosu oracle bash -c ". /.oracle_env && \${ORACLE_HOME}/bin/lsnrctl start" || true
gosu oracle bash -c '. /.oracle_env && echo startup\; | ${ORACLE_HOME}/bin/sqlplus -s -l / as sysdba'
# ords standalone
if [ ${INSTALL_APEX} == "true" ]; then
    gosu oracle bash -c ". /.oracle_env && ${ORDS_HOME}/bin/ords --config ${ORDS_CONFIG} serve --port 8080 --apex-images \${ORACLE_HOME}/apex/images" &
fi

# Graceful shutdown
graceful_shutdown() {
    if [ ${INSTALL_APEX} == "true" ]; then
        echo "Stopping ORDS..."
        pkill -f "ords.*serve" 2>/dev/null
    fi
    echo "Stopping Oracle..."
    gosu oracle bash -c '. /.oracle_env && echo shutdown immediate\; | ${ORACLE_HOME}/bin/sqlplus -S / as sysdba'
    gosu oracle bash -c '. /.oracle_env && ${ORACLE_HOME}/bin/lsnrctl stop' 2>/dev/null
}

trap graceful_shutdown INT TERM
while true; do sleep 1; done
