#!/bin/bash

# Test individual service with RDS
# Usage: ./test_service_with_rds.sh <service-name>

SERVICE=$1
RDS_HOST="infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com"

if [ -z "$SERVICE" ]; then
    echo "Usage: $0 <service-name>"
    echo ""
    echo "Available services:"
    pm2 list | grep -E "online|stopped" | awk "{print \$4}" | grep -v "name"
    exit 1
fi

echo "========================================="
echo "Testing: ${SERVICE} with RDS"
echo "========================================="

# Get current status
echo ""
echo "Current status:"
pm2 info ${SERVICE} | grep -E "status|restarts|uptime|memory"

# Test RDS connectivity
echo ""
echo "Testing RDS connectivity..."
if mysql -h${RDS_HOST} -P3306 -uadmin -p"NcwbBmT5Vxv9ZAx" --ssl-ca=/certs/global-bundle.pem infinitetrading -e "SELECT 1;" 2>/dev/null; then
    echo "✅ RDS connection successful"
else
    echo "❌ RDS connection failed"
    exit 1
fi

echo ""
echo "Service is ready for RDS migration."
echo ""
echo "To migrate this service:"
echo "1. Stop: pm2 stop ${SERVICE}"
echo "2. Update .env to use RDS"
echo "3. Start: pm2 restart ${SERVICE}"
echo "4. Monitor: pm2 logs ${SERVICE} --lines 50"
echo ""

