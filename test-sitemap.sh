#!/bin/bash

# Sitemap Endpoint Test Script
# Usage: ./test-sitemap.sh [base_url]
# Example: ./test-sitemap.sh http://localhost:3000

BASE_URL="${1:-http://localhost:3000}"
PASSED=0
FAILED=0

echo "🧪 Testing Sitemap Endpoint at $BASE_URL"
echo "========================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Health Check
echo -n "Test 1: Health check... "
RESPONSE=$(curl -s "$BASE_URL/health")
if echo "$RESPONSE" | grep -q '"status":"healthy"'; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  ((FAILED++))
fi

# Test 2: API Info includes sitemap
echo -n "Test 2: API info includes sitemap endpoint... "
RESPONSE=$(curl -s "$BASE_URL/v1")
if echo "$RESPONSE" | grep -q '/v1/sitemap/pois'; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  ((FAILED++))
fi

# Test 3: Default pagination
echo -n "Test 3: Default pagination... "
RESPONSE=$(curl -s "$BASE_URL/v1/sitemap/pois")
if echo "$RESPONSE" | grep -q '"success":true'; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  echo "Response: $RESPONSE"
  ((FAILED++))
fi

# Test 4: Response structure
echo -n "Test 4: Response structure... "
RESPONSE=$(curl -s "$BASE_URL/v1/sitemap/pois")
if echo "$RESPONSE" | grep -q '"pagination"' && echo "$RESPONSE" | grep -q '"items"'; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  ((FAILED++))
fi

# Test 5: Pagination metadata
echo -n "Test 5: Pagination metadata... "
RESPONSE=$(curl -s "$BASE_URL/v1/sitemap/pois")
if echo "$RESPONSE" | grep -q '"total":' && \
   echo "$RESPONSE" | grep -q '"page":' && \
   echo "$RESPONSE" | grep -q '"limit":' && \
   echo "$RESPONSE" | grep -q '"has_next":'; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  ((FAILED++))
fi

# Test 6: Custom pagination
echo -n "Test 6: Custom pagination... "
RESPONSE=$(curl -s "$BASE_URL/v1/sitemap/pois?page=2&limit=100")
if echo "$RESPONSE" | grep -q '"page":2' && echo "$RESPONSE" | grep -q '"limit":100'; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  ((FAILED++))
fi

# Test 7: Limit clamping
echo -n "Test 7: Limit clamping to max 1000... "
RESPONSE=$(curl -s "$BASE_URL/v1/sitemap/pois?limit=2000")
if echo "$RESPONSE" | grep -q '"limit":1000'; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  ((FAILED++))
fi

# Test 8: Cache headers
echo -n "Test 8: Cache-Control headers... "
HEADERS=$(curl -sI "$BASE_URL/v1/sitemap/pois")
if echo "$HEADERS" | grep -qi "Cache-Control.*public.*max-age=300"; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  ((FAILED++))
fi

# Test 9: Content-Type
echo -n "Test 9: Content-Type is JSON... "
HEADERS=$(curl -sI "$BASE_URL/v1/sitemap/pois")
if echo "$HEADERS" | grep -qi "Content-Type.*application/json"; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  ((FAILED++))
fi

# Test 10: Invalid page defaults to 1
echo -n "Test 10: Invalid page defaults to 1... "
RESPONSE=$(curl -s "$BASE_URL/v1/sitemap/pois?page=0")
if echo "$RESPONSE" | grep -q '"page":1'; then
  echo -e "${GREEN}✅ PASS${NC}"
  ((PASSED++))
else
  echo -e "${RED}❌ FAIL${NC}"
  ((FAILED++))
fi

# Summary
echo ""
echo "========================================"
echo "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
echo "========================================"

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✨ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}⚠️  Some tests failed${NC}"
  exit 1
fi

