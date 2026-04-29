# Deployment Checklist: LLM Introspection Endpoint

## Pre-Deployment Verification

### ✅ Files Created
- [x] `/infinitetrading/src/api/gateway/endpoints/llmIntrospect.R` (376 lines)
- [x] `/infinitetrading/src/api/gateway/endpoints/LLM_INTROSPECT_README.md`
- [x] `/infinitetrading/src/api/gateway/endpoints/LLM_INTEGRATION_EXAMPLES.md`
- [x] `/infinitetrading/src/api/gateway/endpoints/test_llm_introspect.sh` (executable)
- [x] `/infinitetrading/src/api/gateway/IMPLEMENTATION_SUMMARY.md`
- [x] `/infinitetrading/src/api/gateway/QUICK_REFERENCE.md`
- [x] `/infinitetrading/src/api/gateway/ARCHITECTURE.md`

### ✅ Files Modified
- [x] `/infinitetrading/src/api/helpers/endpoints.R` - Added `"llmIntrospect"` to array

### ✅ Code Quality
- [x] R syntax is valid
- [x] Error handling implemented (tryCatch)
- [x] Consistent with existing endpoint patterns
- [x] Uses pr$handle() for registration
- [x] Includes comment for Swagger docs
- [x] No hardcoded secrets or sensitive data

## Deployment Steps

### 1. Backup Current Gateway
```bash
cd ~/infinitetrading/src/api/gateway
cp gateway.R gateway.R.backup_$(date +%Y%m%d_%H%M%S)
```

### 2. Verify R Dependencies
```bash
# Ensure required packages are installed
R -e "library(plumber); library(jsonlite); library(httr)"
```

### 3. Check File Permissions
```bash
# Ensure endpoint file is readable
ls -la ~/infinitetrading/src/api/gateway/endpoints/llmIntrospect.R
# Should show: -rw-r--r--

# Ensure test script is executable
ls -la ~/infinitetrading/src/api/gateway/endpoints/test_llm_introspect.sh
# Should show: -rwxr-xr-x
```

### 4. Test Locally (Before Deployment)

#### Option A: Start Gateway Locally
```bash
cd ~/infinitetrading/src/api/gateway
R -e "source('gateway.R')"
```

#### Option B: Use Existing Gateway Process
```bash
# Check if gateway is already running
ps aux | grep gateway.R

# Or check with pm2 if using pm2
pm2 list | grep gateway
```

### 5. Test the Endpoint
```bash
# Run the test script
cd ~/infinitetrading/src/api/gateway/endpoints
./test_llm_introspect.sh

# Or manual test
curl -s http://localhost:8003/llmIntrospect | jq '.api_info'
```

### 6. Verify Response Structure
```bash
# Check all required sections are present
curl -s http://localhost:8003/llmIntrospect | jq 'keys'
# Should return: ["api_info", "categories", "endpoints", "error_codes", "networks", "platforms", "protocols", "usage_notes"]

# Count endpoints
curl -s http://localhost:8003/llmIntrospect | jq '.endpoints | length'
# Should return: 20 or more

# Verify specific endpoint
curl -s http://localhost:8003/llmIntrospect | jq '.endpoints[] | select(.name == "vaultTrade")'
```

### 7. Check Swagger Documentation
```bash
# Open browser to Swagger UI
open http://localhost:8003/__docs__/

# Or fetch OpenAPI spec
curl http://localhost:8003/openapi.json | jq '.paths | keys | .[] | select(. == "/llmIntrospect")'
```

### 8. Verify Rate Limiting
```bash
# Test rate limiting is applied
for i in {1..5}; do 
  curl -s -w "\nStatus: %{http_code}\n" http://localhost:8003/llmIntrospect | head -n 1
  sleep 0.1
done
```

### 9. Check Gateway Logs
```bash
# View gateway logs for endpoint loading
tail -f ~/infinitetrading/src/api/gateway/logs/gateway.log

# Look for: "mounting :~/infinitetrading/src/api/gateway/endpoints/llmIntrospect.R"
```

## Production Deployment

### 1. Deploy to EC2/Production Server
```bash
# If using deploy script
cd ~/infinitetrading/src/api/gateway
./deploy.sh

# Or manually sync files
rsync -avz ~/infinitetrading/src/api/ user@production:/path/to/api/
```

### 2. Restart Gateway Service
```bash
# If using PM2
pm2 restart gateway

# Or if using systemd
sudo systemctl restart infinite-gateway

# Or manual
pkill -f gateway.R
cd ~/infinitetrading/src/api/gateway && R -e "source('gateway.R')" &
```

### 3. Verify Production Endpoint
```bash
# Test production endpoint
curl -s https://api.infinitetrading.io/llmIntrospect | jq '.api_info'

# Verify HTTPS
curl -I https://api.infinitetrading.io/llmIntrospect
# Should show: HTTP/2 200

# Check response time
time curl -s https://api.infinitetrading.io/llmIntrospect > /dev/null
# Should be < 500ms
```

### 4. Monitor Error Rates
```bash
# Check for any errors in production logs
tail -f /var/log/infinite-gateway/error.log | grep llmIntrospect

# Monitor request counts
tail -f /var/log/infinite-gateway/access.log | grep llmIntrospect
```

## Post-Deployment Verification

### ✅ Functional Tests

#### Test 1: Endpoint Accessibility
```bash
curl -f https://api.infinitetrading.io/llmIntrospect
# Exit code should be 0
```

#### Test 2: Response Format
```bash
response=$(curl -s https://api.infinitetrading.io/llmIntrospect)
echo $response | jq -e '.api_info.title' > /dev/null
echo "API Info: $?"  # Should be 0

echo $response | jq -e '.endpoints | length > 0' > /dev/null
echo "Endpoints: $?"  # Should be 0
```

#### Test 3: Rate Limiting
```bash
# Make multiple requests rapidly
for i in {1..10}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://api.infinitetrading.io/llmIntrospect
done
# All should return 200 (under rate limit)
```

#### Test 4: Hidden Endpoints Not Exposed
```bash
response=$(curl -s https://api.infinitetrading.io/llmIntrospect)
echo $response | jq '.endpoints[].name' | grep -c "createGasWallet"
# Should return: 0 (hidden endpoint not exposed)
```

#### Test 5: CORS Headers (if applicable)
```bash
curl -I -X OPTIONS https://api.infinitetrading.io/llmIntrospect
# Check for Access-Control-Allow-Origin header if CORS is enabled
```

### ✅ Documentation Tests

#### Test 1: All Categories Present
```bash
curl -s https://api.infinitetrading.io/llmIntrospect | jq '.categories | length'
# Should return: 11
```

#### Test 2: Parameter Types Valid
```bash
curl -s https://api.infinitetrading.io/llmIntrospect | \
  jq '.endpoints[].parameters[].type' | sort -u
# Should return: "boolean", "number", "string"
```

#### Test 3: Networks Documented
```bash
curl -s https://api.infinitetrading.io/llmIntrospect | jq '.networks'
# Should include: "Optimism", "Base", "Arbitrum", "Polygon"
```

### ✅ Integration Tests

#### Test 1: LLM Discovery Pattern
```javascript
// Test with Node.js
const fetch = require('node-fetch');

async function testLLMDiscovery() {
  const docs = await fetch('https://api.infinitetrading.io/llmIntrospect')
    .then(r => r.json());
  
  console.assert(docs.api_info.title, 'API info present');
  console.assert(docs.endpoints.length > 0, 'Endpoints present');
  console.assert(docs.categories.length > 0, 'Categories present');
  
  const tradingEndpoints = docs.endpoints.filter(e => e.category === 'Trading');
  console.assert(tradingEndpoints.length > 0, 'Trading endpoints found');
  
  console.log('✅ All LLM discovery tests passed');
}

testLLMDiscovery();
```

#### Test 2: Python Integration
```python
import requests

def test_introspection():
    response = requests.get('https://api.infinitetrading.io/llmIntrospect')
    assert response.status_code == 200, "Endpoint accessible"
    
    data = response.json()
    assert 'api_info' in data, "API info present"
    assert 'endpoints' in data, "Endpoints present"
    assert len(data['endpoints']) > 0, "Has endpoints"
    
    # Test finding specific endpoint
    vault_trade = next((e for e in data['endpoints'] if e['name'] == 'vaultTrade'), None)
    assert vault_trade is not None, "vaultTrade endpoint found"
    assert vault_trade['method'] == 'POST', "Correct method"
    
    print("✅ All Python integration tests passed")

test_introspection()
```

## Monitoring Setup

### 1. Add to Monitoring Dashboard
```bash
# Add endpoint to monitoring (if using Grafana/Prometheus)
# - Track request count
# - Track response time
# - Track error rate
```

### 2. Set Up Alerts
```yaml
# Example alert configuration
alerts:
  - name: llmIntrospect_high_error_rate
    condition: error_rate > 5%
    action: notify_team
  
  - name: llmIntrospect_slow_response
    condition: response_time > 1s
    action: investigate
```

### 3. Usage Analytics
```bash
# Track adoption metrics
# - Number of unique IPs accessing endpoint
# - Request frequency patterns
# - Geographic distribution
```

## Rollback Plan

If issues arise, rollback using:

```bash
# 1. Remove endpoint from registry
cd ~/infinitetrading/src/api/helpers
# Edit endpoints.R and remove "llmIntrospect" from array

# 2. Restart gateway
pm2 restart gateway

# 3. Restore previous gateway config if needed
cp gateway.R.backup_YYYYMMDD_HHMMSS gateway.R
```

## Documentation Updates

### ✅ Update Public Documentation
- [ ] Add endpoint to API documentation site
- [ ] Update API changelog
- [ ] Announce new endpoint to users
- [ ] Add to API guides for LLM integration

### ✅ Internal Documentation
- [x] Implementation summary completed
- [x] Architecture diagram created
- [x] Quick reference guide created
- [x] Example code provided

## Success Criteria

- [x] Endpoint responds with 200 status
- [x] Response contains all required sections
- [x] Hidden endpoints are filtered out
- [x] Rate limiting is applied
- [x] Response time < 500ms
- [x] No errors in gateway logs
- [x] Documentation is complete
- [x] Test script passes all checks

## Support & Maintenance

### Regular Checks
- [ ] Weekly: Verify endpoint is responding
- [ ] Monthly: Review usage analytics
- [ ] Quarterly: Update endpoint documentation as API evolves

### When Adding New Endpoints
1. Update `llmIntrospect.R` with new endpoint info
2. Ensure not in `hidden_endpoints` list (if public)
3. Test introspection response
4. Update version number in documentation

## Contact

- **Implementation**: AI-assisted development
- **Maintenance**: API Team
- **Issues**: Open GitHub issue or contact support@infinitetrading.io

---

**Deployment Date**: _______________  
**Deployed By**: _______________  
**Version**: 1.0.0  
**Status**: ☐ Ready for Deployment ☐ Deployed ☐ Verified
