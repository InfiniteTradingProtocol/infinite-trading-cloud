#!/bin/bash

# RDS Migration Testing Script
# Tests all critical functions after switching to RDS

echo "========================================="
echo "RDS Migration Test Suite"
echo "========================================="

TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $2"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $2"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Check RDS connectivity
echo ""
echo "Test 1: RDS Connectivity"
echo "------------------------"
mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com \
    -P 3306 -u admin -p"NcwbBmT5Vxv9ZAx" \
    --ssl-ca=/certs/global-bundle.pem \
    -e "SELECT 1 as test;" > /dev/null 2>&1
test_result $? "RDS connection"

# Test 2: Check database exists
echo ""
echo "Test 2: Database Schema"
echo "------------------------"
DB_EXISTS=$(mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com \
    -P 3306 -u admin -p"NcwbBmT5Vxv9ZAx" \
    --ssl-ca=/certs/global-bundle.pem \
    -e "SHOW DATABASES LIKE 'infinitetrading';" 2>/dev/null | grep -c infinitetrading)
test_result $([[ $DB_EXISTS -eq 1 ]] && echo 0 || echo 1) "Database exists"

# Test 3: Check table count
echo ""
echo "Test 3: Table Count"
echo "------------------------"
TABLE_COUNT=$(mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com \
    -P 3306 -u admin -p"NcwbBmT5Vxv9ZAx" \
    --ssl-ca=/certs/global-bundle.pem infinitetrading \
    -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='infinitetrading';" 2>/dev/null)
echo "Found $TABLE_COUNT tables"
test_result $([[ $TABLE_COUNT -gt 50 ]] && echo 0 || echo 1) "Sufficient tables ($TABLE_COUNT > 50)"

# Test 4: PM2 Services Status
echo ""
echo "Test 4: PM2 Services"
echo "------------------------"
SERVICES_ONLINE=$(pm2 jlist 2>/dev/null | grep -c '\"status\":\"online\"')
SERVICES_TOTAL=$(pm2 jlist 2>/dev/null | grep -c '\"name\"')
echo "Services online: $SERVICES_ONLINE / $SERVICES_TOTAL"
test_result $([[ $SERVICES_ONLINE -eq $SERVICES_TOTAL ]] && echo 0 || echo 1) "All PM2 services online"

# Test 5: Check for PM2 restart loops
echo ""
echo "Test 5: Service Stability"
echo "------------------------"
RESTARTING=$(pm2 list 2>/dev/null | grep -c "restart")
if pm2 list 2>/dev/null | grep -q "errored"; then
    test_result 1 "No errored services"
else
    test_result 0 "No errored services"
fi

# Test 6: Check candles data
echo ""
echo "Test 6: Candle Data"
echo "------------------------"
CANDLE_TABLES=$(mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com \
    -P 3306 -u admin -p"NcwbBmT5Vxv9ZAx" \
    --ssl-ca=/certs/global-bundle.pem infinitetrading \
    -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='infinitetrading' AND table_name LIKE 'coinbase_%';" 2>/dev/null)
echo "Found $CANDLE_TABLES candle tables"
test_result $([[ $CANDLE_TABLES -gt 10 ]] && echo 0 || echo 1) "Candle tables exist ($CANDLE_TABLES > 10)"

# Test 7: Check dhedge tables
echo ""
echo "Test 7: Trading Tables"
echo "------------------------"
DHEDGE_TABLES=$(mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com \
    -P 3306 -u admin -p"NcwbBmT5Vxv9ZAx" \
    --ssl-ca=/certs/global-bundle.pem infinitetrading \
    -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='infinitetrading' AND table_name LIKE '%dhedge%';" 2>/dev/null)
echo "Found $DHEDGE_TABLES dhedge tables"
test_result $([[ $DHEDGE_TABLES -gt 5 ]] && echo 0 || echo 1) "Trading tables exist ($DHEDGE_TABLES > 5)"

# Test 8: Check recent data updates
echo ""
echo "Test 8: Recent Data Activity"
echo "------------------------"
RECENT_UPDATES=$(mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com \
    -P 3306 -u admin -p"NcwbBmT5Vxv9ZAx" \
    --ssl-ca=/certs/global-bundle.pem infinitetrading \
    -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='infinitetrading' AND update_time > DATE_SUB(NOW(), INTERVAL 1 HOUR);" 2>/dev/null)
echo "Tables updated in last hour: $RECENT_UPDATES"
test_result $([[ $RECENT_UPDATES -gt 0 ]] && echo 0 || echo 1) "Recent updates detected"

# Test 9: Check PM2 logs for errors
echo ""
echo "Test 9: Recent PM2 Errors"
echo "------------------------"
ERROR_COUNT=$(pm2 logs --nostream --lines 100 2>/dev/null | grep -i error | grep -v "ERROR 2006" | wc -l)
echo "Recent errors in logs: $ERROR_COUNT"
test_result $([[ $ERROR_COUNT -lt 5 ]] && echo 0 || echo 1) "Low error count ($ERROR_COUNT < 5)"

# Summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✅ All tests passed! RDS migration successful."
    exit 0
else
    echo "⚠️  Some tests failed. Review above and consider rollback:"
    echo "   ~/switch_to_rds.sh off"
    echo "   pm2 restart all"
    exit 1
fi

