#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

FILES=(
  "$HOME/infinitetrading/src/.env"
  "$HOME/infinitetrading/src/db/.env"
  "$HOME/infinitetrading/src/api/.env"
  "$HOME/infinitetrading_api/express/.env"
)

case "$1" in
  rds)
    echo "${YELLOW}Switching to RDS...${NC}"
    for f in "${FILES[@]}"; do
      if [ -f "${f}.rds" ]; then
        cp "${f}.rds" "$f"
        echo "${GREEN}✅ $f${NC}"
      fi
    done
    echo "${GREEN}✅ All files switched to RDS${NC}"
    echo "${YELLOW}Run: pm2 restart all${NC}"
    ;;
  local)
    echo "${YELLOW}Switching to Local MySQL...${NC}"
    for f in "${FILES[@]}"; do
      if [ -f "${f}.local" ]; then
        cp "${f}.local" "$f"
        echo "${GREEN}✅ $f${NC}"
      fi
    done
    echo "${GREEN}✅ All files switched to Local${NC}"
    echo "${YELLOW}Run: pm2 restart all${NC}"
    ;;
  status)
    echo "${YELLOW}Current database:${NC}"
    host=$(grep "^host=" ~/infinitetrading/src/.env 2>/dev/null | cut -d= -f2 | tr -d '"')
    user=$(grep "^db_user=" ~/infinitetrading/src/.env 2>/dev/null | cut -d= -f2 | tr -d '"')
    if [[ "$host" == *"rds.amazonaws.com"* ]] && [[ "$user" == "admin" ]]; then
      echo "${GREEN}✅ RDS Aurora${NC}"
    elif [[ "$host" == "localhost" ]] && [[ "$user" == "richard_clare" ]]; then
      echo "${GREEN}✅ Local MySQL${NC}"
    else
      echo "${RED}❌ Unknown${NC}"
    fi
    ;;
  *)
    echo "Usage: $0 {rds|local|status}"
    exit 1
    ;;
esac
