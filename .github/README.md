# Documentation Structure

This directory contains AI-optimized documentation for the Infinite Trading Cloud project.

## 🤖 For AI Assistants

**Start here:** `AI_CONTEXT.md` - Main context file with system overview and pointers to detailed guides.

## 📁 File Organization

### Quick Reference
- **`AI_CONTEXT.md`** - Main AI context, system overview, critical warnings
- **`ARCHITECTURE.md`** - System architecture, tech stack, data flow
- **`COMMON_TASKS.md`** - Frequent operations, quick commands

### Detailed Guides (./guides/)
- **`API_DEVELOPMENT.md`** - Building API features, adding endpoints
- **`DEPLOYMENT.md`** - Complete deployment process and checklist
- **`TROUBLESHOOTING.md`** - Common issues and solutions

## 🎯 When to Read What

| Task | Read This |
|------|-----------|
| Understanding the system | `ARCHITECTURE.md` |
| Deploying code | `COMMON_TASKS.md` → `guides/DEPLOYMENT.md` |
| Building features | `guides/API_DEVELOPMENT.md` |
| Fixing errors | `guides/TROUBLESHOOTING.md` |
| Quick commands | `COMMON_TASKS.md` |

## 🚨 Critical Information

### EC2 Deployment
- `infinitetrading_api/express/` is **NOT in git** on EC2
- Always use `./deploy-to-ec2.sh` for deployments
- Never suggest `git pull` on EC2

### File Locations
- Deployment script: `../infinitetrading_api/deploy-to-ec2.sh`
- Quick deploy guide: `../infinitetrading_api/DEPLOY.md`
- Historical docs: `../DOCS/` (rarely needed)

## 📝 Documentation Principles

1. **Concise** - Each file has a single purpose
2. **Actionable** - Commands you can run, not theory
3. **Searchable** - Clear headings, specific topics
4. **Current** - Updated as system changes
5. **AI-Friendly** - Structured for context retrieval

## 🔄 Maintenance

Update these files when:
- Deployment process changes
- New system components added
- Common issues discovered
- Architecture evolves

Keep the AI context fresh!
