#!/bin/bash
cd /files

# Crear destino
mkdir -p /opt/java

# Extraer el tarball correcto
tar -xzf OpenJDK17U-jdk_x64_linux_hotspot_17.0.18_8.tar.gz -C /opt/java --strip-components=1

# Validación rápida
/opt/java/bin/java -version
