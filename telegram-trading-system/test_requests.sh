#!/bin/bash

echo "🧪 Testing EA → Backend Communication"
echo "===================================="

# Load environment
export $(cat .env | grep -v '^#' | grep -v '^$' | xargs)

BASE_URL="http://localhost:8080"
TOKEN="changeme_to_secure_random_string"

echo "🌐 Testing backend endpoints..."

# Test 1: Health Check
echo ""
echo "📊 1. Health Check:"
curl -s "$BASE_URL/health" | jq '.' 2>/dev/null || curl -s "$BASE_URL/health"

# Test 2: Open Signal (EMA Pullback)
echo ""
echo "📈 2. Open Signal - EMA Pullback:"
curl -X POST "$BASE_URL/signal" \
  -H "Content-Type: application/json" \
  -d "{
    \"token\": \"$TOKEN\",
    \"symbol\": \"XAUUSD\",
    \"timeframe\": 15,
    \"side\": \"BUY\",
    \"strategy\": \"EMA_PULLBACK\",
    \"price\": 2545.20,
    \"ref1\": 2543.50,
    \"ref2\": 2541.80,
    \"timestamp\": $(date +%s)
  }"

sleep 2

# Test 3: Open Signal (Gold Momentum)
echo ""
echo "🚀 3. Open Signal - Gold Momentum:"
curl -X POST "$BASE_URL/signal" \
  -H "Content-Type: application/json" \
  -d "{
    \"token\": \"$TOKEN\",
    \"symbol\": \"XAUUSD\",
    \"timeframe\": 15,
    \"side\": \"SELL\",
    \"strategy\": \"GOLD_MOMENTUM_NY\",
    \"price\": 2540.80,
    \"ref1\": 2545.00,
    \"ref2\": 5.20,
    \"timestamp\": $(date +%s)
  }"

sleep 2

# Test 4: Close Signal
echo ""
echo "🔴 4. Close Signal:"
curl -X POST "$BASE_URL/signal" \
  -H "Content-Type: application/json" \
  -d "{
    \"token\": \"$TOKEN\",
    \"symbol\": \"XAUUSD\",
    \"timeframe\": 15,
    \"side\": \"CLOSE_BUY\",
    \"strategy\": \"CLOSE_EMA_PULLBACK\",
    \"price\": 2555.20,
    \"ref1\": 2545.20,
    \"ref2\": 123456,
    \"reason\": \"EMA trend reversal (bearish)\",
    \"timestamp\": $(date +%s)
  }"

sleep 2

# Test 5: Close Confirmation
echo ""
echo "✅ 5. Close Confirmation:"
curl -X POST "$BASE_URL/signal" \
  -H "Content-Type: application/json" \
  -d "{
    \"token\": \"$TOKEN\",
    \"symbol\": \"XAUUSD\",
    \"timeframe\": 0,
    \"side\": \"BUY\",
    \"strategy\": \"ORDER_CLOSED_CONFIRMATION\",
    \"price\": 2555.20,
    \"ref1\": 2545.20,
    \"ref2\": 123456,
    \"reason\": \"0.10;15.50;USD\",
    \"timestamp\": $(date +%s)
  }"

sleep 2

# Test 6: Round Number Signal
echo ""
echo "💰 6. Round Number Signal:"
curl -X POST "$BASE_URL/signal" \
  -H "Content-Type: application/json" \
  -d "{
    \"token\": \"$TOKEN\",
    \"symbol\": \"XAUUSD\",
    \"timeframe\": 15,
    \"side\": \"BUY\",
    \"strategy\": \"GOLD_ROUND_50\",
    \"price\": 2401.50,
    \"ref1\": 2400.00,
    \"ref2\": 2399.80,
    \"timestamp\": $(date +%s)
  }"

sleep 2

# Test 7: Support/Resistance Signal
echo ""
echo "📊 7. S/R Break Signal:"
curl -X POST "$BASE_URL/signal" \
  -H "Content-Type: application/json" \
  -d "{
    \"token\": \"$TOKEN\",
    \"symbol\": \"XAUUSD\",
    \"timeframe\": 15,
    \"side\": \"SELL\",
    \"strategy\": \"GOLD_SR_BREAK\",
    \"price\": 2548.80,
    \"ref1\": 2550.00,
    \"ref2\": 2549.20,
    \"timestamp\": $(date +%s)
  }"

echo ""
echo "🎯 All test requests sent!"
echo "📱 Check your Telegram for notifications with buttons"
echo ""
echo "📁 Check MT4 files directory:"
ls -la ./mt4-files/ 2>/dev/null || echo "No files yet"

echo ""
echo "🛑 To stop backend: pkill -f 'go run main.go'"
