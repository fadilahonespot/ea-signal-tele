//+------------------------------------------------------------------+
//|                                   Signal_Notifier_Complete.mq4 |
//|                                    Copyright 2024, Trading Helper |
//|        Complete Signal System: Open Signals + Close Signals     |
//+------------------------------------------------------------------+
#property copyright "Trading Helper 2024"
#property link      ""
#property version   "2.00"
#property strict

//=== INPUTS ===
input group "=== Strategy Selection ==="
input bool Enable_EMA_Pullback = true;          // EMA trend + pullback
input bool Enable_Gold_Momentum = true;         // London/NY session momentum
input bool Enable_Gold_Support_Resistance = true; // S/R break + retest
input bool Enable_Gold_Round_Numbers = true;    // Round number levels

input group "=== Close Signal Settings ==="
input bool Enable_Close_Signals = true;         // Enable close order signals
input bool Monitor_Open_Orders = true;          // Monitor existing orders for close signals
input bool Track_Only_EA_Orders = true;         // Track only orders from this EA system
input bool Send_Close_Confirmation = true;      // Send close confirmation with P&L

input group "=== Signal Control Settings ==="
input bool Prevent_Duplicate_Signals = true;    // Prevent same strategy signals when order open
input bool One_Order_Per_Strategy = true;       // Max 1 order per strategy at a time
input bool One_Order_Per_Symbol = false;        // Max 1 order per symbol at a time
input int Max_Open_Orders = 3;                  // Maximum total open orders from EA

input group "=== EMA Settings ==="
input int EMA_Fast = 50;
input int EMA_Slow = 200;
input int Pullback_Tolerance_Points = 300;      // Distance tolerance from EMA
input int Signal_Timeframe_Minutes = 15;        // Signal timeframe (5/15/60)

input group "=== Gold Settings ==="
input string London_Open_GMT = "07:00";         // London open time GMT
input string NY_Open_GMT = "12:00";             // NY open time GMT
input int Momentum_Period_Minutes = 30;         // Momentum period duration
input double Min_Movement_Points = 500;         // Minimum movement for signal
input double Round_Level_50 = 50.0;            // $50 round levels
input double Round_Level_25 = 25.0;            // $25 round levels
input int SR_Lookback_Bars = 100;              // S/R lookback period

input group "=== Backend Settings ==="
input string Backend_URL = "http://localhost:8080/signal";
input string Api_Auth_Token = "changeme";
input bool Auto_Detect_Timezone = true;        // Auto detect broker timezone

input group "=== Filters ==="
input bool Filter_Spread = true;
input double Max_Spread_Points = 350;
input bool Send_Once_Per_Candle = true;

//=== GLOBALS ===
datetime g_lastBarTime = 0;
string g_londonTimeServer = "";
string g_nyTimeServer = "";
int g_serverGMTOffset = 0;

// Order tracking for close signals
struct TrackedOrder
{
    int ticket;
    string symbol;
    int type;
    double openPrice;
    string strategy;
    datetime openTime;
    bool closeSignalSent;
};

TrackedOrder g_trackedOrders[];
int g_trackedOrderCount = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("🚀 Signal Notifier Complete EA Started");
    Print("📡 Backend URL: ", Backend_URL);
    
    if(Auto_Detect_Timezone)
    {
        AutoDetectTimezone();
    }
    else
    {
        g_londonTimeServer = London_Open_GMT;
        g_nyTimeServer = NY_Open_GMT;
    }
    
    // Initialize order tracking
    if(Enable_Close_Signals)
    {
        InitializeOrderTracking();
    }
    
    Print("✅ EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("🛑 Signal Notifier Complete EA Stopped");
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
    // Once per candle check
    if(Send_Once_Per_Candle)
    {
        datetime curBar = iTime(Symbol(), Period(), 0);
        if(curBar == g_lastBarTime) return;
        g_lastBarTime = curBar;
    }

    // Spread filter
    if(Filter_Spread && GetSpreadPoints() > Max_Spread_Points)
        return;

    string symbol = Symbol();
    int tf = GetSignalTimeframe();

    // === OPEN SIGNALS ===
    // Check if we can send new signals (prevent duplicates)
    if(CanSendNewSignals())
    {
        if(Enable_EMA_Pullback && CanSendStrategySignal("EMA_PULLBACK"))
            CheckEMAPullbackSignal(symbol, tf);
            
        if(Enable_Gold_Momentum && CanSendStrategySignal("GOLD_MOMENTUM"))
            CheckGoldMomentumSignal(symbol, tf);
            
        if(Enable_Gold_Support_Resistance && CanSendStrategySignal("GOLD_SR_BREAK"))
            CheckGoldSRSignal(symbol, tf);
            
        if(Enable_Gold_Round_Numbers && CanSendStrategySignal("GOLD_ROUND"))
            CheckGoldRoundSignal(symbol, tf);
    }

    // === CLOSE SIGNALS ===
    if(Enable_Close_Signals && Monitor_Open_Orders)
        CheckCloseSignals(symbol, tf);
    
    // Check for trade commands from backend
    CheckTradeCommands();
}

//+------------------------------------------------------------------+
//| Auto detect broker timezone                                     |
//+------------------------------------------------------------------+
void AutoDetectTimezone()
{
    string broker = AccountCompany();
    Print("🔍 Auto-detecting timezone for broker: ", broker);
    
    // Detect GMT offset based on broker
    if(StringFind(broker, "FXCM") >= 0 || StringFind(broker, "OANDA") >= 0)
        g_serverGMTOffset = 0;
    else if(StringFind(broker, "XM") >= 0 || StringFind(broker, "Alpari") >= 0)
        g_serverGMTOffset = 2;
    else if(StringFind(broker, "IC Markets") >= 0)
        g_serverGMTOffset = 2;
    else
        g_serverGMTOffset = 2; // Default
    
    // Adjust times for server timezone
    g_londonTimeServer = AdjustTimeForOffset(London_Open_GMT, g_serverGMTOffset);
    g_nyTimeServer = AdjustTimeForOffset(NY_Open_GMT, g_serverGMTOffset);
    
    Print("⏰ Server GMT offset: +", g_serverGMTOffset, " hours");
    Print("🇬🇧 London open (server time): ", g_londonTimeServer);
    Print("🇺🇸 NY open (server time): ", g_nyTimeServer);
}

string AdjustTimeForOffset(string gmtTime, int offsetHours)
{
    string parts[];
    StringSplit(gmtTime, ':', parts);
    if(ArraySize(parts) != 2) return gmtTime;
    
    int hour = StringToInteger(parts[0]) + offsetHours;
    if(hour >= 24) hour -= 24;
    if(hour < 0) hour += 24;
    
    return StringFormat("%02d:%02d", hour, StringToInteger(parts[1]));
}

//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+
double GetSpreadPoints()
{
    return (MarketInfo(Symbol(), MODE_ASK) - MarketInfo(Symbol(), MODE_BID)) / MarketInfo(Symbol(), MODE_POINT);
}

int GetSignalTimeframe()
{
    if(Signal_Timeframe_Minutes <= 5) return PERIOD_M5;
    if(Signal_Timeframe_Minutes <= 15) return PERIOD_M15;
    if(Signal_Timeframe_Minutes <= 30) return PERIOD_M30;
    if(Signal_Timeframe_Minutes <= 60) return PERIOD_H1;
    return PERIOD_M15;
}

bool IsTimeInRange(string startTime, int periodMinutes)
{
    string parts[];
    StringSplit(startTime, ':', parts);
    if(ArraySize(parts) != 2) return false;
    
    int startHour = StringToInteger(parts[0]);
    int startMinute = StringToInteger(parts[1]);
    int currentHour = TimeHour(TimeCurrent());
    int currentMinute = TimeMinute(TimeCurrent());
    
    int currentTotalMinutes = currentHour * 60 + currentMinute;
    int startTotalMinutes = startHour * 60 + startMinute;
    int endTotalMinutes = startTotalMinutes + periodMinutes;
    
    return (currentTotalMinutes >= startTotalMinutes && currentTotalMinutes <= endTotalMinutes);
}

//+------------------------------------------------------------------+
//| EMA Pullback Strategy                                            |
//+------------------------------------------------------------------+
void CheckEMAPullbackSignal(string symbol, int tf)
{
    double ema50 = iMA(symbol, tf, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 0);
    double ema200 = iMA(symbol, tf, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 0);
    double close0 = iClose(symbol, tf, 0);
    double open0 = iOpen(symbol, tf, 0);
    
    if(ema50 == 0 || ema200 == 0) return;
    
    bool uptrend = ema50 > ema200;
    bool downtrend = ema50 < ema200;
    double distancePoints = MathAbs((close0 - ema50) / MarketInfo(symbol, MODE_POINT));
    bool nearEMA = distancePoints <= Pullback_Tolerance_Points;
    
    if(uptrend && nearEMA && close0 > open0)
    {
        SendSignal("BUY", "EMA_PULLBACK", symbol, tf, close0, ema50, ema200, "");
    }
    else if(downtrend && nearEMA && close0 < open0)
    {
        SendSignal("SELL", "EMA_PULLBACK", symbol, tf, close0, ema50, ema200, "");
    }
}

//+------------------------------------------------------------------+
//| Gold Momentum Strategy                                           |
//+------------------------------------------------------------------+
void CheckGoldMomentumSignal(string symbol, int tf)
{
    bool isLondon = IsTimeInRange(g_londonTimeServer, Momentum_Period_Minutes);
    bool isNY = IsTimeInRange(g_nyTimeServer, Momentum_Period_Minutes);
    
    if(!isLondon && !isNY) return;
    
    double atr = iATR(symbol, tf, 14, 1);
    double close0 = iClose(symbol, tf, 0);
    double open0 = iOpen(symbol, tf, 0);
    double high0 = iHigh(symbol, tf, 0);
    double low0 = iLow(symbol, tf, 0);
    
    double candleSize = high0 - low0;
    double minMovement = Min_Movement_Points * MarketInfo(symbol, MODE_POINT);
    
    if(candleSize >= minMovement && candleSize >= atr * 1.5)
    {
        string session = isLondon ? "LONDON" : "NY";
        
        if(close0 > open0)
        {
            SendSignal("BUY", "GOLD_MOMENTUM_" + session, symbol, tf, close0, open0, atr, "");
        }
        else if(close0 < open0)
        {
            SendSignal("SELL", "GOLD_MOMENTUM_" + session, symbol, tf, close0, open0, atr, "");
        }
    }
}

//+------------------------------------------------------------------+
//| Gold S/R Strategy                                               |
//+------------------------------------------------------------------+
void CheckGoldSRSignal(string symbol, int tf)
{
    double close0 = iClose(symbol, tf, 0);
    double close1 = iClose(symbol, tf, 1);
    
    // Simple S/R detection using recent highs/lows
    double resistance = iHigh(symbol, tf, iHighest(symbol, tf, MODE_HIGH, SR_Lookback_Bars, 1));
    double support = iLow(symbol, tf, iLowest(symbol, tf, MODE_LOW, SR_Lookback_Bars, 1));
    
    double tolerance = 150 * MarketInfo(symbol, MODE_POINT);
    
    // Resistance break
    if(close1 <= resistance && close0 > resistance + tolerance)
    {
        SendSignal("BUY", "GOLD_SR_BREAK", symbol, tf, close0, resistance, support, "");
    }
    // Support break
    else if(close1 >= support && close0 < support - tolerance)
    {
        SendSignal("SELL", "GOLD_SR_BREAK", symbol, tf, close0, support, resistance, "");
    }
}

//+------------------------------------------------------------------+
//| Gold Round Numbers Strategy                                     |
//+------------------------------------------------------------------+
void CheckGoldRoundSignal(string symbol, int tf)
{
    double close0 = iClose(symbol, tf, 0);
    double close1 = iClose(symbol, tf, 1);
    double tolerance = 100 * MarketInfo(symbol, MODE_POINT);
    
    // Check $50 levels
    double nearest50 = MathRound(close0 / Round_Level_50) * Round_Level_50;
    
    if(close1 < nearest50 && close0 > nearest50 + tolerance)
    {
        SendSignal("BUY", "GOLD_ROUND_50", symbol, tf, close0, nearest50, close1, "");
    }
    else if(close1 > nearest50 && close0 < nearest50 - tolerance)
    {
        SendSignal("SELL", "GOLD_ROUND_50", symbol, tf, close0, nearest50, close1, "");
    }
}

//+------------------------------------------------------------------+
//| Check Close Signals for Open Orders                             |
//+------------------------------------------------------------------+
void CheckCloseSignals(string symbol, int tf)
{
    UpdateTrackedOrders();
    
    for(int i = 0; i < g_trackedOrderCount; i++)
    {
        if(g_trackedOrders[i].closeSignalSent)
            continue;
            
        if(!OrderSelect(g_trackedOrders[i].ticket, SELECT_BY_TICKET, MODE_TRADES))
        {
            RemoveTrackedOrder(i);
            i--;
            continue;
        }
        
        bool shouldClose = false;
        string reason = "";
        
        // Check close conditions based on strategy
        if(g_trackedOrders[i].strategy == "EMA_PULLBACK")
        {
            shouldClose = CheckEMACloseCondition(g_trackedOrders[i], reason);
        }
        else if(StringFind(g_trackedOrders[i].strategy, "GOLD_MOMENTUM") >= 0)
        {
            shouldClose = CheckMomentumCloseCondition(g_trackedOrders[i], reason);
        }
        else if(g_trackedOrders[i].strategy == "GOLD_SR_BREAK")
        {
            shouldClose = CheckSRCloseCondition(g_trackedOrders[i], reason);
        }
        else if(StringFind(g_trackedOrders[i].strategy, "GOLD_ROUND") >= 0)
        {
            shouldClose = CheckRoundCloseCondition(g_trackedOrders[i], reason);
        }
        
        if(shouldClose)
        {
            string side = (g_trackedOrders[i].type == OP_BUY) ? "BUY" : "SELL";
            double currentPrice = (g_trackedOrders[i].type == OP_BUY) ? 
                                 MarketInfo(symbol, MODE_BID) : 
                                 MarketInfo(symbol, MODE_ASK);
            
            // Send close signal for this specific order only
            SendCloseSignal(g_trackedOrders[i].ticket, side, g_trackedOrders[i].strategy, 
                           symbol, tf, currentPrice, g_trackedOrders[i].openPrice, reason);
            
            g_trackedOrders[i].closeSignalSent = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Initialize order tracking                                        |
//+------------------------------------------------------------------+
void InitializeOrderTracking()
{
    ArrayResize(g_trackedOrders, OrdersTotal() + 50);
    g_trackedOrderCount = 0;
    
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(Track_All_Orders || IsOurOrder())
            {
                AddToTracking();
            }
        }
    }
    
    Print("📊 Tracking ", g_trackedOrderCount, " orders for close signals");
}

void UpdateTrackedOrders()
{
    // Add new orders
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            int ticket = OrderTicket();
            bool found = false;
            
            for(int j = 0; j < g_trackedOrderCount; j++)
            {
                if(g_trackedOrders[j].ticket == ticket)
                {
                    found = true;
                    break;
                }
            }
            
            if(!found && (Track_All_Orders || IsOurOrder()))
            {
                AddToTracking();
            }
        }
    }
}

bool IsOurOrder()
{
    string comment = OrderComment();
    return (StringFind(comment, "AutoTrade") >= 0 || 
            StringFind(comment, "EMA_") >= 0 ||
            StringFind(comment, "GOLD_") >= 0);
}

void AddToTracking()
{
    if(g_trackedOrderCount >= ArraySize(g_trackedOrders))
        ArrayResize(g_trackedOrders, g_trackedOrderCount + 50);
    
    g_trackedOrders[g_trackedOrderCount].ticket = OrderTicket();
    g_trackedOrders[g_trackedOrderCount].symbol = OrderSymbol();
    g_trackedOrders[g_trackedOrderCount].type = OrderType();
    g_trackedOrders[g_trackedOrderCount].openPrice = OrderOpenPrice();
    g_trackedOrders[g_trackedOrderCount].openTime = OrderOpenTime();
    g_trackedOrders[g_trackedOrderCount].closeSignalSent = false;
    
    // Determine strategy from comment
    string comment = OrderComment();
    if(StringFind(comment, "EMA_PULLBACK") >= 0)
        g_trackedOrders[g_trackedOrderCount].strategy = "EMA_PULLBACK";
    else if(StringFind(comment, "GOLD_MOMENTUM") >= 0)
        g_trackedOrders[g_trackedOrderCount].strategy = "GOLD_MOMENTUM";
    else if(StringFind(comment, "GOLD_SR") >= 0)
        g_trackedOrders[g_trackedOrderCount].strategy = "GOLD_SR_BREAK";
    else if(StringFind(comment, "GOLD_ROUND") >= 0)
        g_trackedOrders[g_trackedOrderCount].strategy = "GOLD_ROUND";
    else
        g_trackedOrders[g_trackedOrderCount].strategy = "MANUAL";
    
    g_trackedOrderCount++;
}

void RemoveTrackedOrder(int index)
{
    for(int i = index; i < g_trackedOrderCount - 1; i++)
    {
        g_trackedOrders[i] = g_trackedOrders[i + 1];
    }
    g_trackedOrderCount--;
}

//+------------------------------------------------------------------+
//| Close Condition Checks                                          |
//+------------------------------------------------------------------+
bool CheckEMACloseCondition(const TrackedOrder &order, string &reason)
{
    string symbol = order.symbol;
    int tf = GetSignalTimeframe();
    
    double ema50 = iMA(symbol, tf, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 0);
    double ema200 = iMA(symbol, tf, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 0);
    double close0 = iClose(symbol, tf, 0);
    
    if(order.type == OP_BUY && ema50 < ema200)
    {
        reason = "EMA trend reversal (bearish)";
        return true;
    }
    else if(order.type == OP_SELL && ema50 > ema200)
    {
        reason = "EMA trend reversal (bullish)";
        return true;
    }
    
    return false;
}

bool CheckMomentumCloseCondition(const TrackedOrder &order, string &reason)
{
    string symbol = order.symbol;
    int tf = GetSignalTimeframe();
    
    double close0 = iClose(symbol, tf, 0);
    double open0 = iOpen(symbol, tf, 0);
    double atr = iATR(symbol, tf, 14, 1);
    double candleSize = MathAbs(close0 - open0);
    
    // Large opposite candle
    if(candleSize >= atr * 1.5)
    {
        if(order.type == OP_BUY && close0 < open0)
        {
            reason = "Large bearish reversal candle";
            return true;
        }
        else if(order.type == OP_SELL && close0 > open0)
        {
            reason = "Large bullish reversal candle";
            return true;
        }
    }
    
    return false;
}

bool CheckSRCloseCondition(const TrackedOrder &order, string &reason)
{
    string symbol = order.symbol;
    int tf = GetSignalTimeframe();
    double close0 = iClose(symbol, tf, 0);
    
    double resistance = iHigh(symbol, tf, iHighest(symbol, tf, MODE_HIGH, SR_Lookback_Bars, 1));
    double support = iLow(symbol, tf, iLowest(symbol, tf, MODE_LOW, SR_Lookback_Bars, 1));
    double tolerance = 150 * MarketInfo(symbol, MODE_POINT);
    
    if(order.type == OP_BUY && close0 >= resistance - tolerance)
    {
        reason = "Hit resistance at " + DoubleToString(resistance, MarketInfo(symbol, MODE_DIGITS));
        return true;
    }
    else if(order.type == OP_SELL && close0 <= support + tolerance)
    {
        reason = "Hit support at " + DoubleToString(support, MarketInfo(symbol, MODE_DIGITS));
        return true;
    }
    
    return false;
}

bool CheckRoundCloseCondition(const TrackedOrder &order, string &reason)
{
    string symbol = order.symbol;
    double close0 = iClose(symbol, GetSignalTimeframe(), 0);
    double tolerance = 100 * MarketInfo(symbol, MODE_POINT);
    
    double nearest50 = MathRound(close0 / Round_Level_50) * Round_Level_50;
    
    if(order.type == OP_BUY && nearest50 > order.openPrice && MathAbs(close0 - nearest50) <= tolerance)
    {
        reason = "Hit round resistance $" + DoubleToString(nearest50, 2);
        return true;
    }
    else if(order.type == OP_SELL && nearest50 < order.openPrice && MathAbs(close0 - nearest50) <= tolerance)
    {
        reason = "Hit round support $" + DoubleToString(nearest50, 2);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Send Signal to Backend                                          |
//+------------------------------------------------------------------+
void SendSignal(string side, string strategy, string symbol, int tf, 
               double price, double ref1, double ref2, string reason)
{
    string json = "{";
    json += "\"token\":\"" + Api_Auth_Token + "\",";
    json += "\"symbol\":\"" + symbol + "\",";
    json += "\"timeframe\":" + IntegerToString(tf) + ",";
    json += "\"side\":\"" + side + "\",";
    json += "\"strategy\":\"" + strategy + "\",";
    json += "\"price\":" + DoubleToString(price, MarketInfo(symbol, MODE_DIGITS)) + ",";
    json += "\"ref1\":" + DoubleToString(ref1, 5) + ",";
    json += "\"ref2\":" + DoubleToString(ref2, 0) + ",";
    if(reason != "") json += "\"reason\":\"" + reason + "\",";
    json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
    json += "}";

    char post[]; StringToCharArray(json, post);
    char result[]; string headers;
    ResetLastError();

    int res = WebRequest("application/json", Backend_URL, post, ArraySize(post), result, headers);
    if(res == -1)
    {
        Print("❌ WebRequest failed: ", GetLastError(), " - Check URL whitelist: ", Backend_URL);
        return;
    }

    Print("📡 Signal sent: ", side, " ", strategy, " @ ", DoubleToString(price, 2));
}

//+------------------------------------------------------------------+
//| Send close signal for specific order                            |
//+------------------------------------------------------------------+
void SendCloseSignal(int ticket, string side, string strategy, string symbol, int tf, 
                    double currentPrice, double openPrice, string reason)
{
    string json = "{";
    json += "\"token\":\"" + Api_Auth_Token + "\",";
    json += "\"symbol\":\"" + symbol + "\",";
    json += "\"timeframe\":" + IntegerToString(tf) + ",";
    json += "\"side\":\"CLOSE_" + side + "\",";
    json += "\"strategy\":\"CLOSE_" + strategy + "\",";
    json += "\"price\":" + DoubleToString(currentPrice, MarketInfo(symbol, MODE_DIGITS)) + ",";
    json += "\"ref1\":" + DoubleToString(openPrice, MarketInfo(symbol, MODE_DIGITS)) + ",";
    json += "\"ref2\":" + DoubleToString(ticket, 0) + ",";
    json += "\"reason\":\"" + reason + "\",";
    json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
    json += "}";

    char post[]; StringToCharArray(json, post);
    char result[]; string headers;
    ResetLastError();

    int res = WebRequest("application/json", Backend_URL, post, ArraySize(post), result, headers);
    if(res == -1)
    {
        Print("❌ Close signal WebRequest failed: ", GetLastError());
        return;
    }

    Print("🔴 Close signal sent for ticket #", ticket, " reason: ", reason);
}

//+------------------------------------------------------------------+
//| Send close confirmation with P&L details                        |
//+------------------------------------------------------------------+
void SendCloseConfirmation(int ticket, string symbol, string side, double lots, 
                          double openPrice, double closePrice, double profit)
{
    // Use same format as signals but with special strategy identifier
    string json = "{";
    json += "\"token\":\"" + Api_Auth_Token + "\",";
    json += "\"symbol\":\"" + symbol + "\",";
    json += "\"timeframe\":0,";
    json += "\"side\":\"" + side + "\",";
    json += "\"strategy\":\"ORDER_CLOSED_CONFIRMATION\",";
    json += "\"price\":" + DoubleToString(closePrice, MarketInfo(symbol, MODE_DIGITS)) + ",";
    json += "\"ref1\":" + DoubleToString(openPrice, MarketInfo(symbol, MODE_DIGITS)) + ",";
    json += "\"ref2\":" + DoubleToString(ticket, 0) + ",";
    json += "\"reason\":\"" + DoubleToString(lots, 2) + ";" + DoubleToString(profit, 2) + ";" + AccountCurrency() + "\",";
    json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
    json += "}";

    char post[]; StringToCharArray(json, post);
    char result[]; string headers;
    ResetLastError();

    int res = WebRequest("application/json", Backend_URL, post, ArraySize(post), result, headers);
    if(res == -1)
    {
        Print("❌ Close confirmation WebRequest failed: ", GetLastError());
        return;
    }

    string profitStr = (profit >= 0) ? "+" : "";
    profitStr += DoubleToString(profit, 2);
    
    Print("📊 Close confirmation sent: Ticket #", ticket, " P&L: ", profitStr, " ", AccountCurrency());
}

//+------------------------------------------------------------------+
//| Send open confirmation after successful OrderSend                |
//+------------------------------------------------------------------+
void SendOpenConfirmation(int ticket, string symbol, string side, double lots,
                         double openPrice, string strategy)
{
    string json = "{";
    json += "\"token\":\"" + Api_Auth_Token + "\",";
    json += "\"symbol\":\"" + symbol + "\",";
    json += "\"timeframe\":0,";
    json += "\"side\":\"" + side + "\",";
    json += "\"strategy\":\"ORDER_OPENED_CONFIRMATION\",";
    json += "\"price\":" + DoubleToString(openPrice, MarketInfo(symbol, MODE_DIGITS)) + ",";
    json += "\"ref1\":" + DoubleToString(lots, 2) + ",";
    json += "\"ref2\":" + DoubleToString(ticket, 0) + ",";
    json += "\"reason\":\"" + strategy + "\",";
    json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
    json += "}";

    char post[]; StringToCharArray(json, post);
    char result[]; string headers;
    ResetLastError();

    int res = WebRequest("application/json", Backend_URL, post, ArraySize(post), result, headers);
    if(res == -1)
    {
        Print("❌ Open confirmation WebRequest failed: ", GetLastError());
        return;
    }

    Print("📨 Open confirmation sent: Ticket #", ticket, " ", symbol, " ", side, " ", DoubleToString(lots, 2), " lots @ ", DoubleToString(openPrice, MarketInfo(symbol, MODE_DIGITS)));
}

//+------------------------------------------------------------------+
//| Check for trade commands from backend                           |
//+------------------------------------------------------------------+
void CheckTradeCommands()
{
    // Check for open trade commands
    string tradeFile = "trade_command.json";
    int handle = FileOpen(tradeFile, FILE_READ|FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        string command = "";
        while(!FileIsEnding(handle))
        {
            command += FileReadString(handle);
        }
        FileClose(handle);
        FileDelete(tradeFile); // Remove to prevent re-execution
        
        if(StringLen(command) > 0)
        {
            ExecuteTradeCommand(command);
        }
    }
    
    // Check for close commands
    string closeFile = "close_command.json";
    handle = FileOpen(closeFile, FILE_READ|FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        string command = "";
        while(!FileIsEnding(handle))
        {
            command += FileReadString(handle);
        }
        FileClose(handle);
        FileDelete(closeFile);
        
        if(StringLen(command) > 0)
        {
            ExecuteCloseCommand(command);
        }
    }
}

//+------------------------------------------------------------------+
//| Execute trade command from backend                              |
//+------------------------------------------------------------------+
void ExecuteTradeCommand(string jsonCommand)
{
    Print("📥 Trade command received: ", jsonCommand);
    
    // Parse JSON (simple manual parsing)
    string symbol = ExtractJSONValue(jsonCommand, "symbol");
    string side = ExtractJSONValue(jsonCommand, "side");
    double lots = StringToDouble(ExtractJSONValue(jsonCommand, "lots"));
    double sl = StringToDouble(ExtractJSONValue(jsonCommand, "sl"));
    double tp = StringToDouble(ExtractJSONValue(jsonCommand, "tp"));
    string strategy = ExtractJSONValue(jsonCommand, "strategy");
    
    if(symbol == "" || side == "" || lots <= 0)
    {
        Print("❌ Invalid trade parameters");
        return;
    }
    
    // Execute trade
    int orderType = (side == "BUY") ? OP_BUY : OP_SELL;
    double price = (orderType == OP_BUY) ? MarketInfo(symbol, MODE_ASK) : MarketInfo(symbol, MODE_BID);
    
    int ticket = OrderSend(symbol, orderType, lots, price, 10, sl, tp, 
                          "AutoTrade: " + strategy, 0, 0, clrGreen);
    
    if(ticket > 0)
    {
        Print("✅ Trade executed: Ticket #", ticket, " ", symbol, " ", side, " ", lots, " lots");
        
        // Add to tracking for close signals
        if(Enable_Close_Signals)
        {
            AddOrderToTracking(ticket, symbol, orderType, price, strategy);
        }

        // Send open confirmation back to backend/Telegram
        SendOpenConfirmation(ticket, symbol, side, lots, price, strategy);
    }
    else
    {
        Print("❌ Trade failed: Error ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Execute close command from backend                              |
//+------------------------------------------------------------------+
void ExecuteCloseCommand(string jsonCommand)
{
    Print("📥 Close command received: ", jsonCommand);
    
    int ticket = (int)StringToDouble(ExtractJSONValue(jsonCommand, "ticket"));
    
    if(ticket <= 0)
    {
        Print("❌ Invalid ticket number");
        return;
    }
    
    if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
    {
        double closePrice = (OrderType() == OP_BUY) ? 
                           MarketInfo(OrderSymbol(), MODE_BID) : 
                           MarketInfo(OrderSymbol(), MODE_ASK);
        
        double openPrice = OrderOpenPrice();
        double lots = OrderLots();
        string symbol = OrderSymbol();
        string side = (OrderType() == OP_BUY) ? "BUY" : "SELL";
        
        if(OrderClose(ticket, lots, closePrice, 10, clrRed))
        {
            // Calculate profit
            double profit = OrderProfit() + OrderSwap() + OrderCommission();
            
            Print("✅ Order closed: Ticket #", ticket, " Profit: ", profit);
            
            // Send close confirmation to Telegram
            if(Send_Close_Confirmation)
            {
                SendCloseConfirmation(ticket, symbol, side, lots, openPrice, closePrice, profit);
            }
            
            // Remove from tracking
            RemoveOrderFromTracking(ticket);
        }
        else
        {
            Print("❌ Close failed: Error ", GetLastError());
        }
    }
    else
    {
        Print("❌ Order not found: Ticket #", ticket);
    }
}

//+------------------------------------------------------------------+
//| Simple JSON value extractor                                     |
//+------------------------------------------------------------------+
string ExtractJSONValue(string json, string key)
{
    string searchKey = "\"" + key + "\":";
    int startPos = StringFind(json, searchKey);
    if(startPos == -1) return "";
    
    startPos += StringLen(searchKey);
    
    // Skip whitespace and quotes
    while(startPos < StringLen(json) && 
          (StringGetCharacter(json, startPos) == ' ' || StringGetCharacter(json, startPos) == '"'))
        startPos++;
    
    int endPos = startPos;
    bool inQuotes = (StringGetCharacter(json, startPos-1) == '"');
    
    while(endPos < StringLen(json))
    {
        int ch = StringGetCharacter(json, endPos);
        if(inQuotes && ch == '"') break;
        if(!inQuotes && (ch == ',' || ch == '}')) break;
        endPos++;
    }
    
    return StringSubstr(json, startPos, endPos - startPos);
}

//+------------------------------------------------------------------+
//| Order tracking helpers                                          |
//+------------------------------------------------------------------+
void AddOrderToTracking(int ticket, string symbol, int orderType, double openPrice, string strategy)
{
    if(g_trackedOrderCount >= ArraySize(g_trackedOrders))
        ArrayResize(g_trackedOrders, g_trackedOrderCount + 50);
    
    g_trackedOrders[g_trackedOrderCount].ticket = ticket;
    g_trackedOrders[g_trackedOrderCount].symbol = symbol;
    g_trackedOrders[g_trackedOrderCount].type = orderType;
    g_trackedOrders[g_trackedOrderCount].openPrice = openPrice;
    g_trackedOrders[g_trackedOrderCount].strategy = strategy;
    g_trackedOrders[g_trackedOrderCount].openTime = TimeCurrent();
    g_trackedOrders[g_trackedOrderCount].closeSignalSent = false;
    
    g_trackedOrderCount++;
}

void RemoveOrderFromTracking(int ticket)
{
    for(int i = 0; i < g_trackedOrderCount; i++)
    {
        if(g_trackedOrders[i].ticket == ticket)
        {
            // Shift array elements
            for(int j = i; j < g_trackedOrderCount - 1; j++)
            {
                g_trackedOrders[j] = g_trackedOrders[j + 1];
            }
            g_trackedOrderCount--;
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Check if can send new signals (prevent duplicates)             |
//+------------------------------------------------------------------+
bool CanSendNewSignals()
{
    // Count total open orders from this EA
    int eaOrders = CountEAOrders();
    
    if(eaOrders >= Max_Open_Orders)
    {
        Print("📊 Max open orders reached: ", eaOrders, "/", Max_Open_Orders);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if can send signal for specific strategy                  |
//+------------------------------------------------------------------+
bool CanSendStrategySignal(string strategy)
{
    if(!Prevent_Duplicate_Signals)
        return true;
    
    string symbol = Symbol();
    
    // Check for existing orders with same strategy
    if(One_Order_Per_Strategy && HasOpenOrderWithStrategy(strategy))
    {
        Print("📊 Strategy ", strategy, " already has open order - skipping signal");
        return false;
    }
    
    // Check for existing orders on same symbol
    if(One_Order_Per_Symbol && HasOpenOrderOnSymbol(symbol))
    {
        Print("📊 Symbol ", symbol, " already has open order - skipping signal");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Count EA orders                                                 |
//+------------------------------------------------------------------+
int CountEAOrders()
{
    int count = 0;
    
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            string comment = OrderComment();
            if(StringFind(comment, "AutoTrade") >= 0)
            {
                count++;
            }
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Check if has open order with specific strategy                  |
//+------------------------------------------------------------------+
bool HasOpenOrderWithStrategy(string strategy)
{
    for(int i = 0; i < g_trackedOrderCount; i++)
    {
        if(StringFind(g_trackedOrders[i].strategy, strategy) >= 0)
        {
            // Check if order still exists
            if(OrderSelect(g_trackedOrders[i].ticket, SELECT_BY_TICKET, MODE_TRADES))
            {
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if has open order on symbol                               |
//+------------------------------------------------------------------+
bool HasOpenOrderOnSymbol(string symbol)
{
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            string comment = OrderComment();
            if(StringFind(comment, "AutoTrade") >= 0 && OrderSymbol() == symbol)
            {
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
