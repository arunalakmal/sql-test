#!/bin/bash

set -euo pipefail

# Default values
DRY_RUN="true"

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -s, --subscription-id SUBSCRIPTION_ID    Azure subscription ID"
    echo "  -g, --resource-group RESOURCE_GROUP      Resource group name"
    echo "  -n, --server-name SERVER_NAME            SQL server name"
    echo "  -b, --source-db SOURCE_DB_NAME           Source database name"
    echo "  -e, --dest-server DEST_SERVER_NAME       Detination Server Name"
    echo "  -f, --dest-db DEST_DB_NAME               Destination database name"
    echo "  -d, --dry-run true|false                 Dry run mode (default: $DRY_RUN)"
    echo "  -h, --help                               Show this help message"
    exit 1
}

# Function to log messages
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

clone_database() {

    log "INFO" "Cloning database ${SOURCE_DB_NAME}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Dry run mode enabled. No changes will be made this time, without DRY RUN mode database ${SOURCE_DB_NAME} will be cloned."
        return
    else
        log "INFO" "Executing database clonning process..."

        FULL_NAME="${{ github.ref }}"
        CLEAN_NAME=$(echo "$FULL_NAME" | sed 's|refs/heads/||' | tr '/' '-')
        CLEAN_NAME=$(echo "$CLEAN_NAME" | tr '/_' '-')
        SUFFIX=$(echo "$CLEAN_NAME" | cut -c1-10)
        echo "SUFFIX=$SUFFIX" >> $GITHUB_ENV

        az sql db copy --dest-name ${SOURCE_DB_NAME}-${SUFFIX} \
        --name ${SOURCE_DB_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --server ${SERVER_NAME} \
        --dest-resource-group ${RESOURCE_GROUP} \
        --dest-server ${SERVER_NAME}

        log "INFO" "Database ${SOURCE_DB_NAME} cloned to ${SOURCE_DB_NAME}-${SUFFIX} on server ${SERVER_NAME}."
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -n|--server-name)
            SERVER_NAME="$2"
            shift 2
            ;;
        -b|--source-db)
            SOURCE_DB_NAME="$2"
            shift 2
            ;;
        -e|--dest-server)
            DEST_SERVER_NAME="$2"
            shift 2
            ;;
        -f|--dest-db)
            DEST_DB_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "${RESOURCE_GROUP:-}" || -z "${SERVER_NAME:-}" || -z "${SOURCE_DB_NAME:-}" ]]; then
    echo "Error: Missing required parameters"
    usage
fi

clone_database