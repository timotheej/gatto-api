#!/bin/bash

# Gatto API Deployment Verification Script
# Tests all endpoints and checks deployment health

set -e

APP_NAME="gatto-api"
BASE_URL="https://$APP_NAME.fly.dev"

echo "🔍 Gatto API Deployment Verification"
echo "====================================="
echo "🌐 Testing: $BASE_URL"
echo ""

# Function to test endpoint
test_endpoint() {
    local endpoint="$1"
    local description="$2"
    local expected_code="${3:-200}"
    
    echo -n "Testing $description... "
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$BASE_URL$endpoint" 2>/dev/null) || {
        echo "❌ FAILED (connection error)"
        return 1
    }
    
    http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    body=$(echo "$response" | sed "s/HTTPSTATUS:[0-9]*//")
    
    if [ "$http_code" = "$expected_code" ]; then
        echo "✅ OK ($http_code)"
        if [ -n "$body" ] && [ "$body" != "null" ]; then
            echo "   📄 Response preview: $(echo "$body" | head -c 100)..."
        fi
    else
        echo "❌ FAILED (got $http_code, expected $expected_code)"
        echo "   📄 Response: $body"
        return 1
    fi
}

# Test Fly.io app status
echo "📊 Fly.io App Status:"
if command -v flyctl &> /dev/null; then
    flyctl status -a "$APP_NAME" 2>/dev/null || echo "⚠️  Could not get Fly status (flyctl not available or not logged in)"
else
    echo "⚠️  flyctl not available"
fi
echo ""

# Test endpoints
echo "🧪 Testing API Endpoints:"
echo ""

test_endpoint "/health" "Health check"
test_endpoint "/v1" "API v1 root"
test_endpoint "/v1/poi?limit=1" "POI endpoint (1 item)"
test_endpoint "/v1/collections" "Collections endpoint"

echo ""
echo "⚡ Performance Test:"
echo -n "Response time for health check... "
time_result=$(curl -w "%{time_total}" -s -o /dev/null "$BASE_URL/health" 2>/dev/null) || {
    echo "❌ FAILED"
    exit 1
}
echo "✅ ${time_result}s"

echo ""
echo "🔒 Security Headers Check:"
headers=$(curl -I -s "$BASE_URL/health" 2>/dev/null) || {
    echo "❌ Could not fetch headers"
    exit 1
}

check_header() {
    local header="$1"
    local description="$2"
    
    if echo "$headers" | grep -qi "$header"; then
        echo "✅ $description present"
    else
        echo "⚠️  $description missing"
    fi
}

check_header "x-frame-options" "X-Frame-Options"
check_header "x-content-type-options" "X-Content-Type-Options"
check_header "strict-transport-security" "HSTS"

echo ""
echo "📈 Quick Load Test (5 requests):"
for i in {1..5}; do
    echo -n "Request $i... "
    if curl -s -f "$BASE_URL/health" > /dev/null 2>&1; then
        echo "✅"
    else
        echo "❌"
    fi
done

echo ""
echo "🎉 Verification completed!"
echo ""
echo "📋 Summary:"
echo "   🌐 App URL: $BASE_URL"
echo "   🏥 Health: $BASE_URL/health"
echo "   📝 API Docs: $BASE_URL/v1"
echo "   🗺️  POI Data: $BASE_URL/v1/poi?limit=5"
echo ""
echo "🔧 Useful commands:"
echo "   flyctl logs -a $APP_NAME"
echo "   flyctl status -a $APP_NAME"
echo "   flyctl ssh console -a $APP_NAME"