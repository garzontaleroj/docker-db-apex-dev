#!/bin/bash
cd /files

# Crear destino
mkdir -p /opt/java

# Extraer el tarball correcto
tar -xzf OpenJDK17U-jdk_x64_linux_hotspot_17.0.18_8.tar.gz -C /opt/java --strip-components=1

# Definir JAVA_HOME
export JAVA_HOME=/opt/java
export PATH=$JAVA_HOME/bin:$PATH

# Persistir en perfiles
echo "export JAVA_HOME=/opt/java" >> /etc/profile
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> /etc/profile

echo "export JAVA_HOME=/opt/java" >> /home/oracle/.bashrc
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> /home/oracle/.bashrc
echo "export JAVA_HOME=/opt/java" >> /root/.bashrc
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> /root/.bashrc
