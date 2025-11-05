#!/bin/bash

# ========================================
# Script de test Phase 1 Optimizations
# ========================================
# Usage: ./scripts/test-phase1.sh
# ========================================

set -e

# Configuration
API_URL="${API_URL:-http://localhost:3000}"
BBOX="2.25,48.81,2.42,48.90"  # Paris - à adapter selon tes données
TEST_SLUG="${TEST_SLUG:-}"  # Optionnel: slug d'un POI de test

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Phase 1 Optimizations - Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ========================================
# Test 1: GET /v1/pois - Cache MISS
# ========================================
echo -e "${YELLOW}[Test 1]${NC} GET /v1/pois - First request (Cache MISS)"
echo "URL: ${API_URL}/v1/pois?bbox=${BBOX}"
echo ""

START_TIME=$(date +%s%N)
RESPONSE=$(curl -s -w "\n%{http_code}\n%{time_total}" "${API_URL}/v1/pois?bbox=${BBOX}")
END_TIME=$(date +%s%N)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 2 | head -n 1)
TIME_TOTAL=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | head -n -2)

# Extract X-Cache header
CACHE_STATUS=$(curl -s -I "${API_URL}/v1/pois?bbox=${BBOX}" | grep -i "x-cache" | awk '{print $2}' | tr -d '\r')

# Parse JSON to count POIs
POI_COUNT=$(echo "$BODY" | grep -o '"id"' | wc -l)

echo -e "  HTTP Status: ${GREEN}${HTTP_CODE}${NC}"
echo -e "  Response Time: ${GREEN}${TIME_TOTAL}s${NC}"
echo -e "  Cache Status: ${YELLOW}${CACHE_STATUS}${NC}"
echo -e "  POIs returned: ${GREEN}${POI_COUNT}${NC}"

if [ "$HTTP_CODE" != "200" ]; then
  echo -e "  ${RED}❌ FAILED${NC} - Expected HTTP 200"
  exit 1
fi

# Convert time to milliseconds
TIME_MS=$(echo "$TIME_TOTAL * 1000" | bc)
TIME_MS_INT=${TIME_MS%.*}

if [ "$TIME_MS_INT" -gt 200 ]; then
  echo -e "  ${YELLOW}⚠️  WARNING${NC} - Response time > 200ms (got ${TIME_MS_INT}ms)"
  echo -e "     Expected ~130ms for cache MISS"
else
  echo -e "  ${GREEN}✅ PASS${NC} - Response time acceptable"
fi

echo ""
sleep 1

# ========================================
# Test 2: GET /v1/pois - Cache HIT
# ========================================
echo -e "${YELLOW}[Test 2]${NC} GET /v1/pois - Second request (Cache HIT)"
echo "URL: ${API_URL}/v1/pois?bbox=${BBOX}"
echo ""

START_TIME=$(date +%s%N)
RESPONSE=$(curl -s -w "\n%{http_code}\n%{time_total}" "${API_URL}/v1/pois?bbox=${BBOX}")
END_TIME=$(date +%s%N)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 2 | head -n 1)
TIME_TOTAL=$(echo "$RESPONSE" | tail -n 1)

CACHE_STATUS=$(curl -s -I "${API_URL}/v1/pois?bbox=${BBOX}" | grep -i "x-cache" | awk '{print $2}' | tr -d '\r')

echo -e "  HTTP Status: ${GREEN}${HTTP_CODE}${NC}"
echo -e "  Response Time: ${GREEN}${TIME_TOTAL}s${NC}"
echo -e "  Cache Status: ${GREEN}${CACHE_STATUS}${NC}"

if [ "$CACHE_STATUS" != "HIT" ]; then
  echo -e "  ${RED}❌ FAILED${NC} - Expected X-Cache: HIT"
  exit 1
fi

TIME_MS=$(echo "$TIME_TOTAL * 1000" | bc)
TIME_MS_INT=${TIME_MS%.*}

if [ "$TIME_MS_INT" -gt 20 ]; then
  echo -e "  ${YELLOW}⚠️  WARNING${NC} - Cache HIT but response time > 20ms (got ${TIME_MS_INT}ms)"
  echo -e "     Expected ~2-5ms for cache HIT"
else
  echo -e "  ${GREEN}✅ PASS${NC} - Cache HIT is fast!"
fi

echo ""
sleep 1

# ========================================
# Test 3: Cache Hit Ratio (10 requests)
# ========================================
echo -e "${YELLOW}[Test 3]${NC} Cache Hit Ratio - 10 consecutive requests"
echo ""

MISS_COUNT=0
HIT_COUNT=0
TOTAL_TIME=0

for i in {1..10}; do
  RESPONSE=$(curl -s -w "%{time_total}" "${API_URL}/v1/pois?bbox=${BBOX}")
  TIME_TOTAL=$(echo "$RESPONSE" | tail -n 1)
  CACHE_STATUS=$(curl -s -I "${API_URL}/v1/pois?bbox=${BBOX}" | grep -i "x-cache" | awk '{print $2}' | tr -d '\r')

  if [ "$CACHE_STATUS" = "HIT" ]; then
    HIT_COUNT=$((HIT_COUNT + 1))
    echo -e "  Request $i: ${GREEN}HIT${NC} - ${TIME_TOTAL}s"
  else
    MISS_COUNT=$((MISS_COUNT + 1))
    echo -e "  Request $i: ${YELLOW}MISS${NC} - ${TIME_TOTAL}s"
  fi

  TOTAL_TIME=$(echo "$TOTAL_TIME + $TIME_TOTAL" | bc)
  sleep 0.2
done

AVG_TIME=$(echo "scale=3; $TOTAL_TIME / 10" | bc)
HIT_RATIO=$(echo "scale=2; $HIT_COUNT * 10" | bc)

echo ""
echo -e "  Cache Hits: ${GREEN}${HIT_COUNT}/10${NC} (${HIT_RATIO}%)"
echo -e "  Cache Misses: ${YELLOW}${MISS_COUNT}/10${NC}"
echo -e "  Average Response Time: ${GREEN}${AVG_TIME}s${NC}"

if [ "$HIT_COUNT" -lt 8 ]; then
  echo -e "  ${RED}❌ FAILED${NC} - Expected at least 80% cache hit ratio"
  exit 1
else
  echo -e "  ${GREEN}✅ PASS${NC} - Cache hit ratio is good!"
fi

echo ""
sleep 1

# ========================================
# Test 4: Data Validation
# ========================================
echo -e "${YELLOW}[Test 4]${NC} Data Validation - Check enriched photos and mentions"
echo ""

RESPONSE=$(curl -s "${API_URL}/v1/pois?bbox=${BBOX}&limit=1")

# Check if photos are present
HAS_PHOTOS=$(echo "$RESPONSE" | grep -o '"photos"' | wc -l)
HAS_MENTIONS=$(echo "$RESPONSE" | grep -o '"mentions_count"' | wc -l)
HAS_MENTIONS_SAMPLE=$(echo "$RESPONSE" | grep -o '"mentions_sample"' | wc -l)

echo -e "  Photos enriched: ${HAS_PHOTOS} POIs"
echo -e "  Mentions count present: ${HAS_MENTIONS} POIs"
echo -e "  Mentions sample present: ${HAS_MENTIONS_SAMPLE} POIs"

if [ "$HAS_PHOTOS" -eq 0 ]; then
  echo -e "  ${RED}❌ FAILED${NC} - No photos found in response"
  exit 1
fi

if [ "$HAS_MENTIONS" -eq 0 ]; then
  echo -e "  ${YELLOW}⚠️  WARNING${NC} - No mentions_count found"
fi

echo -e "  ${GREEN}✅ PASS${NC} - Data structure is correct"
echo ""

# ========================================
# Test 5: GET /v1/pois/:slug (if slug provided)
# ========================================
if [ -n "$TEST_SLUG" ]; then
  echo -e "${YELLOW}[Test 5]${NC} GET /v1/pois/:slug - Detail endpoint"
  echo "URL: ${API_URL}/v1/pois/${TEST_SLUG}"
  echo ""

  # Cache MISS
  RESPONSE=$(curl -s -w "\n%{http_code}\n%{time_total}" "${API_URL}/v1/pois/${TEST_SLUG}")
  HTTP_CODE=$(echo "$RESPONSE" | tail -n 2 | head -n 1)
  TIME_TOTAL=$(echo "$RESPONSE" | tail -n 1)
  CACHE_STATUS=$(curl -s -I "${API_URL}/v1/pois/${TEST_SLUG}" | grep -i "x-cache" | awk '{print $2}' | tr -d '\r')

  echo -e "  First request (MISS): ${TIME_TOTAL}s - Cache: ${YELLOW}${CACHE_STATUS}${NC}"

  # Cache HIT
  sleep 0.5
  RESPONSE=$(curl -s -w "\n%{http_code}\n%{time_total}" "${API_URL}/v1/pois/${TEST_SLUG}")
  TIME_TOTAL=$(echo "$RESPONSE" | tail -n 1)
  CACHE_STATUS=$(curl -s -I "${API_URL}/v1/pois/${TEST_SLUG}" | grep -i "x-cache" | awk '{print $2}' | tr -d '\r')

  echo -e "  Second request (HIT): ${TIME_TOTAL}s - Cache: ${GREEN}${CACHE_STATUS}${NC}"

  if [ "$CACHE_STATUS" = "HIT" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} - Detail endpoint cache working"
  else
    echo -e "  ${RED}❌ FAILED${NC} - Expected cache HIT on second request"
  fi
  echo ""
else
  echo -e "${YELLOW}[Test 5]${NC} GET /v1/pois/:slug - ${BLUE}SKIPPED${NC}"
  echo "  Set TEST_SLUG environment variable to test detail endpoint"
  echo "  Example: TEST_SLUG=restaurant-example ./scripts/test-phase1.sh"
  echo ""
fi

# ========================================
# Summary
# ========================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}✅ All critical tests passed!${NC}"
echo ""
echo "Next steps:"
echo "  1. Deploy photo_indexes.sql to Supabase"
echo "  2. Monitor X-Cache headers in production"
echo "  3. Check average response time < 30ms"
echo ""
echo -e "${GREEN}Phase 1 optimization validated! 🚀${NC}"
