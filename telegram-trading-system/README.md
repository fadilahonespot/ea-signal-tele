# 🤖 Telegram Trading System - Unified Project

**All-in-one trading system**: Signal detection + Telegram notifications + Auto trading untuk XAUUSD (Gold).

## 📦 What's Included

```
telegram-trading-system/
├── main.go                        # 🚀 UNIFIED BACKEND (all-in-one)
├── Signal_Notifier_Complete.mq4   # 📊 COMPLETE EA (open + close signals)
├── go.mod                         # 📋 Go module
├── config.env.example             # ⚙️ Configuration template
├── start.sh                       # 🎮 One-click startup
└── README.md                      # 📖 This guide
```

## ⚡ Quick Start (3 Steps)

### **Step 1: Get Telegram Credentials**
```bash
# 1. Chat with @BotFather → /newbot → Get bot token
# 2. Chat with @RawDataBot → Get your chat ID
```

### **Step 2: Configure**
```bash
# Copy template
cp config.env.example config.env

# Edit with your credentials:
nano config.env
```

### **Step 3: Start System**
```bash
# One command to rule them all!
./start.sh
```

## 🎯 How It Works

### **Complete Signal Flow:**
```
MT4 EA → Backend Go → Telegram → User Click → MT4 Trade
```

### **1. Open Signals**
```
🚨 [OPEN SIGNAL]
📊 XAUUSD BUY
🎯 GOLD_MOMENTUM_LONDON
💰 Price: 2545.20

[🟢 TRADE BUY] [❌ IGNORE]
[📊 0.1] [📊 0.2] [📊 0.5]
```

### **2. Close Signals (INTEGRATED!)**
```
🔴 [CLOSE SIGNAL]
📊 XAUUSD BUY
🎯 CLOSE_GOLD_MOMENTUM_LONDON
💰 Price: 2555.20
📍 Entry: 2545.20
📝 Large bearish reversal candle

[🔴 CLOSE ORDER] [⏳ KEEP OPEN]
```

## ⚙️ MT4 Setup

### **1. Install EA**
```bash
# Copy EA to MT4 Experts folder
cp Signal_Notifier_Complete.mq4 /path/to/MT4/Experts/

# In MT4:
# - Compile EA (F4 → F7)
# - Enable WebRequest: Tools → Options → Expert Advisors → Allow WebRequest → Add: http://localhost:8080
# - Attach EA to XAUUSD chart
```

### **2. EA Settings for Gold**
```mql4
// Strategy Selection
Enable_EMA_Pullback = true
Enable_Gold_Momentum = true
Enable_Gold_Support_Resistance = true
Enable_Gold_Round_Numbers = true

// Close Signals (MAIN FEATURE!)
Enable_Close_Signals = true
Monitor_Open_Orders = true
Track_All_Orders = false

// Auto Configuration
Auto_Detect_Timezone = true
Backend_URL = "http://localhost:8080/signal"
Api_Auth_Token = "changeme"

// Gold Parameters
Min_Movement_Points = 500
Round_Level_50 = 50.0
Max_Spread_Points = 350
```

## 🎮 Trading Scenarios

### **Scenario 1: Complete Trade Cycle**
```
10:30 → 🚨 OPEN: BUY XAUUSD @ 2545.20 (London momentum)
10:31 → User clicks [🟢 TRADE BUY 0.1 LOT]
10:31 → ✅ Order opened: Ticket #123456
11:45 → 🔴 CLOSE: Large bearish reversal detected
11:46 → User clicks [🔴 CLOSE ORDER]
11:46 → ✅ Order closed: Profit +$8.50
```

### **Scenario 2: EMA Pullback**
```
14:20 → 🚨 OPEN: SELL XAUUSD @ 2540.00 (EMA pullback)
14:21 → User trades 0.2 lots
15:30 → 🔴 CLOSE: EMA trend reversal (bullish)
15:31 → User keeps order open (clicks ⏳ KEEP OPEN)
16:00 → Manual close with profit
```

### **Scenario 3: Round Number Strategy**
```
09:15 → 🚨 OPEN: BUY XAUUSD @ 2348.50 (Break above $2350)
09:16 → User trades 0.1 lots
11:20 → 🔴 CLOSE: Hit round resistance $2400
11:21 → User closes: Profit +$51.50
```

## 🛡️ Built-in Protections

### **Signal Quality**
- ✅ Spread filtering (max 3.5 points)
- ✅ Volatility checks (ATR-based)
- ✅ Session timing (London/NY focus)
- ✅ Once per candle (no spam)

### **Risk Management**
- ✅ User approval required for all trades
- ✅ Lot size selection (0.1/0.2/0.5)
- ✅ Close signal suggestions
- ✅ Manual override options

### **Smart Features**
- ✅ Auto timezone detection
- ✅ Gold-optimized parameters
- ✅ Strategy-consistent close signals
- ✅ Real-time order tracking

## 📊 Strategies Included

### **1. EMA Pullback**
- **Open**: Trend direction + pullback to EMA 50 + bullish/bearish candle
- **Close**: EMA crossover reversal or price break far from EMA

### **2. Gold Momentum (London/NY)**
- **Open**: Large movement during first 30 min of major sessions
- **Close**: Session end + reversal or large opposite candle

### **3. Support/Resistance Break**
- **Open**: Break significant S/R level + retest
- **Close**: Hit opposite S/R level

### **4. Round Number Levels**
- **Open**: Break psychological levels ($50/$25 intervals)
- **Close**: Hit opposite round number levels

## 🔧 Configuration

### **config.env.example**
```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
API_AUTH_TOKEN=secure_random_string
PORT=:8080
MT4_DATA_PATH=/path/to/mt4/files
```

### **Startup Script**
```bash
./start.sh
# - Validates configuration
# - Tests Telegram connection  
# - Creates MT4 directories
# - Starts backend with status
```

## 🎯 Key Benefits

### **1. Unified Project**
- Single Go file handles everything
- Single MT4 EA for complete signals
- Zero external dependencies
- Easy to deploy and backup

### **2. Complete Signal System**
- Open signals with strategy analysis
- Close signals with exit reasoning
- User control via Telegram buttons
- Strategy-consistent logic

### **3. Gold-Optimized**
- Timezone auto-detection
- Session-based momentum
- Round number psychology
- Volatility-adjusted parameters

### **4. Production Ready**
- Error handling and logging
- Health monitoring endpoint
- Graceful startup/shutdown
- Configuration validation

## 🚀 Result

**Single unified project** yang memberikan:
- ✅ **Complete signal system** (open + close)
- ✅ **Telegram integration** dengan buttons
- ✅ **Auto timezone detection**
- ✅ **Gold-optimized strategies**
- ✅ **User control** dan safety
- ✅ **Zero dependencies** - pure Go stdlib

**Cukup 1 EA + 1 Go file = Complete automated trading system!** 🎯

---

**Disclaimer**: Trading forex dan gold berisiko tinggi. Selalu test di demo account dan trade dengan bijak.
