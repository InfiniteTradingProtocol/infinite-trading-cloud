# Troubleshooting Guide

## Deployment Issues

### Changes Don't Appear After Deployment

**Symptoms:** Deployed code but logs show old behavior

**Causes:**
1. Forgot to build on EC2
2. PM2 not restarted
3. Files not synced properly

**Solutions:**

```bash
# Check if files were synced
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "ls -la infinitetrading_api/express/src/requests/ | grep trade-fallback"

# Check build timestamp
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "ls -la infinitetrading_api/express/build/src/"

# Rebuild and restart
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd infinitetrading_api/express
npm run build
pm2 restart infinitetrading-api
```

### Build Succeeds But Old Code Runs

**Symptoms:** Build completes successfully, but PM2 shows old behavior

**Cause:** PM2 cache or not restarted properly

**Solution:**

```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Force complete restart
pm2 delete infinitetrading-api
pm2 start ecosystem.config.js

# OR restart with env update
pm2 restart infinitetrading-api --update-env
```

### Module Not Found Errors

**Symptoms:** `Cannot find module 'xyz'` on EC2

**Causes:**
1. New dependency added but package.json not synced
2. npm install not run on EC2
3. TypeScript paths misconfigured

**Solution:**

```bash
# Sync package files
rsync -avz \
  -e "ssh -i ~/.ssh/macbook.pem" \
  infinitetrading_api/express/package.json \
  infinitetrading_api/express/package-lock.json \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:infinitetrading_api/express/

# Install and rebuild
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "cd infinitetrading_api/express && npm install && npm run build && pm2 restart infinitetrading-api"
```

### TypeScript Errors Only on EC2

**Symptoms:** Builds locally but fails on EC2

**Causes:**
1. Partial file sync - some dependencies missing
2. Different TypeScript versions
3. Node version mismatch

**Solution:**

```bash
# Sync ALL source files
rsync -avz --delete \
  -e "ssh -i ~/.ssh/macbook.pem" \
  infinitetrading_api/express/src/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:infinitetrading_api/express/src/

# Check versions match
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "node --version && cd infinitetrading_api/express && npx tsc --version"
```

## Runtime Issues

### Redis Connection Failures

**Symptoms:** `ECONNREFUSED` or Redis timeout errors

**Check:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Check Redis status
redis-cli ping  # Should return PONG

# Restart Redis if needed
sudo systemctl restart redis
```

### PM2 Process Crashes

**Symptoms:** PM2 shows "errored" or "stopped"

**Check:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# View error logs
pm2 logs infinitetrading-api --err --lines 100

# Check for common issues
pm2 logs infinitetrading-api --lines 50 --nostream | grep -i error
```

### Database Connection Issues

**Symptoms:** MySQL connection errors

**Check:**
```bash
# Test connection from local
mysql -urichard_clare -p -h3.135.99.211 infinitetrading -e "SELECT 1;"

# Test from EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
mysql -urichard_clare -p -h127.0.0.1 infinitetrading -e "SELECT 1;"
```

## Performance Issues

### High Memory Usage

**Check:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Check memory
free -h

# Check PM2 process memory
pm2 monit

# Restart if memory leak suspected
pm2 restart infinitetrading-api
```

### Slow Response Times

**Possible Causes:**
1. Rate limiting (ODOS 429 errors)
2. RPC provider issues
3. Database queries slow
4. Cache misses

**Check:**
```bash
# Look for rate limit errors
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api --lines 200 --nostream | grep '429'"

# Check cache hit rate
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api --lines 500 --nostream | grep -i 'using cached'"
```

## Cache System Issues

### Cache Not Working

**Symptoms:** Logs don't show cache hits, always querying on-chain

**Check:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Check if cache keys exist
redis-cli KEYS 'vault:guard:*'

# Check if cache logs appear
pm2 logs infinitetrading-api --lines 200 --nostream | grep -E '(cache|Cache|whitelist)'

# Check if vault-guard files are built
ls -la infinitetrading_api/express/build/src/utils/ | grep vault
```

### Cache Not Expiring

**Check TTL:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
redis-cli TTL 'vault:guard:dex:base'  # Should show seconds remaining
```

## Git/Version Control Issues

### "Git pull doesn't work on EC2"

**This is expected!** The `express/` directory on EC2 is NOT tracked by git.

**Solution:** Use rsync, not git:
```bash
cd infinitetrading_api
./deploy-to-ec2.sh
```

### Local and EC2 Out of Sync

**Symptoms:** Different behavior locally vs production

**Solution:**
```bash
# Deploy to EC2 to sync
cd infinitetrading_api
./deploy-to-ec2.sh

# OR sync specific files
rsync -avz --delete \
  -e "ssh -i ~/.ssh/macbook.pem" \
  infinitetrading_api/express/src/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:infinitetrading_api/express/src/
```

## Getting Help

1. Check logs first: `pm2 logs infinitetrading-api --lines 100`
2. Search for error messages in logs
3. Check PM2 status: `pm2 status`
4. Verify Redis: `redis-cli ping`
5. Test MySQL: `mysql -urichard_clare -p -h3.135.99.211 infinitetrading`
6. Review recent deployments: `git log --oneline -5`
