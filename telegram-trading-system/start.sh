#!/bin/bash

echo "🚀 Telegram Trading System - Starting..."
echo "=========================================="

# Check if config exists
if [ ! -f "config.env" ]; then
    echo "❌ config.env not found!"
    echo ""
    echo "📝 Please create config.env from template:"
    echo "   cp config.env.example config.env"
    echo "   nano config.env  # Edit with your values"
    echo ""
    echo "Required values:"
    echo "   - TELEGRAM_BOT_TOKEN (from @BotFather)"
    echo "   - TELEGRAM_CHAT_ID (from @RawDataBot)"
    echo ""
    exit 1
fi

# Check if .env exists (godotenv will load it automatically)
if [ ! -f ".env" ]; then
    if [ -f "config.env" ]; then
        echo "📋 Copying config.env to .env..."
        cp config.env .env
    else
        echo "❌ Neither .env nor config.env found!"
        echo ""
        echo "📝 Please create .env file:"
        echo "   cp config.env.example .env"
        echo "   nano .env  # Edit with your values"
        exit 1
    fi
fi

echo "📊 Configuration will be loaded automatically by godotenv..."

# Download dependencies if needed
echo "📦 Checking dependencies..."
go mod tidy > /dev/null 2>&1

# Test Telegram connection
echo "🤖 Testing Telegram connection..."
response=$(curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getMe")
if [[ $response == *"\"ok\":true"* ]]; then
    echo "✅ Telegram bot connection OK"
else
    echo "❌ Telegram connection failed. Check TELEGRAM_BOT_TOKEN"
    exit 1
fi

# Check Go installation
if ! command -v go &> /dev/null; then
    echo "❌ Go not installed. Please install Go 1.19+ first"
    exit 1
fi

echo "✅ Go found: $(go version)"

# Create MT4 directory if specified
if [ ! -z "$MT4_DATA_PATH" ]; then
    if [ ! -d "$MT4_DATA_PATH" ]; then
        echo "📁 Creating MT4 data directory: $MT4_DATA_PATH"
        mkdir -p "$MT4_DATA_PATH" 2>/dev/null || echo "⚠️  Could not create MT4 path (will use local)"
    fi
fi

echo ""
echo "🎯 Configuration Summary:"
echo "   Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}..."
echo "   Chat ID: $TELEGRAM_CHAT_ID"
echo "   Auth Token: ${API_AUTH_TOKEN:0:5}..."
echo "   Port: ${PORT:-:8080}"
echo "   MT4 Path: ${MT4_DATA_PATH:-auto-detect}"
echo ""

# Send startup notification
startup_msg="🚀 Trading System Starting...\n🕐 $(date '+%Y-%m-%d %H:%M:%S')\n💻 Backend initializing..."
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d "chat_id=$TELEGRAM_CHAT_ID" \
  -d "text=$startup_msg" > /dev/null

echo "📱 Startup notification sent to Telegram"
echo ""
echo "🌐 Starting backend server..."
echo "📡 Listening on http://localhost${PORT:-:8080}"
echo "🎯 Waiting for MT4 signals..."
echo "🛑 Press Ctrl+C to stop"
echo ""

# Start the backend
go run main.go
