# Common Tasks

Quick reference for frequent operations.

## Deploy Code Changes

```bash
cd infinitetrading_api
./deploy-to-ec2.sh
```

That's it! The script handles everything.

## Check Production Status

```bash
# View PM2 status
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "pm2 status"

# View recent logs
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api --lines 50 --nostream"

# Monitor live logs
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api"
```

## Check Specific Features

### Cache System
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api --lines 200 --nostream | grep -i cache"
```

### Redis Keys
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "redis-cli KEYS 'vault:guard:*'"
```

### Check Cached Value
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "redis-cli GET 'vault:guard:dex:base'"
```

## Local Development

### Start Dev Server
```bash
cd infinitetrading_api/express
npm run start:watch
```

### Run TypeScript Checks
```bash
cd infinitetrading_api/express
npx tsc --noEmit
```

### Test Build
```bash
cd infinitetrading_api/express
npm run build
```

## Database Queries

### Connect to MySQL
```bash
mysql -urichard_clare -p -h3.135.99.211 infinitetrading
```

### Check Candle Data
```bash
mysql -urichard_clare -p -h3.135.99.211 infinitetrading -e "
SELECT TABLE_NAME, TABLE_ROWS 
FROM information_schema.TABLES 
WHERE TABLE_SCHEMA = 'infinitetrading' 
AND TABLE_NAME LIKE 'coinbase_%'
ORDER BY TABLE_NAME;
"
```

## Emergency Procedures

### Restart PM2 Service
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
pm2 restart infinitetrading-api
```

### Rebuild on EC2
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd infinitetrading_api/express
npm run build
pm2 restart infinitetrading-api
```

### Check System Resources
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
htop  # or top
df -h  # disk space
free -h  # memory
```

## Testing Endpoints

### Local Test
```bash
curl "http://localhost:8000/trade?network=polygon&pool=0x..."
```

### Production Test
Replace `localhost:8000` with EC2 IP or domain.

## Git Operations

### Commit Changes
```bash
git add -A
git commit -m "Your message"
git push
```

### Check Status
```bash
git status
git log --oneline -5
```

## File Sync (Manual)

If deployment script fails:

```bash
# Sync source
rsync -avz --delete \
  -e "ssh -i ~/.ssh/macbook.pem" \
  infinitetrading_api/express/src/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:infinitetrading_api/express/src/

# Sync package files
rsync -avz \
  -e "ssh -i ~/.ssh/macbook.pem" \
  infinitetrading_api/express/package.json \
  infinitetrading_api/express/tsconfig.json \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:infinitetrading_api/express/
```
