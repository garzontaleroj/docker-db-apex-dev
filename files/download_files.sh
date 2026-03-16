#!/bin/bash
#
# Downloads and extracts all required files for building the Docker image.
# The archive is hosted on Google Drive and contains Oracle DB, APEX, ORDS,
# JDK, SQLcl, Swagger UI, Tomcat, and optional components.
#
# Usage:
#   cd files/
#   chmod +x download_files.sh
#   ./download_files.sh
#

set -e

GDRIVE_FILE_ID="1KeAFJhYzhvJMNm9t5jfrXyhPnM4T6Yz0"
DOWNLOAD_FILE="oracle_files.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=================================================="
echo " Docker DB APEX Dev - File Downloader"
echo "=================================================="
echo ""
echo "Target directory: ${SCRIPT_DIR}"
echo ""

cd "${SCRIPT_DIR}"

# -------------------------------------------------------
# Download from Google Drive
# -------------------------------------------------------
download_from_gdrive() {
    local file_id="$1"
    local output="$2"

    # Try gdown first (most reliable for Google Drive)
    if command -v gdown &>/dev/null; then
        echo "Downloading with gdown..."
        gdown "https://drive.google.com/uc?id=${file_id}" -O "${output}"
        return $?
    fi

    # Fallback: curl with confirmation token for large files
    if command -v curl &>/dev/null; then
        echo "Downloading with curl (gdown not found)..."
        # First request to get the confirmation token
        local confirm
        confirm=$(curl -sc /tmp/gdrive_cookie \
            "https://drive.google.com/uc?export=download&id=${file_id}" \
            | grep -oP 'confirm=\K[^&]+' || true)

        if [ -n "${confirm}" ]; then
            # Large file: use confirmation token
            curl -Lb /tmp/gdrive_cookie \
                "https://drive.google.com/uc?export=download&confirm=${confirm}&id=${file_id}" \
                -o "${output}"
        else
            # Try direct download (small file or new API)
            curl -L \
                "https://drive.google.com/uc?export=download&id=${file_id}" \
                -o "${output}"

            # Check if we got an HTML page instead of the actual file
            if file "${output}" | grep -qi "html"; then
                echo ""
                echo "ERROR: Google Drive returned an HTML page instead of the file."
                echo "This usually means the file requires manual confirmation."
                echo ""
                echo "Please install gdown and retry:"
                echo "  pip install gdown"
                echo "  ./download_files.sh"
                echo ""
                echo "Or download manually from:"
                echo "  https://drive.google.com/file/d/${file_id}/view?usp=drive_link"
                echo ""
                echo "Save the file as '${output}' in this directory, then run:"
                echo "  ./download_files.sh --extract-only"
                rm -f "${output}"
                return 1
            fi
        fi
        rm -f /tmp/gdrive_cookie
        return 0
    fi

    # Fallback: wget
    if command -v wget &>/dev/null; then
        echo "Downloading with wget (gdown and curl not found)..."
        wget --no-check-certificate \
            "https://drive.google.com/uc?export=download&id=${file_id}" \
            -O "${output}"

        if file "${output}" | grep -qi "html"; then
            echo ""
            echo "ERROR: Google Drive returned an HTML page."
            echo "Please install gdown: pip install gdown"
            rm -f "${output}"
            return 1
        fi
        return 0
    fi

    echo "ERROR: No download tool found. Install one of: gdown, curl, wget"
    return 1
}

# -------------------------------------------------------
# Extract archive
# -------------------------------------------------------
extract_archive() {
    local archive="$1"

    if [ ! -f "${archive}" ]; then
        echo "ERROR: Archive not found: ${archive}"
        return 1
    fi

    echo ""
    echo "Extracting ${archive}..."

    # Detect format and extract
    case "$(file -b "${archive}" | tr '[:upper:]' '[:lower:]')" in
        *gzip*|*tar*)
            tar -xzf "${archive}" --strip-components=0
            ;;
        *zip*)
            unzip -o "${archive}"
            ;;
        *xz*)
            tar -xJf "${archive}" --strip-components=0
            ;;
        *bzip2*)
            tar -xjf "${archive}" --strip-components=0
            ;;
        *)
            # Try tar.gz first, then zip
            if tar -xzf "${archive}" 2>/dev/null; then
                echo "Extracted as tar.gz"
            elif unzip -o "${archive}" 2>/dev/null; then
                echo "Extracted as zip"
            else
                echo "ERROR: Unknown archive format."
                file "${archive}"
                return 1
            fi
            ;;
    esac

    echo "Extraction complete."
}

# -------------------------------------------------------
# Verify expected files
# -------------------------------------------------------
verify_files() {
    echo ""
    echo "Verifying required files..."
    local missing=0

    local required_files=(
        "LINUX.X64_193000_db_home.zip:Oracle Database 19c"
        "OpenJDK17U-jdk_*.tar.gz:Eclipse Temurin JDK 17"
    )

    local optional_files=(
        "apex*.zip:Oracle APEX"
        "ords*.zip:Oracle ORDS"
        "sqlcl*.zip:Oracle SQLcl"
        "swagger-ui*.zip:Swagger UI"
        "apache-tomcat*.tar.gz:Apache Tomcat"
        "logger_*.zip:OraOpenSource Logger"
        "oos-utils*.zip:OraOpenSource OOS Utils"
        "aop_cloud_v*.zip:APEX Office Print"
        "ame_cloud_v*.zip:APEX Media Extension"
    )

    echo ""
    echo "--- Required ---"
    for entry in "${required_files[@]}"; do
        local pattern="${entry%%:*}"
        local name="${entry#*:}"
        if ls ${pattern} 1>/dev/null 2>&1; then
            echo "  [OK] ${name} ($(ls ${pattern}))"
        else
            echo "  [MISSING] ${name} (${pattern})"
            missing=$((missing + 1))
        fi
    done

    echo ""
    echo "--- Optional ---"
    for entry in "${optional_files[@]}"; do
        local pattern="${entry%%:*}"
        local name="${entry#*:}"
        if ls ${pattern} 1>/dev/null 2>&1; then
            echo "  [OK] ${name} ($(ls ${pattern}))"
        else
            echo "  [--] ${name} (${pattern}) - not found"
        fi
    done

    echo ""
    if [ ${missing} -gt 0 ]; then
        echo "WARNING: ${missing} required file(s) missing!"
        return 1
    else
        echo "All required files present."
        return 0
    fi
}

# -------------------------------------------------------
# Main
# -------------------------------------------------------

# --extract-only: skip download, just extract existing file
if [ "$1" == "--extract-only" ]; then
    extract_archive "${DOWNLOAD_FILE}"
    verify_files
    exit $?
fi

# --verify: only check files
if [ "$1" == "--verify" ]; then
    verify_files
    exit $?
fi

# Full flow: download + extract + verify
echo "Step 1/3: Downloading from Google Drive..."
echo "File ID: ${GDRIVE_FILE_ID}"
echo ""

if [ -f "${DOWNLOAD_FILE}" ]; then
    echo "Archive already exists: ${DOWNLOAD_FILE}"
    read -rp "Re-download? [y/N]: " yn
    case ${yn} in
        [Yy]*) rm -f "${DOWNLOAD_FILE}" ;;
        *)     echo "Using existing archive." ;;
    esac
fi

if [ ! -f "${DOWNLOAD_FILE}" ]; then
    download_from_gdrive "${GDRIVE_FILE_ID}" "${DOWNLOAD_FILE}"
    echo ""
    echo "Download complete: $(du -h "${DOWNLOAD_FILE}" | cut -f1)"
fi

echo ""
echo "Step 2/3: Extracting files..."
extract_archive "${DOWNLOAD_FILE}"

echo ""
echo "Step 3/3: Verifying files..."
verify_files
VERIFY_RESULT=$?

# Cleanup archive to save space
echo ""
read -rp "Delete archive ${DOWNLOAD_FILE} to save space? [Y/n]: " yn
case ${yn} in
    [Nn]*) echo "Keeping ${DOWNLOAD_FILE}" ;;
    *)     rm -f "${DOWNLOAD_FILE}"; echo "Archive deleted." ;;
esac

echo ""
echo "=================================================="
echo " Done! You can now build the Docker image:"
echo "   docker build -t db-apex-dev ."
echo "=================================================="

exit ${VERIFY_RESULT}
