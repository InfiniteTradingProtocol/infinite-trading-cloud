#!/bin/bash
# Clean EC2 Deployment Script
# This safely deploys the entire monorepo to EC2 with proper backup

set -e  # Exit on any error

EC2_HOST="ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com"
EC2_KEY="~/.ssh/macbook.pem"
REPO_NAME="infinite-trading-api"
BACKUP_DIR="/home/ubuntu/backup_$(date +%Y%m%d_%H%M%S)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     🚀 CLEAN EC2 DEPLOYMENT WITH BACKUP                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Create AMI Snapshot (you do this manually in AWS Console)
echo "⚠️  MANUAL STEP REQUIRED:"
echo "   1. Go to AWS Console → EC2 → Instances"
echo "   2. Select your instance"
echo "   3. Actions → Image and templates → Create image"
echo "   4. Name: 'prod-backup-$(date +%Y%m%d)'"
echo "   5. Wait for AMI to be 'available' (5-10 min)"
echo ""
read -p "Have you created the AMI snapshot? (yes/no): " confirm
if [[ $confirm != "yes" ]]; then
    echo "❌ Deployment cancelled. Please create AMI snapshot first."
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Step 1: Stop all running services on EC2"
echo "════════════════════════════════════════════════════════════"
ssh -i $EC2_KEY $EC2_HOST << 'ENDSSH'
    echo "Stopping PM2 processes..."
    pm2 stop all 2>/dev/null || echo "No PM2 processes running"
    
    echo "Stopping forever processes..."
    forever stopall 2>/dev/null || echo "No forever processes running"
    
    echo "Killing any remaining R processes..."
    pkill -f "Rscript" 2>/dev/null || echo "No R processes running"
    
    echo "Killing any remaining node processes (except PM2)..."
    pkill -f "node.*infinite" 2>/dev/null || echo "No node processes"
    
    echo "✅ All services stopped"
ENDSSH

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Step 2: Create backup of current code"
echo "════════════════════════════════════════════════════════════"
ssh -i $EC2_KEY $EC2_HOST << ENDSSH
    echo "Creating backup directory: $BACKUP_DIR"
    mkdir -p $BACKUP_DIR
    
    # Backup old infinitetrading repo
    if [ -d /home/ubuntu/infinitetrading/src ]; then
        echo "Backing up /home/ubuntu/infinitetrading/src..."
        cp -r /home/ubuntu/infinitetrading/src $BACKUP_DIR/infinitetrading_src_backup
    fi
    
    # Backup infinitetrading_api repo
    if [ -d /home/ubuntu/infinitetrading_api ]; then
        echo "Backing up /home/ubuntu/infinitetrading_api..."
        cp -r /home/ubuntu/infinitetrading_api $BACKUP_DIR/infinitetrading_api_backup
    fi
    
    # Backup ALL .env files from both repos
    echo "Backing up .env files..."
    mkdir -p $BACKUP_DIR/env_files
    
    # Backup all .env files with their full paths preserved
    for env_file in \
      /home/ubuntu/.env \
      /home/ubuntu/infinitetrading/src/.env \
      /home/ubuntu/infinitetrading/src/executor/.env \
      /home/ubuntu/infinitetrading/src/api/.env \
      /home/ubuntu/infinitetrading/src/api/gateway/.env \
      /home/ubuntu/infinitetrading/defi/.env \
      /home/ubuntu/infinitetrading_api/express/.env \
      /home/ubuntu/infinitetrading_api/express/src/sugar/.env
    do
      if [ -f "\$env_file" ]; then
        dir_path=\$(dirname "\$env_file")
        mkdir -p "$BACKUP_DIR/env_files\$dir_path"
        cp "\$env_file" "$BACKUP_DIR/env_files\$env_file"
        echo "  ✓ Backed up: \$env_file"
      fi
    done
    
    # Backup PM2 ecosystem files
    if [ -f /home/ubuntu/infinitetrading_api/express/ecosystem.config.js ]; then
        cp /home/ubuntu/infinitetrading_api/express/ecosystem.config.js $BACKUP_DIR/
    fi
    
    echo "✅ Backup created at: $BACKUP_DIR"
    echo "   To restore: cp -r $BACKUP_DIR/* /home/ubuntu/"
ENDSSH

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Step 3: Setup Git monorepo on EC2"
echo "════════════════════════════════════════════════════════════"
ssh -i $EC2_KEY $EC2_HOST << 'ENDSSH'
    cd /home/ubuntu
    
    # Remove old repo if it exists
    if [ -d infinite-trading-api ]; then
        echo "Removing old infinite-trading-api directory..."
        rm -rf infinite-trading-api
    fi
    
    echo "Cloning fresh repository..."
    git clone https://github.com/etherpilled/infinite-trading-api.git
    cd infinite-trading-api
    
    echo "✅ Git repository cloned"
ENDSSH

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Step 4: Sync local files to EC2 (rsync)"
echo "════════════════════════════════════════════════════════════"

# Sync all folders except node_modules, .git, logs, tmp
rsync -avz --progress \
    --exclude 'node_modules' \
    --exclude '.git' \
    --exclude '*.log' \
    --exclude 'logs/*' \
    --exclude 'tmp/*' \
    --exclude '.DS_Store' \
    --exclude '*.swp' \
    --exclude '*.swo' \
    --exclude '*.swm' \
    -e "ssh -i $EC2_KEY" \
    ./ $EC2_HOST:/home/ubuntu/infinite-trading-api/

echo "✅ Files synced to EC2"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Step 5: Restore .env and credentials to new locations"
echo "════════════════════════════════════════════════════════════"
ssh -i $EC2_KEY $EC2_HOST << ENDSSH
    cd /home/ubuntu/infinite-trading-api
    
    echo "Restoring .env files from backup..."
    
    # Create necessary directories in new structure
    mkdir -p express/src/sugar
    mkdir -p plumber
    mkdir -p data-collectors/db
    
    # Map old .env locations to new monorepo structure
    # Priority: Use backed up files, they have the real credentials
    
    # 1. Root .env (main credentials)
    if [ -f $BACKUP_DIR/env_files/home/ubuntu/infinitetrading/src/.env ]; then
        echo "✓ Restoring main .env from infinitetrading/src/.env"
        cp $BACKUP_DIR/env_files/home/ubuntu/infinitetrading/src/.env /home/ubuntu/infinite-trading-api/.env
    elif [ -f $BACKUP_DIR/env_files/home/ubuntu/infinitetrading_api/express/.env ]; then
        echo "✓ Restoring main .env from express/.env"
        cp $BACKUP_DIR/env_files/home/ubuntu/infinitetrading_api/express/.env /home/ubuntu/infinite-trading-api/.env
    fi
    
    # 2. Express .env
    if [ -f $BACKUP_DIR/env_files/home/ubuntu/infinitetrading_api/express/.env ]; then
        echo "✓ Restoring express/.env"
        cp $BACKUP_DIR/env_files/home/ubuntu/infinitetrading_api/express/.env /home/ubuntu/infinite-trading-api/express/.env
    fi
    
    # 3. Sugar .env (large file with many keys)
    if [ -f $BACKUP_DIR/env_files/home/ubuntu/infinitetrading_api/express/src/sugar/.env ]; then
        echo "✓ Restoring express/src/sugar/.env (contains many API keys)"
        cp $BACKUP_DIR/env_files/home/ubuntu/infinitetrading_api/express/src/sugar/.env /home/ubuntu/infinite-trading-api/express/src/sugar/.env
    fi
    
    # 4. API gateway .env (if plumber needs it)
    if [ -f $BACKUP_DIR/env_files/home/ubuntu/infinitetrading/src/api/.env ]; then
        echo "✓ Restoring plumber/.env from api/.env"
        cp $BACKUP_DIR/env_files/home/ubuntu/infinitetrading/src/api/.env /home/ubuntu/infinite-trading-api/plumber/.env
    fi
    
    # 5. Data collectors .env
    if [ -f $BACKUP_DIR/env_files/home/ubuntu/infinitetrading/src/.env ]; then
        echo "✓ Restoring data-collectors/.env"
        cp $BACKUP_DIR/env_files/home/ubuntu/infinitetrading/src/.env /home/ubuntu/infinite-trading-api/data-collectors/.env
    fi
    
    # 6. Also keep backup in home directory
    if [ -f $BACKUP_DIR/env_files/home/ubuntu/.env ]; then
        cp $BACKUP_DIR/env_files/home/ubuntu/.env /home/ubuntu/.env
    fi
    
    echo ""
    echo "Verifying restored .env files:"
    for file in \
      /home/ubuntu/infinite-trading-api/.env \
      /home/ubuntu/infinite-trading-api/express/.env \
      /home/ubuntu/infinite-trading-api/express/src/sugar/.env \
      /home/ubuntu/infinite-trading-api/plumber/.env \
      /home/ubuntu/infinite-trading-api/data-collectors/.env
    do
      if [ -f "\$file" ]; then
        size=\$(wc -c < "\$file")
        echo "  ✓ \$file (\${size} bytes)"
      else
        echo "  ⚠️  Missing: \$file"
      fi
    done
    
    echo ""
    echo "✅ Credentials restored to new monorepo structure"
ENDSSH

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Step 6: Install dependencies"
echo "════════════════════════════════════════════════════════════"
ssh -i $EC2_KEY $EC2_HOST << 'ENDSSH'
    cd /home/ubuntu/infinite-trading-api
    
    # Install Node dependencies for express
    echo "Installing Node.js dependencies..."
    cd express
    npm install
    npm run build
    
    # Install R packages if needed
    echo "Checking R packages..."
    Rscript -e "required <- c('httr', 'jsonlite', 'lubridate', 'TTR', 'quantmod', 'DBI', 'RMariaDB', 'dotenv', 'plumber'); for (pkg in required) { if (!require(pkg, quietly=TRUE)) install.packages(pkg, repos='http://cran.rstudio.com/') }"
    
    # Install Python dependencies for data-collectors
    echo "Installing Python dependencies..."
    cd /home/ubuntu/infinite-trading-api/data-collectors/db
    pip3 install -r requirements.txt 2>/dev/null || pip3 install mysql-connector-python python-dotenv requests
    
    echo "✅ Dependencies installed"
ENDSSH

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Step 7: Update PM2 ecosystem config"
echo "════════════════════════════════════════════════════════════"
ssh -i $EC2_KEY $EC2_HOST << 'ENDSSH'
    cd /home/ubuntu/infinite-trading-api/express
    
    # Update paths in ecosystem.config.js if needed
    echo "Updating PM2 configuration..."
    
    # Reload PM2 config
    pm2 delete all 2>/dev/null || true
    pm2 start ecosystem.config.js
    pm2 save
    
    echo "✅ PM2 configured"
ENDSSH

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Step 8: Test services"
echo "════════════════════════════════════════════════════════════"
ssh -i $EC2_KEY $EC2_HOST << 'ENDSSH'
    cd /home/ubuntu/infinite-trading-api
    
    echo "Testing strategy loading..."
    Rscript -e "source('strategies/main.R'); cat('✅ main.R loaded\n')"
    
    echo ""
    echo "Testing plumber API..."
    Rscript -e "library(plumber); cat('✅ Plumber available\n')"
    
    echo ""
    echo "PM2 status:"
    pm2 status
    
    echo ""
    echo "✅ Services tested"
ENDSSH

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Step 9: Stop old screen sessions and start PM2 services"
echo "════════════════════════════════════════════════════════════"
ssh -i $EC2_KEY $EC2_HOST << 'ENDSSH'
    cd /home/ubuntu/infinite-trading-api
    
    echo "Stopping old screen sessions (if any)..."
    screen -S candles -X quit 2>/dev/null || echo "No candles screen session"
    screen -S messages -X quit 2>/dev/null || echo "No messages screen session"
    
    echo ""
    echo "Starting all PM2 services (including data collectors)..."
    pm2 restart all
    
    echo ""
    echo "✅ All services started"
    echo ""
    pm2 status
ENDSSH

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    ✅ DEPLOYMENT COMPLETE                  ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  Backup location: $BACKUP_DIR                              ║"
echo "║                                                            ║"
echo "║  To rollback:                                              ║"
echo "║    ssh $EC2_HOST                                           ║"
echo "║    pm2 stop all                                            ║"
echo "║    rm -rf /home/ubuntu/infinite-trading-api                ║"
echo "║    cp -r $BACKUP_DIR/* /home/ubuntu/                       ║"
echo "║    pm2 restart all                                         ║"
echo "║                                                            ║"
echo "║  Or restore from AMI snapshot (see instructions below)     ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📝 Monitor logs:"
echo "   ssh $EC2_HOST 'pm2 logs'"
echo "   ssh $EC2_HOST 'pm2 logs candles-collector'"
echo "   ssh $EC2_HOST 'pm2 logs messages-collector'"
echo ""
