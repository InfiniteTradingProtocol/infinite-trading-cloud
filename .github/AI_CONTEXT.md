# AI Context - Infinite Trading Cloud

**Last Updated:** April 3, 2026

This file provides critical context for AI assistants working on this codebase.

## 🚨 Critical Information

### EC2 Deployment Architecture

**MOST IMPORTANT - READ THIS FIRST:**

- EC2's `infinitetrading_api/express/` directory is **NOT tracked by git**
- **NEVER** suggest using `git pull` on EC2
- **ALWAYS** use rsync to deploy: `./infinitetrading_api/deploy-to-ec2.sh`
- Files must be manually synced, then built on EC2, then PM2 restarted

### System Architecture

- **Production Server:** EC2 (3.135.99.211) - Ubuntu, Node.js v22.18.0, PM2
- **Database:** MySQL on EC2 (remotely accessible on port 3306)
- **Cache:** Redis v6.0.16 on EC2
- **Main App:** Express API in TypeScript
- **Process Manager:** PM2 (not screen sessions)

### Key Directories

```
infinite-trading-cloud/
├── infinitetrading_api/       # Main API (TypeScript/Express)
│   ├── express/               # NOT IN GIT ON EC2!
│   └── deploy-to-ec2.sh       # Deployment script
├── infinitetrading/           # R-based strategies
├── infinitetrading-sdk/       # SDK for vault interactions
└── .github/                   # AI context (this directory)
```

## 📚 Documentation Index

### Quick References (Read These First)
- **Deployment:** `infinitetrading_api/DEPLOY.md` - Single command deployment
- **Architecture:** `.github/ARCHITECTURE.md` - System overview
- **Common Tasks:** `.github/COMMON_TASKS.md` - Frequent operations

### Detailed Guides (When Needed)
- **API Development:** `.github/guides/API_DEVELOPMENT.md`
- **Deployment Details:** `.github/guides/DEPLOYMENT.md`
- **Troubleshooting:** `.github/guides/TROUBLESHOOTING.md`
- **Testing:** `.github/guides/TESTING.md`

### Historical/Reference (Rarely Needed)
- `DOCS/` - Historical documentation, migration plans, status reports

## 🎯 Quick Commands

### Deploy Changes
```bash
cd infinitetrading_api
./deploy-to-ec2.sh
```

### Check Production
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs infinitetrading-api --lines 50 --nostream"
```

### Emergency Access
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
```

## 🔑 Key Technologies

- **Language:** TypeScript, R, Python
- **Framework:** Express.js
- **Blockchain:** Ethereum, Optimism, Base, Polygon, Arbitrum
- **SDK:** dHEDGE v2-sdk
- **Deployment:** rsync + PM2
- **Cache:** Redis (24h TTL for vault guards)

## ⚠️ Common Mistakes to Avoid

1. **Don't suggest `git pull` on EC2** - express/ isn't in git
2. **Don't forget to build on EC2** - TypeScript must compile there
3. **Don't skip PM2 restart** - Changes won't apply otherwise
4. **Don't assume git sync works** - Use rsync for all deployments
5. **Don't modify both environments separately** - Keep local and EC2 in sync

## 🔍 When to Read What

- **Deploying code?** → Read `DEPLOY.md`
- **Building features?** → Read `API_DEVELOPMENT.md`
- **Errors on EC2?** → Read `TROUBLESHOOTING.md`
- **Understanding system?** → Read `ARCHITECTURE.md`
- **Writing tests?** → Read `TESTING.md`
