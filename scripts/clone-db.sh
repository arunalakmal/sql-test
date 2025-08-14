#!/bin/bash

set -euo pipefail

# Default values
DRY_RUN="true"

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -f, --function OPERATION Create|Delete   Azure subscription ID)"
    echo "  -s, --subscription-id SUBSCRIPTION_ID    Azure subscription ID"
    echo "  -g, --resource-group RESOURCE_GROUP      Resource group name"
    echo "  -n, --server-name SERVER_NAME            SQL server name"
    echo "  -b, --source-db SOURCE_DB_NAME           Source database name"
    echo "  -e, --dest-server DEST_SERVER_NAME       Detination Server Name"
    echo "  -c, --dest-db DEST_DB_NAME               Destination database name"
    echo "  -i, --suffix DB CLONE SUFFIX             Detination Server Name"
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

construct_suffix() {
    FULL_NAME=${SUFFIX}
    CLEAN_NAME=$(echo "$FULL_NAME" | sed 's|refs/heads/||' | tr '/' '-')
    CLEAN_NAME=$(echo "$CLEAN_NAME" | tr '/_' '-' | tr '[:upper:]' '[:lower:]')
    SUFFIX=$(echo "$CLEAN_NAME" | cut -c1-20)
    echo "SUFFIX=$SUFFIX" >> $GITHUB_ENV
    FULL_DB_NAME=${SOURCE_DB_NAME}-${SUFFIX}
    echo "FULL_DB_NAME=${FULL_DB_NAME}" >> $GITHUB_ENV
    
    log "INFO" "Database is: ${FULL_DB_NAME:-}"
}

clone_database() {
    construct_suffix
    log "INFO" "Checking if database ${FULL_DB_NAME} exists on server ${SERVER_NAME}"
    if az sql db show \
        --name ${FULL_DB_NAME} \
        --server ${SERVER_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "name" -o tsv >/dev/null 2>&1; then

        log "INFO" "Database ${FULL_DB_NAME} already exists on server ${SERVER_NAME}. DB Cloning process will be skipped and continue."
    else
        log "INFO" "Cloning database ${SOURCE_DB_NAME} to ${FULL_DB_NAME} on server ${SERVER_NAME}"

        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "Dry run mode enabled. No changes will be made this time, without DRY RUN mode database ${SOURCE_DB_NAME} will be cloned."
            return
        else
            log "INFO" "Executing database clonning process..."
            log "INFO" "Please wait! this process will take a while..."

            az sql db copy --dest-name ${FULL_DB_NAME} \
            --name ${SOURCE_DB_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --server ${SERVER_NAME} \
            --dest-resource-group ${RESOURCE_GROUP} \
            --dest-server ${SERVER_NAME} > /dev/null 2>&1

            log "INFO" "Database ${SOURCE_DB_NAME} cloned to ${FULL_DB_NAME} on server ${SERVER_NAME} successfully."
        fi
    fi
}

delete_clone() {
    construct_suffix
    log "INFO" "Deleting cloned database ${FULL_DB_NAME}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Dry run mode enabled. No changes will be made this time, without DRY RUN mode database ${FULL_DB_NAME} will be deleted."
        return
    else
        log "INFO" "Executing database deletion process..."
        log "INFO" "Please wait! this process will take a while..."
        
        az sql db delete --name ${FULL_DB_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --server ${SERVER_NAME} --yes > /dev/null 2>&1

        log "INFO" "Database ${FULL_DB_NAME} deleted from server ${SERVER_NAME}."
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--function)
            OPERATION="$2"
            shift 2
            ;;
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
        -c|--dest-db)
            DEST_DB_NAME="$2"
            shift 2
            ;;
        -i|--suffix)
            SUFFIX="$2"
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
if [[ -z "${OPERATION:-}" || -z "${RESOURCE_GROUP:-}" || -z "${SERVER_NAME:-}" || -z "${SOURCE_DB_NAME:-}" || -z "${SUFFIX:-}" ]]; then
    echo "Error: Missing required parameters"
    usage
fi

if [[ "$OPERATION" == "create" ]]; then
    clone_database
elif [[ "$OPERATION" == "delete" ]]; then
    delete_clone
else
    echo "Error: Invalid operation '$OPERATION'. Use 'create' or 'delete'."
    exit 1
fi
