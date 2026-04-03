# Deployment Guide

## Quick Deploy

```bash
cd infinitetrading_api
./deploy-to-ec2.sh
```

## What the Script Does

1. ✓ Verifies Node.js version
2. ✓ Checks TypeScript for errors
3. ✓ Tests local build
4. ✓ Syncs files via rsync to EC2
5. ✓ Installs dependencies on EC2
6. ✓ Builds TypeScript on EC2
7. ✓ Restarts PM2
8. ✓ Shows deployment logs

## Manual Deployment

If the script fails or you need more control:

### 1. Test Locally

```bash
cd infinitetrading_api/express

# Check for TypeScript errors
npx tsc --noEmit

# Test build
npm run build
```

### 2. Sync Files to EC2

```bash
# Sync source files
rsync -avz --delete \
  -e "ssh -i ~/.ssh/macbook.pem" \
  src/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:infinitetrading_api/express/src/

# Sync package files
rsync -avz \
  -e "ssh -i ~/.ssh/macbook.pem" \
  package.json tsconfig.json \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:infinitetrading_api/express/
```

### 3. Build on EC2

```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd infinitetrading_api/express
npm install
npm run build
pm2 restart infinitetrading-api
```

## Post-Deployment Verification

```bash
# Check PM2 status
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "pm2 status"

# View recent logs
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api --lines 50 --nostream"

# Check specific feature (e.g., cache)
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api --lines 200 --nostream | grep -i cache"
```

## Deployment Checklist

Before deploying:

- [ ] Tested locally with `npm run start:watch`
- [ ] No TypeScript errors (`npx tsc --noEmit`)
- [ ] Local build succeeds (`npm run build`)
- [ ] Changes committed to git
- [ ] .env configured if needed

After deploying:

- [ ] PM2 status shows "online"
- [ ] Recent logs show no errors
- [ ] Test endpoint responds correctly
- [ ] New features appear in logs

## Emergency Rollback

If something breaks:

```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd infinitetrading_api/express

# Quick restart
pm2 restart infinitetrading-api

# If that doesn't work, rebuild
npm run build
pm2 restart infinitetrading-api

# If still broken, check logs
pm2 logs infinitetrading-api --lines 100 --nostream
```

## ⚠️ Critical Deployment Facts

1. **EC2's `express/` directory is NOT in git**
   - Don't suggest `git pull` on EC2
   - Always use rsync to sync files

2. **Build must happen on EC2**
   - TypeScript compiles to JavaScript
   - Build directory is gitignored
   - Source files alone won't work

3. **PM2 restart is required**
   - Node.js won't pick up changes until restart
   - Check PM2 status after restart

4. **Dependencies must be synced**
   - If you add npm packages, sync package.json
   - Run `npm install` on EC2 before building

## Common Deployment Issues

See `TROUBLESHOOTING.md` for solutions to:
- Changes don't appear after deployment
- Build fails on EC2
- Module not found errors
- PM2 shows old code running
