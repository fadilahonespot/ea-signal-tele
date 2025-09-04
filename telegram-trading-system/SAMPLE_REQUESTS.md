# 📡 Sample Requests: EA → Backend

Dokumentasi lengkap untuk semua jenis request yang dikirim EA ke backend Go.

## 🎯 Overview Communication Flow

```
MT4 EA → WebRequest → Go Backend → Telegram Bot → User → Button Click → Go Backend → File → MT4 EA
```

## 📊 Request Types

### **1. 🚨 Open Signal Requests**

#### **EMA Pullback Signal:**
```json
{
  "token": "changeme_to_secure_random_string",
  "symbol": "XAUUSD",
  "timeframe": 15,
  "side": "BUY",
  "strategy": "EMA_PULLBACK",
  "price": 2545.20,
  "ref1": 2543.50,  // EMA 50 value
  "ref2": 2541.80,  // EMA 200 value
  "timestamp": 1640995200
}
```

#### **Gold Momentum Signal:**
```json
{
  "token": "changeme_to_secure_random_string",
  "symbol": "XAUUSD", 
  "timeframe": 15,
  "side": "SELL",
  "strategy": "GOLD_MOMENTUM_LONDON",
  "price": 2540.80,
  "ref1": 2545.00,  // Session start price
  "ref2": 5.20,     // ATR value
  "timestamp": 1640995200
}
```

#### **Support/Resistance Signal:**
```json
{
  "token": "changeme_to_secure_random_string",
  "symbol": "XAUUSD",
  "timeframe": 15,
  "side": "BUY",
  "strategy": "GOLD_SR_BREAK",
  "price": 2551.50,
  "ref1": 2550.00,  // Resistance level
  "ref2": 2549.20,  // Previous close
  "timestamp": 1640995200
}
```

#### **Round Number Signal:**
```json
{
  "token": "changeme_to_secure_random_string",
  "symbol": "XAUUSD",
  "timeframe": 15,
  "side": "BUY",
  "strategy": "GOLD_ROUND_50",
  "price": 2401.50,
  "ref1": 2400.00,  // Round level
  "ref2": 2399.80,  // Previous close
  "timestamp": 1640995200
}
```

### **2. 🔴 Close Signal Requests**

#### **EMA Close Signal:**
```json
{
  "token": "changeme_to_secure_random_string",
  "symbol": "XAUUSD",
  "timeframe": 15,
  "side": "CLOSE_BUY",
  "strategy": "CLOSE_EMA_PULLBACK",
  "price": 2555.20,
  "ref1": 2545.20,  // Original open price
  "ref2": 123456,   // Order ticket number
  "reason": "EMA trend reversal (bearish)",
  "timestamp": 1640999800
}
```

#### **Momentum Close Signal:**
```json
{
  "token": "changeme_to_secure_random_string",
  "symbol": "XAUUSD",
  "timeframe": 15,
  "side": "CLOSE_SELL",
  "strategy": "CLOSE_GOLD_MOMENTUM_NY",
  "price": 2532.40,
  "ref1": 2540.80,  // Original open price
  "ref2": 789012,   // Order ticket number
  "reason": "Large bullish reversal candle",
  "timestamp": 1641003400
}
```

### **3. ✅ Close Confirmation Requests**

#### **Successful Close:**
```json
{
  "token": "changeme_to_secure_random_string",
  "symbol": "XAUUSD",
  "timeframe": 0,
  "side": "BUY",
  "strategy": "ORDER_CLOSED_CONFIRMATION",
  "price": 2555.20,     // Close price
  "ref1": 2545.20,      // Open price
  "ref2": 123456,       // Ticket number
  "reason": "0.10;15.50;USD",  // lots;profit;currency
  "timestamp": 1641000000
}
```

#### **Loss Close:**
```json
{
  "token": "changeme_to_secure_random_string",
  "symbol": "XAUUSD",
  "timeframe": 0,
  "side": "SELL",
  "strategy": "ORDER_CLOSED_CONFIRMATION", 
  "price": 2535.20,     // Close price
  "ref1": 2540.80,      // Open price
  "ref2": 789012,       // Ticket number
  "reason": "0.20;-11.20;USD", // lots;profit;currency
  "timestamp": 1641000000
}
```

## 📱 Telegram Results

### **Open Signal → Telegram:**
```
🚨 [OPEN SIGNAL]
📊 XAUUSD
📈 BUY
🎯 GOLD_MOMENTUM_LONDON
💰 Price: 2545.20
🕐 10:30:05

[🟢 TRADE BUY] [❌ IGNORE]
[📊 0.1 LOT] [📊 0.2 LOT] [📊 0.5 LOT]
```

### **Close Signal → Telegram:**
```
🔴 [CLOSE SIGNAL]
📊 XAUUSD BUY
🎯 CLOSE_EMA_PULLBACK
💰 Price: 2555.20
📍 Entry: 2545.20
📝 EMA trend reversal (bearish)
🕐 11:45:15

[🔴 CLOSE ORDER] [⏳ KEEP OPEN]
```

### **Close Confirmation → Telegram:**
```
✅ [ORDER CLOSED]
🎫 Ticket: #123456
📊 XAUUSD BUY 0.10 lots
💰 Open: 2545.20
💰 Close: 2555.20
💵 P&L: +$15.50 USD
🕐 12:00:00
```

## 🔧 Testing Commands

### **Manual Testing:**

#### **Test Health:**
```bash
curl http://localhost:8080/health
```

#### **Test Open Signal:**
```bash
curl -X POST http://localhost:8080/signal \
  -H "Content-Type: application/json" \
  -d '{
    "token": "changeme_to_secure_random_string",
    "symbol": "XAUUSD",
    "timeframe": 15,
    "side": "BUY", 
    "strategy": "GOLD_MOMENTUM_LONDON",
    "price": 2545.20,
    "ref1": 2540.00,
    "ref2": 4.50,
    "timestamp": '$(date +%s)'
  }'
```

#### **Test Close Signal:**
```bash
curl -X POST http://localhost:8080/signal \
  -H "Content-Type: application/json" \
  -d '{
    "token": "changeme_to_secure_random_string",
    "symbol": "XAUUSD",
    "timeframe": 15,
    "side": "CLOSE_BUY",
    "strategy": "CLOSE_GOLD_MOMENTUM_LONDON",
    "price": 2555.20,
    "ref1": 2545.20,
    "ref2": 123456,
    "reason": "Large bearish reversal candle",
    "timestamp": '$(date +%s)'
  }'
```

### **Automated Testing:**
```bash
# Run all tests
./test_requests.sh

# Expected output:
# 📊 Health Check: {"status":"OK",...}
# 📈 Open Signal: {"ok":true}
# 🔴 Close Signal: {"ok":true}
# ✅ Close Confirmation: {"ok":true}
```

## 📋 Field Descriptions

### **Common Fields:**
- **token**: Authentication (harus sama dengan API_AUTH_TOKEN)
- **symbol**: Trading pair (XAUUSD, EURUSD, etc)
- **timeframe**: Chart timeframe (5, 15, 30, 60)
- **timestamp**: Unix timestamp

### **Signal-Specific Fields:**
- **side**: BUY/SELL (open) atau CLOSE_BUY/CLOSE_SELL
- **strategy**: Strategy identifier
- **price**: Current market price
- **ref1**: Reference price 1 (context-dependent)
- **ref2**: Reference price 2 atau ticket number
- **reason**: Close reason (untuk close signals)

### **Data Mapping Examples:**

#### **EMA Pullback:**
```
ref1 = EMA 50 value
ref2 = EMA 200 value
```

#### **Gold Momentum:**
```
ref1 = Session start price
ref2 = ATR value
```

#### **Support/Resistance:**
```
ref1 = S/R level price
ref2 = Previous close price
```

#### **Close Signals:**
```
ref1 = Original open price
ref2 = Order ticket number
reason = Close reasoning
```

#### **Close Confirmation:**
```
ref1 = Open price
ref2 = Ticket number
reason = "lots;profit;currency" (packed)
```

## 🚀 Live Testing

### **Start System:**
```bash
# 1. Start backend
./start.sh

# 2. Run tests
./test_requests.sh

# 3. Check Telegram notifications
# 4. Test button interactions
```

### **Expected Telegram Flow:**
1. **7 notifications** dengan different signal types
2. **Buttons** untuk trade/ignore/close/keep
3. **Interactive testing** via button clicks

### **Backend Logs:**
```
📱 Signal sent: BUY EMA_PULLBACK
📱 Signal sent: SELL GOLD_MOMENTUM_NY
🔴 Close signal sent for ticket #123456
📊 Close confirmation sent: Ticket #123456 P&L: +15.50
```

## ⚠️ Important Notes

### **Authentication:**
- Token di request harus sama dengan `API_AUTH_TOKEN` di config
- Invalid token = `401 Unauthorized`

### **WebRequest Setup:**
- MT4 harus enable WebRequest untuk `http://localhost:8080`
- Tools → Options → Expert Advisors → Allow WebRequest

### **File Communication:**
- Backend write files ke `MT4_DATA_PATH`
- EA read files setiap tick
- Auto cleanup setelah processed

**Semua sample requests sudah siap untuk testing complete system!** 🧪📡🚀

