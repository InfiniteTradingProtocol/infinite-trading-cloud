#!/bin/bash
# Download missing files from EC2 before migration
# Run this from the repo root: /Users/richardclare/infinite-trading-api

set -e

EC2_HOST="ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com"
SSH_KEY="~/.ssh/macbook.pem"

echo "🔍 Downloading missing files from EC2..."
echo ""

# Create temp directory
mkdir -p /tmp/ec2_downloads

# Download main.R (critical dependency for strategies)
echo "📥 Downloading strategies/main.R..."
scp -i $SSH_KEY $EC2_HOST:~/infinitetrading/src/strategies/main.R /tmp/ec2_downloads/main.R

if [ -f /tmp/ec2_downloads/main.R ]; then
    echo "✅ Downloaded main.R"
    echo ""
    echo "📝 Contents preview:"
    head -20 /tmp/ec2_downloads/main.R
    echo ""
    echo "⚠️  MANUAL ACTION REQUIRED:"
    echo "   1. Review /tmp/ec2_downloads/main.R"
    echo "   2. Update hardcoded paths (~/infinitetrading/src/)"
    echo "   3. Copy to strategies/strategies/main.R"
    echo "   4. Test locally before deploying"
else
    echo "❌ Failed to download main.R"
    exit 1
fi

echo ""
echo "🔍 Checking for other potential missing files..."

# Check if slack.R exists (referenced in tradebot/index.R)
echo "📥 Checking for slack.R..."
scp -i $SSH_KEY $EC2_HOST:~/infinitetrading/src/slack.R /tmp/ec2_downloads/slack.R 2>/dev/null || echo "⚠️  slack.R not found on EC2"

# List all files in infinitetrading/src to see what else might be missing
echo ""
echo "📋 Getting full file list from EC2..."
ssh -i $SSH_KEY $EC2_HOST "find ~/infinitetrading/src -type f -name '*.R' -o -name '*.py' -o -name '*.sh'" > /tmp/ec2_downloads/file_list.txt

echo ""
echo "✅ File list saved to /tmp/ec2_downloads/file_list.txt"
echo ""
echo "📝 Files found on EC2:"
cat /tmp/ec2_downloads/file_list.txt

echo ""
echo "🎯 Next steps:"
echo "   1. Review downloaded files in /tmp/ec2_downloads/"
echo "   2. Check file_list.txt for any other missing files"
echo "   3. Update paths in downloaded files"
echo "   4. Copy to appropriate locations in repo"
echo "   5. Test locally"
