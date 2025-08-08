#!/bin/bash
# scripts/cleanup-azure-databases.sh

set -euo pipefail

# Default values
DRY_RUN="true"
CONFIG_FILE="config/allowed-databases.yml"
EXCLUDE_DBS="master,tempdb,model,msdb"

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -s, --subscription-id SUBSCRIPTION_ID    Azure subscription ID"
    echo "  -g, --resource-group RESOURCE_GROUP      Resource group name"
    echo "  -n, --server-name SERVER_NAME            SQL server name"
    echo "  -c, --config-file CONFIG_FILE            Config file path (default: $CONFIG_FILE)"
    echo "  -d, --dry-run true|false                 Dry run mode (default: $DRY_RUN)"
    echo "  -e, --exclude-dbs DATABASES              Comma-separated list of DBs to exclude (default: $EXCLUDE_DBS)"
    echo "  -h, --help                               Show this help message"
    exit 1
}

# Function to log messages
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
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
        -c|--config-file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="$2"
            shift 2
            ;;
        -e|--exclude-dbs)
            EXCLUDE_DBS="$2"
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
if [[ -z "${SUBSCRIPTION_ID:-}" || -z "${RESOURCE_GROUP:-}" || -z "${SERVER_NAME:-}" ]]; then
    echo "Error: Missing required parameters"
    usage
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR" "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Create reports directory
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
REPORT_DIR="./reports"
mkdir -p "$REPORT_DIR"

LOG_FILE="$REPORT_DIR/cleanup-log-$TIMESTAMP.txt"
REPORT_FILE="$REPORT_DIR/cleanup-report-$TIMESTAMP.json"

# Redirect output to both console and log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log "INFO" "Starting Azure SQL Database cleanup process"
log "INFO" "Subscription: $SUBSCRIPTION_ID"
log "INFO" "Resource Group: $RESOURCE_GROUP"
log "INFO" "SQL Server: $SERVER_NAME"
log "INFO" "Config File: $CONFIG_FILE"
log "INFO" "Dry Run Mode: $DRY_RUN"

# Set Azure subscription context
log "INFO" "Setting Azure subscription context..."
az account set --subscription "$SUBSCRIPTION_ID"

# Read allowed databases from config file
log "INFO" "Reading configuration file..."
ALLOWED_DATABASES=()

case "${CONFIG_FILE##*.}" in
    yml|yaml)
        if command -v yq >/dev/null 2>&1; then
            # Using yq (YAML processor)
            if yq eval '.databases' "$CONFIG_FILE" >/dev/null 2>&1; then
                mapfile -t ALLOWED_DATABASES < <(yq eval '.databases[]' "$CONFIG_FILE")
            else
                mapfile -t ALLOWED_DATABASES < <(yq eval '.[]' "$CONFIG_FILE")
            fi
        else
            # Fallback: parse YAML manually (basic parsing)
            mapfile -t ALLOWED_DATABASES < <(grep -E "^\s*-\s*" "$CONFIG_FILE" | sed 's/^\s*-\s*//' | sed 's/["'"'"']//g')
        fi
        ;;
    txt)
        mapfile -t ALLOWED_DATABASES < <(grep -v '^#' "$CONFIG_FILE" | grep -v '^[[:space:]]*$')
        ;;
    json)
        if command -v jq >/dev/null 2>&1; then
            if jq -e '.databases' "$CONFIG_FILE" >/dev/null 2>&1; then
                mapfile -t ALLOWED_DATABASES < <(jq -r '.databases[]' "$CONFIG_FILE")
            else
                mapfile -t ALLOWED_DATABASES < <(jq -r '.[]' "$CONFIG_FILE")
            fi
        else
            log "ERROR" "jq is required to parse JSON files"
            exit 1
        fi
        ;;
    *)
        log "ERROR" "Unsupported file format. Supported formats: .yml, .yaml, .txt, .json"
        exit 1
        ;;
esac

log "INFO" "Found ${#ALLOWED_DATABASES[@]} allowed databases in config file"
log "INFO" "Allowed databases: $(IFS=', '; echo "${ALLOWED_DATABASES[*]}")"

# Get all databases from Azure SQL Server
log "INFO" "Fetching databases from Azure SQL Server..."
AZURE_DATABASES=$(az sql db list \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --query "[].name" \
    --output tsv)

# Convert exclude list to array
IFS=',' read -ra EXCLUDE_ARRAY <<< "$EXCLUDE_DBS"

# Filter out system databases
USER_DATABASES=()
while IFS= read -r db; do
    if [[ -n "$db" ]]; then
        exclude_db=false
        for exclude in "${EXCLUDE_ARRAY[@]}"; do
            if [[ "$db" == "$exclude" ]]; then
                exclude_db=true
                break
            fi
        done
        if [[ "$exclude_db" == false ]]; then
            USER_DATABASES+=("$db")
        fi
    fi
done <<< "$AZURE_DATABASES"

log "INFO" "User databases found: $(IFS=', '; echo "${USER_DATABASES[*]}")"

# Find databases to delete
DATABASES_TO_DELETE=()
for db in "${USER_DATABASES[@]}"; do
    found=false
    for allowed_db in "${ALLOWED_DATABASES[@]}"; do
        if [[ "$db" == "$allowed_db" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" == false ]]; then
        DATABASES_TO_DELETE+=("$db")
    fi
done

log "INFO" "Databases marked for deletion: ${#DATABASES_TO_DELETE[@]}"

# Initialize report
cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "subscriptionId": "$SUBSCRIPTION_ID",
  "resourceGroupName": "$RESOURCE_GROUP",
  "serverName": "$SERVER_NAME",
  "configFile": "$CONFIG_FILE",
  "dryRun": $DRY_RUN,
  "allowedDatabases": $(printf '%s\n' "${ALLOWED_DATABASES[@]}" | jq -R . | jq -s .),
  "existingDatabases": $(printf '%s\n' "${USER_DATABASES[@]}" | jq -R . | jq -s .),
  "databasesMarkedForDeletion": $(printf '%s\n' "${DATABASES_TO_DELETE[@]}" | jq -R . | jq -s .),
  "deletionResults": []
}
EOF

if [[ ${#DATABASES_TO_DELETE[@]} -eq 0 ]]; then
    log "INFO" "No databases to delete. All existing databases are in the allowed list."
else
    log "WARN" "The following databases will be deleted:"
    for db in "${DATABASES_TO_DELETE[@]}"; do
        # Get database details
        DB_INFO=$(az sql db show \
            --resource-group "$RESOURCE_GROUP" \
            --server "$SERVER_NAME" \
            --name "$db" \
            --query "{creationDate: creationDate, serviceObjective: currentServiceObjectiveName}" \
            --output json 2>/dev/null || echo '{"creationDate": "unknown", "serviceObjective": "unknown"}')
        
        CREATION_DATE=$(echo "$DB_INFO" | jq -r '.creationDate')
        SERVICE_OBJECTIVE=$(echo "$DB_INFO" | jq -r '.serviceObjective')
        
        log "WARN" "  - $db (Created: $CREATION_DATE, Size: $SERVICE_OBJECTIVE)"
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        log "WARN" "DRY RUN MODE: No databases will actually be deleted"
        
        # Update report with dry run results
        RESULTS_JSON="["
        for i in "${!DATABASES_TO_DELETE[@]}"; do
            if [[ $i -gt 0 ]]; then
                RESULTS_JSON+=","
            fi
            RESULTS_JSON+="{\"databaseName\": \"${DATABASES_TO_DELETE[$i]}\", \"status\": \"DRY_RUN\", \"message\": \"Would be deleted in real run\"}"
        done
        RESULTS_JSON+="]"
        
        jq ".deletionResults = $RESULTS_JSON" "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"
    else
        log "WARN" "Proceeding with database deletion..."
        
        RESULTS_JSON="["
        for i in "${!DATABASES_TO_DELETE[@]}"; do
            db="${DATABASES_TO_DELETE[$i]}"
            
            if [[ $i -gt 0 ]]; then
                RESULTS_JSON+=","
            fi
            
            log "INFO" "Deleting database: $db"
            
            # Confirmation timeout
            CONFIRMATION_TIMEOUT=30
            log "INFO" "Waiting $CONFIRMATION_TIMEOUT seconds before deletion..."
            sleep $CONFIRMATION_TIMEOUT
            
            # Attempt to delete the database
            if az sql db delete \
                --resource-group "$RESOURCE_GROUP" \
                --server "$SERVER_NAME" \
                --name "$db" \
                --yes > /dev/null 2>&1; then
                
                log "SUCCESS" "Successfully deleted database: $db"
                RESULTS_JSON+="{\"databaseName\": \"$db\", \"status\": \"SUCCESS\", \"message\": \"Database deleted successfully\"}"
            else
                ERROR_MSG="Failed to delete database via Azure CLI"
                log "ERROR" "Failed to delete database $db: $ERROR_MSG"
                RESULTS_JSON+="{\"databaseName\": \"$db\", \"status\": \"ERROR\", \"message\": \"$ERROR_MSG\"}"
            fi
        done
        RESULTS_JSON+="]"
        
        # Update report with actual results
        jq ".deletionResults = $RESULTS_JSON" "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"
    fi
fi

# Find databases that exist in config but not in Azure (for information)
MISSING_DATABASES=()
for allowed_db in "${ALLOWED_DATABASES[@]}"; do
    found=false
    for existing_db in "${USER_DATABASES[@]}"; do
        if [[ "$allowed_db" == "$existing_db" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" == false ]]; then
        MISSING_DATABASES+=("$allowed_db")
    fi
done

if [[ ${#MISSING_DATABASES[@]} -gt 0 ]]; then
    log "INFO" "NOTE: The following databases are in the config but don't exist on the server:"
    for db in "${MISSING_DATABASES[@]}"; do
        log "INFO" "  - $db"
    done
    
    # Add missing databases to report
    MISSING_JSON=$(printf '%s\n' "${MISSING_DATABASES[@]}" | jq -R . | jq -s .)
    jq ".missingDatabases = $MISSING_JSON" "$REPORT_FILE" > "$REPORT_FILE.tmp" && mv "$REPORT_FILE.tmp" "$REPORT_FILE"
fi

log "INFO" "Cleanup report saved to: $REPORT_FILE"
log "INFO" "Azure SQL Database cleanup process completed successfully"

# Output summary
echo ""
echo "=== CLEANUP SUMMARY ==="
echo "Total databases on server: ${#USER_DATABASES[@]}"
echo "Allowed databases in config: ${#ALLOWED_DATABASES[@]}"
echo "Databases marked for deletion: ${#DATABASES_TO_DELETE[@]}"

if [[ "$DRY_RUN" == "true" ]]; then
    echo "Mode: DRY RUN (no actual deletions performed)"
else
    SUCCESS_COUNT=$(jq '[.deletionResults[] | select(.status == "SUCCESS")] | length' "$REPORT_FILE")
    ERROR_COUNT=$(jq '[.deletionResults[] | select(.status == "ERROR")] | length' "$REPORT_FILE")
    echo "Successfully deleted: $SUCCESS_COUNT"
    echo "Failed deletions: $ERROR_COUNT"
fi

echo ""
echo "Reports generated:"
echo "  Log: $LOG_FILE"
echo "  Report: $REPORT_FILE"