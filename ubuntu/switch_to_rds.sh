#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Paths
ENV_R=~/infinitetrading/src/.env
ENV_NODE=~/infinitetrading_api/express/.env

# RDS Configuration
RDS_HOST="infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com"
RDS_USER="admin"
RDS_PASS="NcwbBmT5Vxv9ZAx"
RDS_DB="infinitetrading"

# Local MySQL Configuration
LOCAL_HOST="localhost"
LOCAL_USER="richard_clare"
LOCAL_PASS="AxDWeW8E7w8dSXJKsXsdfASXaxAD279347"
LOCAL_DB="infinitetrading"

backup_env() {
    local file=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp "$file" "${file}.backup_${timestamp}"
    echo "${GREEN}✅ Backed up: ${file}.backup_${timestamp}${NC}"
}

switch_to_rds() {
    echo "${YELLOW}Switching to RDS Aurora...${NC}"
    
    # Backup R env file
    if [ -f "$ENV_R" ]; then
        backup_env "$ENV_R"
        sed -i 's|^host="[^"]*"|host=""|' "$ENV_R"
        sed -i 's|^db_user="[^"]*"|db_user=""|' "$ENV_R"
        sed -i 's|^db_password="[^"]*"|db_password=""|' "$ENV_R"
        sed -i 's|^database="[^"]*"|database=""|' "$ENV_R"
        echo "${GREEN}✅ Updated R environment: $ENV_R${NC}"
    fi
    
    # Backup Node env file
    if [ -f "$ENV_NODE" ]; then
        backup_env "$ENV_NODE"
        # Update or add DB_HOST
        if grep -q "^DB_HOST=" "$ENV_NODE"; then
            sed -i 's|^DB_HOST=.*|DB_HOST=|' "$ENV_NODE"
        else
            echo "DB_HOST=$RDS_HOST" >> "$ENV_NODE"
        fi
        # Update or add DB_USER
        if grep -q "^DB_USER=" "$ENV_NODE"; then
            sed -i 's|^DB_USER=.*|DB_USER=|' "$ENV_NODE"
        else
            echo "DB_USER=$RDS_USER" >> "$ENV_NODE"
        fi
        # Update or add DB_PASSWORD
        if grep -q "^DB_PASSWORD=" "$ENV_NODE"; then
            sed -i 's|^DB_PASSWORD=.*|DB_PASSWORD=|' "$ENV_NODE"
        else
            echo "DB_PASSWORD=$RDS_PASS" >> "$ENV_NODE"
        fi
        # Update or add DB_NAME
        if grep -q "^DB_NAME=" "$ENV_NODE"; then
            sed -i 's|^DB_NAME=.*|DB_NAME=|' "$ENV_NODE"
        else
            echo "DB_NAME=$RDS_DB" >> "$ENV_NODE"
        fi
        echo "${GREEN}✅ Updated Node environment: $ENV_NODE${NC}"
    fi
    
    echo ""
    echo "${GREEN}✅ Switched to RDS Aurora${NC}"
    echo "${YELLOW}⚠️  Remember to restart PM2 services:${NC}"
    echo "    pm2 restart all"
}

switch_to_local() {
    echo "${YELLOW}Switching back to Local MySQL...${NC}"
    
    # Find most recent backup for R env
    if [ -f "$ENV_R" ]; then
        LATEST_R=$(ls -t ${ENV_R}.backup_* 2>/dev/null | head -1)
        if [ -n "$LATEST_R" ]; then
            cp "$LATEST_R" "$ENV_R"
            echo "${GREEN}✅ Restored R environment from: $LATEST_R${NC}"
        else
            # Manual restoration
            sed -i 's|^host="[^"]*"|host=""|' "$ENV_R"
            sed -i 's|^db_user="[^"]*"|db_user=""|' "$ENV_R"
            sed -i 's|^db_password="[^"]*"|db_password=""|' "$ENV_R"
            sed -i 's|^database="[^"]*"|database=""|' "$ENV_R"
            echo "${GREEN}✅ Manually updated R environment: $ENV_R${NC}"
        fi
    fi
    
    # Find most recent backup for Node env
    if [ -f "$ENV_NODE" ]; then
        LATEST_NODE=$(ls -t ${ENV_NODE}.backup_* 2>/dev/null | head -1)
        if [ -n "$LATEST_NODE" ]; then
            cp "$LATEST_NODE" "$ENV_NODE"
            echo "${GREEN}✅ Restored Node environment from: $LATEST_NODE${NC}"
        else
            # Manual restoration
            sed -i 's|^DB_HOST=.*|DB_HOST=|' "$ENV_NODE"
            sed -i 's|^DB_USER=.*|DB_USER=|' "$ENV_NODE"
            sed -i 's|^DB_PASSWORD=.*|DB_PASSWORD=|' "$ENV_NODE"
            sed -i 's|^DB_NAME=.*|DB_NAME=|' "$ENV_NODE"
            echo "${GREEN}✅ Manually updated Node environment: $ENV_NODE${NC}"
        fi
    fi
    
    echo ""
    echo "${GREEN}✅ Switched back to Local MySQL${NC}"
    echo "${YELLOW}⚠️  Remember to restart PM2 services:${NC}"
    echo "    pm2 restart all"
}

show_status() {
    echo "${YELLOW}Current Database Configuration:${NC}"
    echo ""
    
    echo "${YELLOW}R Environment ($ENV_R):${NC}"
    if [ -f "$ENV_R" ]; then
        echo "  host:     $(grep "^host=" "$ENV_R" | cut -d= -f2 | tr -d '"')"
        echo "  user:     $(grep "^db_user=" "$ENV_R" | cut -d= -f2 | tr -d '"')"
        echo "  database: $(grep "^database=" "$ENV_R" | cut -d= -f2 | tr -d '"')"
    else
        echo "  ${RED}File not found${NC}"
    fi
    
    echo ""
    echo "${YELLOW}Node Environment ($ENV_NODE):${NC}"
    if [ -f "$ENV_NODE" ]; then
        HOST=$(grep "^DB_HOST=" "$ENV_NODE" 2>/dev/null | cut -d= -f2)
        USER=$(grep "^DB_USER=" "$ENV_NODE" 2>/dev/null | cut -d= -f2)
        DB=$(grep "^DB_NAME=" "$ENV_NODE" 2>/dev/null | cut -d= -f2)
        if [ -n "$HOST" ]; then
            echo "  DB_HOST:     $HOST"
            echo "  DB_USER:     $USER"
            echo "  DB_NAME:     $DB"
        else
            echo "  ${YELLOW}No DB_HOST set (uses localhost default)${NC}"
        fi
    else
        echo "  ${RED}File not found${NC}"
    fi
    
    echo ""
    echo "${YELLOW}Detecting current database:${NC}"
    if [ -f "$ENV_R" ]; then
        CURRENT_HOST=$(grep "^host=" "$ENV_R" | cut -d= -f2 | tr -d '"')
        CURRENT_USER=$(grep "^db_user=" "$ENV_R" | cut -d= -f2 | tr -d '"')
        if [[ "$CURRENT_HOST" == *"rds.amazonaws.com"* ]] && [[ "$CURRENT_USER" == "admin" ]]; then
            echo "  ${GREEN}✅ Using RDS Aurora${NC}"
        elif [[ "$CURRENT_HOST" == "localhost" ]] && [[ "$CURRENT_USER" == "richard_clare" ]]; then
            echo "  ${GREEN}✅ Using Local MySQL${NC}"
        else
            echo "  ${YELLOW}⚠️  Unknown configuration${NC}"
        fi
    fi
}

case "$1" in
    on)
        switch_to_rds
        ;;
    off)
        switch_to_local
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {on|off|status}"
        echo ""
        echo "  on     - Switch to RDS Aurora (changes host + credentials)"
        echo "  off    - Switch back to Local MySQL (restores from backup)"
        echo "  status - Show current database configuration"
        exit 1
        ;;
esac
