#!/bin/bash
set -e

echo "--------------------------------------------------"
echo "Installing ORACLE Database 19 EE.................."

# Crear grupos y usuario Oracle
groupadd --gid 54321 oinstall || true
groupadd --gid 54322 dba || true
groupadd --gid 54323 oper || true
useradd --create-home --gid oinstall --groups oinstall,dba --uid 54321 oracle || true
echo "oracle:${PASS}" | chpasswd

# Instalar prerequisitos
yum install -y oracle-database-preinstall-19c.x86_64 perl tar unzip wget

# Variables de entorno
echo "export ORACLE_HOME=${ORACLE_HOME}" >> /.oracle_env
echo "export ORACLE_BASE=${ORACLE_BASE}" >> /.oracle_env
echo "export ORACLE_SID=${ORACLE_SID}" >> /.oracle_env
echo "export PATH=/usr/sbin:\$PATH" >> /.oracle_env
echo "export PATH=\$ORACLE_HOME/bin:\$PATH" >> /.oracle_env
echo "export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib" >> /.oracle_env
echo "export CLASSPATH=\$ORACLE_HOME/jlib:\$ORACLE_HOME/rdbms/jlib" >> /.oracle_env
echo "export TMP=/tmp" >> /.oracle_env
echo "export TMPDIR=\$TMP" >> /.oracle_env
echo "export TERM=linux" >> /.oracle_env
echo "export NLS_LANG=American_America.AL32UTF8" >> /.oracle_env
chmod +x /.oracle_env
. /.oracle_env

# Crear directorios
mkdir -p ${ORACLE_HOME}
mkdir -p ${ORACLE_BASE}
mkdir -p ${ORACLE_INVENTORY}
mkdir -p ${ORACLE_HOME}/network/admin   # <-- asegura que exista
chown -R oracle:oinstall /u01

# Instalar gosu
cp /files/gosu-amd64 /usr/local/bin/gosu
chmod +x /usr/local/bin/gosu

# Extraer software Oracle
cd /files
chown oracle:oinstall LINUX.X64_193000_db_home.zip
echo "Extracting Oracle 19c software..."
gosu oracle bash -c "unzip -o /files/LINUX.X64_193000_db_home.zip -d ${ORACLE_HOME}" > /dev/null
rm -f /files/LINUX.X64_193000_db_home.zip

# Preparar response file
sed -i -E "s:#ORACLE_INVENTORY#:${ORACLE_INVENTORY}:g" /files/db_install_19.rsp
sed -i -E "s:#ORACLE_HOME#:${ORACLE_HOME}:g" /files/db_install_19.rsp
sed -i -E "s:#ORACLE_BASE#:${ORACLE_BASE}:g" /files/db_install_19.rsp
chown oracle:oinstall /files/db_install_19.rsp

# Ejecutar instalador
echo "Running Oracle installer..."
gosu oracle bash -c "${ORACLE_HOME}/runInstaller -silent -force -waitforcompletion -responsefile /files/db_install_19.rsp -ignorePrereqFailure"

# Ejecutar scripts de root
echo "Running Oracle root scripts..."
/u01/app/oraInventory/orainstRoot.sh || true
${ORACLE_HOME}/root.sh || true

echo "--------------------------------------------------"
echo "Oracle 19c software installation completed."
echo "Database will be created on first container start."
