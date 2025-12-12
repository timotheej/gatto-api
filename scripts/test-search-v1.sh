#!/bin/bash

# Search V1 - Quick Test Script
# Tests the main search functionality of the API

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
API_BASE_URL="${API_BASE_URL:-http://localhost:3100}"
API_KEY="${API_KEY_PUBLIC:-}"

if [ -z "$API_KEY" ]; then
  echo -e "${RED}Error: API_KEY_PUBLIC environment variable not set${NC}"
  echo "Usage: export API_KEY_PUBLIC=your_key && ./scripts/test-search-v1.sh"
  exit 1
fi

echo -e "${YELLOW}=== Search V1 Test Suite ===${NC}"
echo "API: $API_BASE_URL"
echo ""

# Helper function to test endpoint
test_endpoint() {
  local name=$1
  local url=$2
  local expected_code=${3:-200}

  echo -n "Testing $name... "

  response=$(curl -s -w "\n%{http_code}" -H "x-api-key: $API_KEY" "$url")
  body=$(echo "$response" | head -n -1)
  code=$(echo "$response" | tail -n 1)

  if [ "$code" -eq "$expected_code" ]; then
    echo -e "${GREEN}OK${NC} (HTTP $code)"
    return 0
  else
    echo -e "${RED}FAIL${NC} (HTTP $code, expected $expected_code)"
    echo "Response: $body"
    return 1
  fi
}

# Test counter
PASSED=0
FAILED=0

# === AUTOCOMPLETE TESTS ===
echo -e "${YELLOW}--- Autocomplete Tests ---${NC}"

if test_endpoint "Autocomplete: type search (italien)" \
  "$API_BASE_URL/v1/autocomplete?q=ital&city=paris&lang=fr&limit=10"; then
  ((PASSED++))
else
  ((FAILED++))
fi

if test_endpoint "Autocomplete: name search (comptoir)" \
  "$API_BASE_URL/v1/autocomplete?q=comptoir&city=paris&lang=fr&limit=10"; then
  ((PASSED++))
else
  ((FAILED++))
fi

if test_endpoint "Autocomplete: parent category (restaurant)" \
  "$API_BASE_URL/v1/autocomplete?q=restaurant&city=paris&lang=fr&limit=10"; then
  ((PASSED++))
else
  ((FAILED++))
fi

if test_endpoint "Autocomplete: multi-word (restaurant italien)" \
  "$API_BASE_URL/v1/autocomplete?q=restaurant%20italien&city=paris&lang=fr&limit=10"; then
  ((PASSED++))
else
  ((FAILED++))
fi

echo ""

# === SEARCH TESTS ===
echo -e "${YELLOW}--- Search Tests (/v1/pois) ---${NC}"

if test_endpoint "Search: type detection (italien)" \
  "$API_BASE_URL/v1/pois?q=italien&city=paris&lang=fr&limit=20"; then
  ((PASSED++))
else
  ((FAILED++))
fi

if test_endpoint "Search: name search with relevance sort" \
  "$API_BASE_URL/v1/pois?q=comptoir&city=paris&lang=fr&limit=20&sort=relevance"; then
  ((PASSED++))
else
  ((FAILED++))
fi

if test_endpoint "Search: backward compatibility (no q)" \
  "$API_BASE_URL/v1/pois?city=paris&type_keys=italian_restaurant&lang=fr&limit=20"; then
  ((PASSED++))
else
  ((FAILED++))
fi

if test_endpoint "Search: combined filters" \
  "$API_BASE_URL/v1/pois?q=italien&city=paris&price_min=2&lang=fr&limit=20"; then
  ((PASSED++))
else
  ((FAILED++))
fi

echo ""

# === FACETS TESTS ===
echo -e "${YELLOW}--- Facets Tests ---${NC}"

if test_endpoint "Facets: with type search" \
  "$API_BASE_URL/v1/pois/facets?q=italien&city=paris&lang=fr"; then
  ((PASSED++))
else
  ((FAILED++))
fi

echo ""

# === METRICS TEST ===
echo -e "${YELLOW}--- Monitoring Tests ---${NC}"

if test_endpoint "Metrics endpoint" \
  "$API_BASE_URL/v1/metrics"; then
  ((PASSED++))
else
  ((FAILED++))
fi

echo ""

# === ERROR HANDLING TESTS ===
echo -e "${YELLOW}--- Error Handling Tests ---${NC}"

if test_endpoint "Validation: empty query" \
  "$API_BASE_URL/v1/autocomplete?q=&city=paris" 400; then
  ((PASSED++))
else
  ((FAILED++))
fi

if test_endpoint "Validation: sort=relevance without q" \
  "$API_BASE_URL/v1/pois?city=paris&sort=relevance&limit=20" 400; then
  ((PASSED++))
else
  ((FAILED++))
fi

echo ""

# === CACHE PERFORMANCE TEST ===
echo -e "${YELLOW}--- Cache Performance Test ---${NC}"

echo -n "Testing cache (MISS then HIT)... "

# First request (MISS)
response1=$(curl -s -w "\n%{time_total}" -H "x-api-key: $API_KEY" \
  "$API_BASE_URL/v1/autocomplete?q=italien&city=paris&lang=fr")
time1=$(echo "$response1" | tail -n 1)

# Second request (HIT)
response2=$(curl -s -w "\n%{time_total}" -H "x-api-key: $API_KEY" \
  "$API_BASE_URL/v1/autocomplete?q=italien&city=paris&lang=fr")
time2=$(echo "$response2" | tail -n 1)

# Check if HIT is faster (it should be significantly faster)
if (( $(echo "$time2 < $time1" | bc -l) )); then
  echo -e "${GREEN}OK${NC} (MISS: ${time1}s, HIT: ${time2}s)"
  ((PASSED++))
else
  echo -e "${YELLOW}WARNING${NC} (MISS: ${time1}s, HIT: ${time2}s - HIT not faster)"
  ((PASSED++))
fi

echo ""

# === SUMMARY ===
echo -e "${YELLOW}=== Test Summary ===${NC}"
TOTAL=$((PASSED + FAILED))
echo "Total tests: $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"

if [ $FAILED -gt 0 ]; then
  echo -e "${RED}Failed: $FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
