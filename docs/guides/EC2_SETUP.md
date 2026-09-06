# EC2 Setup Instructions

## Initial Setup (Run Once)

### 1. Set up Git on EC2

SSH into EC2:
```bash
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
```

Configure Git:
```bash
cd /home/ubuntu/infinitetrading

# Initialize git repo
git init

# Set up remote (read-only HTTPS)
git remote add origin https://github.com/etherpilled/infinite-trading-cloud.git

# Configure to pull without conflicts
git config pull.rebase false

# Fetch and checkout
git fetch origin
git reset --hard origin/main
```

### 2. Create .gitignore on EC2

```bash
cd /home/ubuntu/infinitetrading

cat > .gitignore << 'EOF'
# Environment & Secrets
.env*
*.pem

# Logs
logs/
*.log

# Node
node_modules/
build/

# PM2
.pm2/

# Cache
.cache/
.npm/

# Bash history
.bash_history
EOF
```

### 3. Configure Git to Preserve Local Changes

To prevent conflicts with local .env and logs:

```bash
cd /home/ubuntu/infinitetrading

# Assume these files are unchanged (even if modified locally)
git update-index --assume-unchanged .env.production
git update-index --assume-unchanged src/express/.env

# If you need to track them again later:
# git update-index --no-assume-unchanged <file>
```

## Deployment Workflow

### From Local Machine

1. **Make changes** in `infinitetrading/` (the R strategies tree)

2. **Deploy using script:**
   ```bash
   cd ~/infinite-trading-cloud
   
   # Deploy and restart only APIs
   ./deploy.sh "fix: update trade logic" --restart-api
   
   # Deploy and restart all services
   ./deploy.sh "feat: new strategy bot" --restart-all
   
   # Deploy and restart only strategy bots
   ./deploy.sh "fix: strategy parameter" --restart-strategies
   ```

3. **Or deploy manually:**
   ```bash
   git add infinitetrading/src/api/db.R
   git commit -m "fix: connection pool exhaustion"
   git push origin main
   
   ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
   cd /home/ubuntu/infinitetrading
   git pull origin main
   pm2 restart infinitetrading-api
   ```

## Common Commands

### Check Deployment Status on EC2

```bash
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "pm2 status"
```

### View Logs

```bash
# Specific service
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "pm2 logs infinitetrading-api --lines 50"

# All services
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "pm2 logs --lines 20"
```

### Pull Latest Changes Manually

```bash
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com << 'EOF'
  cd /home/ubuntu/infinitetrading
  git stash  # Save any local changes
  git pull origin main
  git stash pop  # Restore local changes
  pm2 restart all
EOF
```

## File Structure Mapping

```
Local:                          EC2:
infinite-trading-cloud/    →    /home/
├── ubuntu/                →    └── ubuntu/
│   └── infinitetrading/   →        └── infinitetrading/
│       ├── src/          →            ├── src/
│       │   ├── api/      →            │   ├── api/
│       │   ├── express/  →            │   ├── express/
│       │   └── ...       →            │   └── ...
│       └── ...           →            └── ...
└── DOCS/                 (local only, not deployed)
```

## Troubleshooting

### Git Pull Fails with "local changes"

```bash
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com << 'EOF'
  cd /home/ubuntu/infinitetrading
  git reset --hard origin/main
EOF
```

### PM2 Process Won't Start

```bash
# Check logs
pm2 logs <process-name> --lines 100

# Delete and restart
pm2 delete <process-name>
pm2 start ecosystem_prod.config.js --only <process-name>
```

### Node Modules Out of Sync

```bash
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com << 'EOF'
  cd /home/ubuntu/infinitetrading_api/express
  rm -rf node_modules package-lock.json
  npm install --production
  pm2 restart infinitetrading-api
EOF
```

## Security Notes

- **Never commit `.env` files** - they're in .gitignore
- **Never commit `.pem` SSH keys**
- **Keep API keys out of code** - use environment variables
- **The EC2 instance has read-only access** to GitHub (HTTPS clone)

## Quick Reference

| Action | Command |
|--------|---------|
| Deploy all changes | `./deploy.sh "message" --restart-all` |
| Deploy API only | `./deploy.sh "message" --restart-api` |
| Deploy strategies only | `./deploy.sh "message" --restart-strategies` |
| Check EC2 status | `ssh ubuntu@EC2 "pm2 status"` |
| View logs | `ssh ubuntu@EC2 "pm2 logs <name>"` |
| Manual pull | `ssh ubuntu@EC2 "cd /home/ubuntu/infinitetrading && git pull"` |
