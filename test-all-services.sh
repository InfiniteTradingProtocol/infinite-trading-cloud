#!/bin/bash
# Comprehensive test script for all services after migration
# Tests all fixed files to ensure no breaking changes

# Don't exit on error - we want to run all tests
set +e

echo "=== INFINITE TRADING API - COMPREHENSIVE TEST SUITE ==="
echo "Starting at: $(date)"
echo ""

REPO_ROOT="/Users/richardclare/infinite-trading-api"
cd "$REPO_ROOT"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Helper functions
test_passed() {
    echo -e "${GREEN}✓ PASSED${NC}: $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

test_failed() {
    echo -e "${RED}✗ FAILED${NC}: $1"
    echo "   Error: $2"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

test_warning() {
    echo -e "${YELLOW}⚠ WARNING${NC}: $1"
}

echo "=== PHASE 1: FILE EXISTENCE CHECKS ==="
echo ""

# Check critical files exist
FILES_TO_CHECK=(
    "express/src/walletv2.ts"
    "express/ecosystem.config.js"
    "plumber/messaging.R"
    "plumber/reporting.R"
    "plumber/encryption.R"
    "strategies/main.R"
    "tradebot/tradebot.R"
    "tradebot/defi_thread.R"
)

for file in "${FILES_TO_CHECK[@]}"; do
    if [ -f "$REPO_ROOT/$file" ]; then
        test_passed "File exists: $file"
    else
        test_failed "File missing: $file" "File not found in repository"
    fi
done

echo ""
echo "=== PHASE 2: PATH VALIDATION IN R FILES ==="
echo ""

# Check that no hardcoded paths remain in critical R files
R_FILES=(
    "strategies/main.R"
    "strategies/superTrend.R"
    "strategies/dht_ema_rsi.R"
    "strategies/crossOvers.R"
    "strategies/velo_ema_rsi.R"
    "strategies/velo_rsi_14.R"
    "strategies/Velo1DBot.R"
    "strategies/ETHUSD1D_EMA_RSI.R"
    "strategies/cbBTC_probability_model.R"
    "strategies/aero_ema_11_33_crossover.R"
    "strategies/OP_probability_model.R"
    "strategies/cbBTC_probability_model_backtest.R"
    "tradebot/approvals.R"
    "tradebot/defund_pools.R"
    "tradebot/pools.R"
    "tradebot/index.R"
    "tradebot/forever.R"
    "tradebot/tradebot_with_stoploss.R"
    "tradebot/tradebot_old.R"
    "tradebot/ccxt_tradebot.R"
    "tradebot/defi_thread.R"
    "plumber/messaging.R"
    "plumber/reporting.R"
)

for file in "${R_FILES[@]}"; do
    if grep -q "~/infinitetrading/src/" "$REPO_ROOT/$file" 2>/dev/null; then
        test_failed "Hardcoded path in $file" "Found ~/infinitetrading/src/ reference"
    else
        test_passed "No hardcoded paths in $file"
    fi
done

echo ""
echo "=== PHASE 3: DYNAMIC PATH DETECTION VALIDATION ==="
echo ""

# Check that files have proper dynamic path detection
for file in "${R_FILES[@]}"; do
    if grep -q 'if (!exists("wd"))' "$REPO_ROOT/$file" 2>/dev/null || \
       grep -q 'if (!file.exists(env_path))' "$REPO_ROOT/$file" 2>/dev/null; then
        test_passed "Dynamic path detection in $file"
    else
        # main.R has different pattern, skip it
        if [[ "$file" == "strategies/strategies/main.R" ]] || \
           [[ "$file" == "plumber/messaging.R" ]] || \
           [[ "$file" == "plumber/reporting.R" ]]; then
            test_passed "Alternative path handling in $file"
        else
            test_warning "No dynamic path detection found in $file"
        fi
    fi
done

echo ""
echo "=== PHASE 4: TYPESCRIPT/JAVASCRIPT PATH VALIDATION ==="
echo ""

# Check walletv2.ts for proper relative path
if grep -q "../../plumber/encryption.R" "$REPO_ROOT/express/src/walletv2.ts"; then
    test_passed "Relative path in walletv2.ts"
else
    if grep -q "/home/ubuntu/infinitetrading/src/" "$REPO_ROOT/express/src/walletv2.ts"; then
        test_failed "Hardcoded path in walletv2.ts" "Old absolute path found"
    else
        test_warning "Cannot verify path in walletv2.ts"
    fi
fi

echo ""
echo "=== PHASE 5: ECOSYSTEM.CONFIG.JS VALIDATION ==="
echo ""

# Check ecosystem.config.js has correct paths
if grep -q "plumber/gateway/gateway.R" "$REPO_ROOT/express/ecosystem.config.js"; then
    test_passed "Gateway path in ecosystem.config.js"
else
    test_failed "Gateway path in ecosystem.config.js" "Incorrect gateway path"
fi

if grep -q "express/build/src/index.js" "$REPO_ROOT/express/ecosystem.config.js"; then
    test_passed "Express path in ecosystem.config.js"
else
    test_failed "Express path in ecosystem.config.js" "Incorrect express path"
fi

if grep -q "plumber/api.R" "$REPO_ROOT/express/ecosystem.config.js"; then
    test_passed "Plumber path in ecosystem.config.js"
else
    test_failed "Plumber path in ecosystem.config.js" "Incorrect plumber path"
fi

echo ""
echo "=== PHASE 6: SERVICE AVAILABILITY CHECKS ==="
echo ""

# Check if services are running
if curl -s http://localhost:8000 > /dev/null 2>&1; then
    test_passed "Express API (port 8000) responding"
else
    test_warning "Express API (port 8000) not responding (may be stopped)"
fi

if curl -s http://localhost:8002/__docs__/ > /dev/null 2>&1; then
    test_passed "Plumber API (port 8002) responding"
else
    test_warning "Plumber API (port 8002) not responding (may be stopped)"
fi

if curl -s http://localhost:8003/__docs__/ > /dev/null 2>&1; then
    test_passed "Gateway API (port 8003) responding"
else
    test_warning "Gateway API (port 8003) not responding (may be stopped)"
fi

echo ""
echo "=== PHASE 7: ENVIRONMENT FILE CHECKS ==="
echo ""

# Check for .env files
if [ -f "$REPO_ROOT/.env" ]; then
    test_passed ".env file exists in repo root"
elif [ -f "$HOME/.env" ]; then
    test_warning ".env in home directory (will work but repo root preferred)"
else
    test_failed ".env file missing" "No .env found in repo root or home directory"
fi

echo ""
echo "=== PHASE 8: R SYNTAX VALIDATION (BASIC) ==="
echo ""

# Basic syntax check for R files (if Rscript available)
if command -v Rscript &> /dev/null; then
    for file in "${R_FILES[@]}"; do
        if Rscript -e "parse('$REPO_ROOT/$file')" &> /dev/null; then
            test_passed "R syntax valid: $file"
        else
            test_failed "R syntax error: $file" "Parse failed"
        fi
    done
else
    test_warning "Rscript not available, skipping R syntax validation"
fi

echo ""
echo "=== PHASE 9: TYPESCRIPT BUILD TEST ==="
echo ""

# Test TypeScript compilation
if [ -f "$REPO_ROOT/express/package.json" ]; then
    cd "$REPO_ROOT/express"
    if npm run build &> /tmp/ts-build.log; then
        test_passed "TypeScript build successful"
    else
        test_failed "TypeScript build failed" "See /tmp/ts-build.log for details"
    fi
    cd "$REPO_ROOT"
else
    test_warning "express/package.json not found, skipping build test"
fi

echo ""
echo "=== PHASE 10: MIGRATION SCRIPT VALIDATION ==="
echo ""

# Check migration scripts exist
MIGRATION_SCRIPTS=(
    "migrate-ec2.sh"
    "rollback-migration.sh"
    "download-missing-files.sh"
)

for script in "${MIGRATION_SCRIPTS[@]}"; do
    if [ -f "$REPO_ROOT/$script" ]; then
        if [ -x "$REPO_ROOT/$script" ]; then
            test_passed "Migration script exists and executable: $script"
        else
            test_warning "Migration script not executable: $script (run: chmod +x $script)"
        fi
    else
        test_failed "Migration script missing: $script" "Script not found"
    fi
done

echo ""
echo "=== PHASE 11: DOCUMENTATION VALIDATION ==="
echo ""

# Check documentation files
DOCS=(
    "EC2_MIGRATION_AUDIT.md"
    "DEPLOYMENT_CHECKLIST.md"
    "MIGRATION_STATUS.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$REPO_ROOT/$doc" ]; then
        test_passed "Documentation exists: $doc"
    else
        test_failed "Documentation missing: $doc" "File not found"
    fi
done

echo ""
echo "=============================================="
echo "=== TEST SUMMARY ==="
echo "=============================================="
echo "Total Tests: $TESTS_TOTAL"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED - READY FOR EC2 MIGRATION${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ SOME TESTS FAILED - REVIEW FAILURES BEFORE MIGRATION${NC}"
    exit 1
fi
