# Quick Deployment Reference

## The ONE Command You Need

```bash
cd /path/to/infinite-trading-cloud/infinitetrading_api
./deploy-to-ec2.sh
```

That's it! The script handles everything.

---

## What It Does

1. ✓ Checks TypeScript for errors
2. ✓ Tests local build
3. ✓ Syncs files to EC2 via rsync
4. ✓ Builds on EC2
5. ✓ Restarts PM2
6. ✓ Shows logs

---

## ⚠️ CRITICAL: EC2 Architecture

**DO NOT use `git pull` on EC2!**

- The `express/` directory on EC2 is **NOT in git**
- All deployments must use **rsync** or **scp**
- The script does this automatically

---

## Manual Deployment (if script fails)

```bash
# 1. Sync source files
rsync -avz --delete \
  -e "ssh -i ~/.ssh/macmini.pem" \
  src/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:infinitetrading_api/express/src/

# 2. Build on EC2
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "cd infinitetrading_api/express && npm run build && pm2 restart infinitetrading-api"
```

---

## Check Deployment

```bash
# View logs
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api --lines 50 --nostream"

# Check specific feature (e.g., cache)
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api --lines 200 --nostream | grep -i cache"
```

---

## Troubleshooting

### Changes don't appear after deployment?

You probably forgot to build on EC2:

```bash
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd infinitetrading_api/express
npm run build
pm2 restart infinitetrading-api
```

### Module not found errors?

Sync package.json too:

```bash
rsync -avz \
  -e "ssh -i ~/.ssh/macmini.pem" \
  package.json package-lock.json \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:infinitetrading_api/express/

ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "cd infinitetrading_api/express && npm install && npm run build && pm2 restart infinitetrading-api"
```

---

## Full Documentation

See `DOCS/DEVELOPMENT_GUIDE.md` for complete details.
