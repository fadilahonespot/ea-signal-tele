//+------------------------------------------------------------------+
//|                                              Signal_Notifier.mq4 |
//|                                    Copyright 2024, Trading Helper |
//+------------------------------------------------------------------+
#property copyright "Trading Helper 2024"
#property link      ""
#property version   "1.00"
#property strict

//=== Inputs ===
input group "=== Strategy Selection ==="
input bool Enable_EMA_Pullback = true;       // EMA trend + pullback
input bool Enable_Asia_Breakout = true;      // Asia range breakout
input bool Enable_Engulfing = true;          // Engulfing pattern
input bool Enable_Pin_Bar = true;            // Pin bar pattern
input bool Enable_Volume_Spike = true;       // Volume spike detection
input bool Enable_London_Open_Breakout = true; // London open breakout
input bool Enable_Support_Resistance_Bounce = true; // S/R bounce
input bool Enable_Fibonacci_Retracement = true; // Fibonacci retracement
input bool Enable_Trend_Line_Break = true;   // Trend line break
input bool Enable_Volume_Profile_Imbalance = true; // Volume profile imbalance

input group "=== EMA Settings ==="
input int EMA_Fast = 50;
input int EMA_Slow = 200;
input int Pullback_EMA = 50;                 // EMA yang dijadikan referensi pullback
input int Pullback_Tolerance_Points = 300;   // Toleransi jarak dari EMA (points)
input int Signal_Timeframe_Minutes = 15;     // Timeframe sinyal (menit), 5/15/60

input group "=== Asia Range Settings ==="
input string Asia_Session_Start_UTC = "00:00"; // 00:00 UTC
input string Asia_Session_End_UTC   = "06:00"; // 06:00 UTC
input int Breakout_Buffer_Points = 200;        // Buffer di atas/bawah range (points)

input group "=== Filters ==="
input bool Filter_Spread = true;
input double Max_Spread_Points = 500;          // Batas spread (points)
input bool Filter_News = false;                // Placeholder (integrasi optional)

input group "=== Webhook/Backend Settings ==="
input string Backend_Base_URL = "http://localhost:8080";    // Base URL backend
input string Api_Auth_Token = "changeme";                   // auth token

input group "=== Health Check Settings ==="
input bool   Enable_Health_Ping = false;                      // Aktifkan ping kesehatan backend
input int    Health_Ping_Interval_Sec = 30;                  // Interval ping (detik)

input group "=== HTTP Command Bridge ==="
input bool   Enable_HTTP_Command_Poll = false;               // Poll perintah via HTTP (untuk server terpisah)
input int    HTTP_Command_Poll_Interval_Sec = 5;             // Interval polling perintah (detik)

input group "=== Symbol/Run Settings ==="
input bool Only_Current_Symbol = true;
input int Magic_Number = 0;                   // not used here, reserved
input bool Send_Once_Per_Candle = true;       // Hindari spam setiap tick

// === Additional Strategy Inputs ===
input group "=== RSI Pullback Settings ==="
input bool   Enable_RSI_Pullback = false;
input int    RSI_Period = 14;
input int    RSI_BuyZone_Low = 40;   // 40-50 zone for BUY pullback
input int    RSI_BuyZone_High = 50;
input int    RSI_SellZone_Low = 50;  // 50-60 zone for SELL pullback
input int    RSI_SellZone_High = 60;

input group "=== Breakout Retest Settings ==="
input bool   Enable_Asia_Retest = false;
input int    Retest_Tolerance_Points = 150; // tolerance to retest level
input int    ATR_Period = 14;
input double ATR_Min_Points = 350;          // minimal ATR (points) for volatility

// === VWAP & Volatility Inputs ===
input group "=== VWAP Settings ==="
input bool   Enable_VWAP = false;
input string VWAP_Session_Start_UTC = "00:00";
input int    VWAP_ATR_Period = 14;
input double VWAP_Dev_Mult_Reversion = 1.0; // reversion band = vwap ± mult*ATR
input double VWAP_Dev_Mult_Continuation = 2.0; // continuation band hold

input group "=== Bollinger Squeeze Settings ==="
input bool   Enable_BB_Squeeze = false;
input int    BB_Period = 20;
input double BB_Dev = 2.0;
input int    BB_Squeeze_Threshold_Points = 150; // width threshold

input group "=== Keltner vs Bollinger Settings ==="
input bool   Enable_KC_BB_Expansion = false;
input int    KC_Period = 20;
input double KC_ATR_Mult = 1.5;
input int    KC_ATR_Period = 14;

// === Candlestick helpers ===
bool IsBullEngulfing(string symbol, int tf, int shift)
{
	double open1 = iOpen(symbol, tf, shift+1);
	double close1 = iClose(symbol, tf, shift+1);
	double open0 = iOpen(symbol, tf, shift);
	double close0 = iClose(symbol, tf, shift);
	return (close1 < open1) && (close0 > open0) && (close0 >= open1) && (open0 <= close1);
}

bool IsBearEngulfing(string symbol, int tf, int shift)
{
	double open1 = iOpen(symbol, tf, shift+1);
	double close1 = iClose(symbol, tf, shift+1);
	double open0 = iOpen(symbol, tf, shift);
	double close0 = iClose(symbol, tf, shift);
	return (close1 > open1) && (close0 < open0) && (close0 <= open1) && (open0 >= close1);
}

bool IsPinBarBull(string symbol, int tf, int shift)
{
	double high = iHigh(symbol, tf, shift);
	double low  = iLow(symbol, tf, shift);
	double open = iOpen(symbol, tf, shift);
	double close= iClose(symbol, tf, shift);
	double body = MathAbs(close - open);
	double tail = MathAbs(open - low);
	return (close > open) && (tail > body * 2.0) && ((high - close) < body);
}

bool IsPinBarBear(string symbol, int tf, int shift)
{
	double high = iHigh(symbol, tf, shift);
	double low  = iLow(symbol, tf, shift);
	double open = iOpen(symbol, tf, shift);
	double close= iClose(symbol, tf, shift);
	double body = MathAbs(close - open);
	double wick = MathAbs(high - open);
	return (close < open) && (wick > body * 2.0) && ((close - low) < body);
}

//=== Globals ===
datetime g_lastBarTime = 0;
datetime g_lastHttpPollTime = 0;
datetime g_lastClosedScanTime = 0;
int g_closedNotifiedCount = 0;
int g_closedNotifiedTickets[200];

// Dashboard variables
string g_dashboardObjects[50];
int g_dashboardObjectCount = 0;

// Config change detection
bool g_lastEnableEMA = false;
bool g_lastEnableEngulfing = false;
bool g_lastEnablePinBar = false;
bool g_lastEnableVolumeSpike = false;
bool g_lastEnableAsiaBreakout = false;
bool g_lastEnableLondonBreakout = false;
bool g_lastEnableSRBounce = false;
bool g_lastEnableFibonacci = false;
bool g_lastEnableTrendLine = false;
bool g_lastEnableVolumeProfile = false;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Signal Notifier EA started. Add backend base URL to MT4 WebRequest whitelist: ", Backend_Base_URL);

    // Setup timer if either health ping or HTTP command polling is enabled
    int timerSec = 0;
    if(Enable_Health_Ping && Health_Ping_Interval_Sec > 0) timerSec = Health_Ping_Interval_Sec;
    if(Enable_HTTP_Command_Poll && HTTP_Command_Poll_Interval_Sec > 0)
    {
        if(timerSec == 0 || HTTP_Command_Poll_Interval_Sec < timerSec) timerSec = HTTP_Command_Poll_Interval_Sec;
    }
    if(timerSec > 0)
    {
        EventSetTimer(timerSec);
        Print("Timer enabled every ", timerSec, "s (health=", Enable_Health_Ping, ", cmd=", Enable_HTTP_Command_Poll, ")");
    }
    
    // Always recreate dashboard panel on init (handles config changes)
    Print("Creating/refreshing dashboard panel...");
    CreateDashboardPanel();
    
    // Initialize config tracking
    g_lastEnableEMA = Enable_EMA_Pullback;
    g_lastEnableEngulfing = Enable_Engulfing;
    g_lastEnablePinBar = Enable_Pin_Bar;
    g_lastEnableVolumeSpike = Enable_Volume_Spike;
    g_lastEnableAsiaBreakout = Enable_Asia_Breakout;
    g_lastEnableLondonBreakout = Enable_London_Open_Breakout;
    g_lastEnableSRBounce = Enable_Support_Resistance_Bounce;
    g_lastEnableFibonacci = Enable_Fibonacci_Retracement;
    g_lastEnableTrendLine = Enable_Trend_Line_Break;
    g_lastEnableVolumeProfile = Enable_Volume_Profile_Imbalance;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Kill timer
    EventKillTimer();
    
    // Cleanup dashboard
    CleanupDashboard();

    Print("Signal Notifier EA stopped");
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
    if(Send_Once_Per_Candle)
    {
        datetime curBar = iTime(Symbol(), Period(), 0);
        if(curBar == g_lastBarTime) return; // once per bar
        g_lastBarTime = curBar;
    }

    if(Filter_Spread && GetCurrentSpreadPoints(Symbol()) > Max_Spread_Points)
        return;

    string tradeSymbol = Only_Current_Symbol ? Symbol() : Symbol(); // extend later for multi-symbol

    // Determine signal timeframe
    int tf = MinutesToPeriod(Signal_Timeframe_Minutes);
    if(tf <= 0) tf = Period();

    // EMA Pullback
    if(Enable_EMA_Pullback)
        CheckEMAPullbackSignal(tradeSymbol, tf);

    // Asia Breakout
    if(Enable_Asia_Breakout)
        CheckAsiaBreakoutSignal(tradeSymbol, tf);

    // RSI Pullback
    if(Enable_RSI_Pullback)
        CheckRSIPullbackSignal(tradeSymbol, tf);

    // Asia Breakout Retest
    if(Enable_Asia_Retest)
        CheckAsiaBreakoutRetestSignal(tradeSymbol, tf);

    // VWAP
    if(Enable_VWAP)
        CheckVWAPSignal(tradeSymbol, tf);

    // Bollinger Squeeze
    if(Enable_BB_Squeeze)
        CheckBBSqueezeSignal(tradeSymbol, tf);

    // Keltner vs Bollinger Expansion
    if(Enable_KC_BB_Expansion)
        CheckKeltnerExpansionSignal(tradeSymbol, tf);

    // London Open Breakout
    CheckLondonOpenBreakoutSignal(tradeSymbol, tf);

    // Support/Resistance Bounce
    CheckSupportResistanceBounceSignal(tradeSymbol, tf);

    // Fibonacci Retracement
    CheckFibonacciRetracementSignal(tradeSymbol, tf);

    // Trend Line Break
    CheckTrendLineBreakSignal(tradeSymbol, tf);

    // Volume Profile Imbalance
    CheckVolumeProfileImbalanceSignal(tradeSymbol, tf);

    // Monitor open orders for exit conditions
    MonitorOpenOrdersForExit(tradeSymbol, tf);

    // Execute incoming trade/close commands from backend
        CheckTradeCommands();

    // Detect closed orders (including SL/TP) and notify backend/Telegram
    DetectAndNotifyClosedOrders();
    
    // Check for config changes and refresh dashboard if needed
    CheckConfigChanges();
    
    // Update dashboard
    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| OnTimer - periodic health ping                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Health ping (optional)
    if(Enable_Health_Ping && Health_Ping_Interval_Sec > 0)
    {
        char post[]; ArrayResize(post, 0);
        char result[]; string result_headers = "";
        ResetLastError();
        string healthUrl = Backend_Base_URL + "/health";
        int res = WebRequest("GET", healthUrl, "", "", 5000, post, ArraySize(post), result, result_headers);
        if(res == -1)
        {
            int err = GetLastError();
            Print("Health ping failed ", err, ". Ensure URL is allowed in MT4 settings: ", healthUrl);
        }
        else
        {
            string resp = CharArrayToString(result, 0, -1);
            Print("Health OK resp=", resp);
        }
    }

    // Poll HTTP commands if enabled and interval elapsed
    if(Enable_HTTP_Command_Poll && HTTP_Command_Poll_Interval_Sec > 0)
    {
        if(g_lastHttpPollTime == 0 || (TimeCurrent() - g_lastHttpPollTime) >= HTTP_Command_Poll_Interval_Sec)
        {
            PollBackendCommands();
            g_lastHttpPollTime = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int MinutesToPeriod(int minutes)
{
    if(minutes <= 1) return PERIOD_M1;
    if(minutes <= 5) return PERIOD_M5;
    if(minutes <= 15) return PERIOD_M15;
    if(minutes <= 30) return PERIOD_M30;
    if(minutes <= 60) return PERIOD_H1;
    if(minutes <= 240) return PERIOD_H4;
    return Period();
}

double GetCurrentSpreadPoints(string symbol)
{
    double spreadPoints = (MarketInfo(symbol, MODE_ASK) - MarketInfo(symbol, MODE_BID)) / MarketInfo(symbol, MODE_POINT);
    return spreadPoints;
}

bool GetEMAs(string symbol, int tf, int fast, int slow, int shift, double &emaFast, double &emaSlow)
{
    emaFast = iMA(symbol, tf, fast, 0, MODE_EMA, PRICE_CLOSE, shift);
    emaSlow = iMA(symbol, tf, slow, 0, MODE_EMA, PRICE_CLOSE, shift);
    if(emaFast == 0 || emaSlow == 0) return false;
    return true;
}

//+------------------------------------------------------------------+
//| EMA Pullback Strategy                                            |
//+------------------------------------------------------------------+
void CheckEMAPullbackSignal(string symbol, int tf)
{
    double emaFast0, emaSlow0, emaRef0;
    if(!GetEMAs(symbol, tf, EMA_Fast, EMA_Slow, 0, emaFast0, emaSlow0)) return;
    emaRef0 = iMA(symbol, tf, Pullback_EMA, 0, MODE_EMA, PRICE_CLOSE, 0);

    double close0 = iClose(symbol, tf, 0);
    int digits = (int)MarketInfo(symbol, MODE_DIGITS);
    double point = MarketInfo(symbol, MODE_POINT);

    // Uptrend: EMA_Fast > EMA_Slow, price pulled back near EMA Pullback, and bullish close
    bool uptrend = emaFast0 > emaSlow0;
    bool downtrend = emaFast0 < emaSlow0;

    double distPoints = MathAbs((close0 - emaRef0) / point);
    bool nearPullback = distPoints <= Pullback_Tolerance_Points;

    double open0 = iOpen(symbol, tf, 0);
    bool bullCandle = close0 > open0;
    bool bearCandle = close0 < open0;

    // Example wraps within strategies (pattern applied across all)
    // EMA Pullback
    if(uptrend && nearPullback && bullCandle)
    {
        if(!HasOpenOrderForStrategy(symbol, "EMA_PULLBACK"))
            SendSignal("BUY", "EMA_PULLBACK", symbol, tf, close0, emaFast0, emaSlow0);
    }
    else if(downtrend && nearPullback && bearCandle)
    {
        if(!HasOpenOrderForStrategy(symbol, "EMA_PULLBACK"))
            SendSignal("SELL", "EMA_PULLBACK", symbol, tf, close0, emaFast0, emaSlow0);
    }
}

//+------------------------------------------------------------------+
//| Asia Range Breakout Strategy                                     |
//+------------------------------------------------------------------+
void CheckAsiaBreakoutSignal(string symbol, int tf)
{
    // Build Asia session range for previous day segment (UTC-based)
    datetime now = TimeCurrent();
    datetime sessionStart = ComposeTimeUTC(now, Asia_Session_Start_UTC);
    datetime sessionEnd   = ComposeTimeUTC(now, Asia_Session_End_UTC);

    // If we're before today's Asia session end, use yesterday's window
    if(TimeCurrent() <= sessionEnd)
    {
        sessionStart -= 24*60*60;
        sessionEnd   -= 24*60*60;
    }

    double highRange = -DBL_MAX;
    double lowRange  = DBL_MAX;

    // Scan bars within the window on the selected tf
    for(int i = 1; i < 500; i++)
    {
        datetime bt = iTime(symbol, tf, i);
        if(bt == 0) break;
        if(bt < sessionStart) break;
        if(bt <= sessionEnd && bt >= sessionStart)
        {
            double bh = iHigh(symbol, tf, i);
            double bl = iLow(symbol, tf, i);
            if(bh > highRange) highRange = bh;
            if(bl < lowRange)  lowRange  = bl;
        }
    }

    if(highRange == -DBL_MAX || lowRange == DBL_MAX) return; // no range

    double buffer = Breakout_Buffer_Points * MarketInfo(symbol, MODE_POINT);
    double upper = highRange + buffer;
    double lower = lowRange  - buffer;

    double close0 = iClose(symbol, tf, 0);

    if(close0 > upper)
    {
        if(!HasOpenOrderForStrategy(symbol, "ASIA_BREAKOUT"))
            SendSignal("BUY", "ASIA_BREAKOUT", symbol, tf, close0, highRange, lowRange);
    }
    else if(close0 < lower)
    {
        if(!HasOpenOrderForStrategy(symbol, "ASIA_BREAKOUT"))
            SendSignal("SELL", "ASIA_BREAKOUT", symbol, tf, close0, highRange, lowRange);
    }
}

// === RSI Pullback Strategy ===
void CheckRSIPullbackSignal(string symbol, int tf)
{
	double rsi0 = iRSI(symbol, tf, RSI_Period, PRICE_CLOSE, 0);
	if(rsi0 <= 0) return;

	double emaFast0, emaSlow0;
	if(!GetEMAs(symbol, tf, EMA_Fast, EMA_Slow, 0, emaFast0, emaSlow0)) return;
	bool uptrend = emaFast0 > emaSlow0;
	bool downtrend = emaFast0 < emaSlow0;

	// BUY pullback: trend up, RSI in 40-50, bullish pattern
	if(uptrend && rsi0 >= RSI_BuyZone_Low && rsi0 <= RSI_BuyZone_High)
	{
		if(IsBullEngulfing(symbol, tf, 0) || IsPinBarBull(symbol, tf, 0))
		{
			double price = iClose(symbol, tf, 0);
			if(!HasOpenOrderForStrategy(symbol, "RSI_PULLBACK"))
				SendSignal("BUY", "RSI_PULLBACK", symbol, tf, price, rsi0, emaFast0);
			return;
		}
	}
	// SELL pullback: trend down, RSI in 50-60, bearish pattern
	if(downtrend && rsi0 >= RSI_SellZone_Low && rsi0 <= RSI_SellZone_High)
	{
		if(IsBearEngulfing(symbol, tf, 0) || IsPinBarBear(symbol, tf, 0))
		{
			double price = iClose(symbol, tf, 0);
			if(!HasOpenOrderForStrategy(symbol, "RSI_PULLBACK"))
				SendSignal("SELL", "RSI_PULLBACK", symbol, tf, price, rsi0, emaFast0);
			return;
		}
	}
}

// === Asia Breakout Retest Strategy ===
void CheckAsiaBreakoutRetestSignal(string symbol, int tf)
{
	// Reuse Asia session window
	datetime now = TimeCurrent();
	datetime sessionStart = ComposeTimeUTC(now, Asia_Session_Start_UTC);
	datetime sessionEnd   = ComposeTimeUTC(now, Asia_Session_End_UTC);
	if(TimeCurrent() <= sessionEnd) { sessionStart -= 24*60*60; sessionEnd -= 24*60*60; }

	double highRange = -DBL_MAX;
	double lowRange  = DBL_MAX;
	for(int i = 1; i < 500; i++)
	{
		datetime bt = iTime(symbol, tf, i);
		if(bt == 0) break;
		if(bt < sessionStart) break;
		if(bt <= sessionEnd && bt >= sessionStart)
		{
			double bh = iHigh(symbol, tf, i);
			double bl = iLow(symbol, tf, i);
			if(bh > highRange) highRange = bh;
			if(bl < lowRange)  lowRange  = bl;
		}
	}
	if(highRange == -DBL_MAX || lowRange == DBL_MAX) return;

	double point = MarketInfo(symbol, MODE_POINT);
	double tol = Retest_Tolerance_Points * point;
	double atr = iATR(symbol, tf, ATR_Period, 1) / point; // in points
	if(atr < ATR_Min_Points) return; // need volatility

	double close0 = iClose(symbol, tf, 0);

	// Retest upper: price returns near highRange after prior breakout (close above)
	bool retestUpper = MathAbs(close0 - highRange) <= tol && close0 > highRange;
	bool retestLower = MathAbs(close0 - lowRange) <= tol && close0 < lowRange;

	if(retestUpper && (IsBullEngulfing(symbol, tf, 0) || IsPinBarBull(symbol, tf, 0)))
	{
		if(!HasOpenOrderForStrategy(symbol, "ASIA_RETEST"))
			SendSignal("BUY", "ASIA_RETEST", symbol, tf, close0, highRange, atr);
		return;
	}
	if(retestLower && (IsBearEngulfing(symbol, tf, 0) || IsPinBarBear(symbol, tf, 0)))
	{
		if(!HasOpenOrderForStrategy(symbol, "ASIA_RETEST"))
			SendSignal("SELL", "ASIA_RETEST", symbol, tf, close0, lowRange, atr);
		return;
	}
}

// === VWAP Strategy ===
void CheckVWAPSignal(string symbol, int tf)
{
	double vwap;
	if(!ComputeSessionVWAP(symbol, tf, VWAP_Session_Start_UTC, vwap)) return;
	double atr = iATR(symbol, tf, VWAP_ATR_Period, 0);
	if(atr <= 0) return;
	int digits = (int)MarketInfo(symbol, MODE_DIGITS);
	double close0 = iClose(symbol, tf, 0);
	bool bull = IsBullEngulfing(symbol, tf, 0) || IsPinBarBull(symbol, tf, 0);
	bool bear = IsBearEngulfing(symbol, tf, 0) || IsPinBarBear(symbol, tf, 0);

	// Reversion: price beyond vwap ± 1*ATR and gives reversal trigger back toward mean
	double lowerRev = vwap - VWAP_Dev_Mult_Reversion * atr;
	double upperRev = vwap + VWAP_Dev_Mult_Reversion * atr;
	if(close0 <= lowerRev && bull)
	{
		if(!HasOpenOrderForStrategy(symbol, "VWAP_REVERSION"))
			SendSignal("BUY", "VWAP_REVERSION", symbol, tf, close0, vwap, atr);
		return;
	}
	if(close0 >= upperRev && bear)
	{
		if(!HasOpenOrderForStrategy(symbol, "VWAP_REVERSION"))
			SendSignal("SELL", "VWAP_REVERSION", symbol, tf, close0, vwap, atr);
		return;
	}

	// Continuation: price holding beyond vwap ± 2*ATR with momentum candle
	double lowerCont = vwap - VWAP_Dev_Mult_Continuation * atr;
	double upperCont = vwap + VWAP_Dev_Mult_Continuation * atr;
	if(close0 > upperCont && bull)
	{
		if(!HasOpenOrderForStrategy(symbol, "VWAP_CONTINUATION"))
			SendSignal("BUY", "VWAP_CONTINUATION", symbol, tf, close0, vwap, atr);
		return;
	}
	if(close0 < lowerCont && bear)
	{
		if(!HasOpenOrderForStrategy(symbol, "VWAP_CONTINUATION"))
			SendSignal("SELL", "VWAP_CONTINUATION", symbol, tf, close0, vwap, atr);
		return;
	}
}

// === Bollinger Squeeze + Breakout ===
void CheckBBSqueezeSignal(string symbol, int tf)
{
	double upper0 = iBands(symbol, tf, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 0);
	double lower0 = iBands(symbol, tf, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 0);
	double upper1 = iBands(symbol, tf, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
	double lower1 = iBands(symbol, tf, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
	if(upper0 == 0 || lower0 == 0 || upper1 == 0 || lower1 == 0) return;
	double width0 = upper0 - lower0;
	double width1 = upper1 - lower1;
	double point = MarketInfo(symbol, MODE_POINT);
	if(width1/point > BB_Squeeze_Threshold_Points) return; // not squeezed previously
	if(width0 <= width1) return; // no expansion yet
	double close0 = iClose(symbol, tf, 0);
	if(close0 > upper0)
	{
		if(!HasOpenOrderForStrategy(symbol, "BB_SQUEEZE_BREAK"))
			SendSignal("BUY", "BB_SQUEEZE_BREAK", symbol, tf, close0, width0/point, width1/point);
		return;
	}
	if(close0 < lower0)
	{
		if(!HasOpenOrderForStrategy(symbol, "BB_SQUEEZE_BREAK"))
			SendSignal("SELL", "BB_SQUEEZE_BREAK", symbol, tf, close0, width0/point, width1/point);
		return;
	}
}

// === Keltner vs Bollinger Expansion ===
void CheckKeltnerExpansionSignal(string symbol, int tf)
{
	double ema = iMA(symbol, tf, KC_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
	double atr = iATR(symbol, tf, KC_ATR_Period, 0);
	if(ema == 0 || atr == 0) return;
	double kcUpper = ema + KC_ATR_Mult * atr;
	double kcLower = ema - KC_ATR_Mult * atr;
	double bbUpper = iBands(symbol, tf, KC_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 0);
	double bbLower = iBands(symbol, tf, KC_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 0);
	if(bbUpper == 0 || bbLower == 0) return;
	double close0 = iClose(symbol, tf, 0);

	// Expansion when Bollinger pierces Keltner envelope
	if(bbUpper > kcUpper && close0 > kcUpper)
	{
		if(!HasOpenOrderForStrategy(symbol, "KC_BB_EXPANSION"))
			SendSignal("BUY", "KC_BB_EXPANSION", symbol, tf, close0, kcUpper, bbUpper);
		return;
	}
	if(bbLower < kcLower && close0 < kcLower)
	{
		if(!HasOpenOrderForStrategy(symbol, "KC_BB_EXPANSION"))
			SendSignal("SELL", "KC_BB_EXPANSION", symbol, tf, close0, kcLower, bbLower);
		return;
	}
}

//+------------------------------------------------------------------+
//| Check London Open Breakout Signal                               |
//+------------------------------------------------------------------+
void CheckLondonOpenBreakoutSignal(string symbol, int tf)
{
	// London session: 07:00-09:00 UTC
	if(!IsInTimeRange("07:00", "09:00")) return;
	
	// Cari range London open (2 jam pertama)
	double londonHigh = 0;
	double londonLow = 999999;
	int londonBars = 0;
	
	// Hitung berapa bar dalam 2 jam terakhir
	for(int i = 0; i < 50; i++)
	{
		datetime barTime = iTime(symbol, tf, i);
		if(barTime < TimeCurrent() - 2*3600) break; // 2 jam terakhir
		
		double high = iHigh(symbol, tf, i);
		double low = iLow(symbol, tf, i);
		
		if(high > londonHigh) londonHigh = high;
		if(low < londonLow) londonLow = low;
		londonBars++;
	}
	
	if(londonBars < 5) return; // Minimal 5 bar
	
	double close0 = iClose(symbol, tf, 0);
	double point = MarketInfo(symbol, MODE_POINT);
	double breakoutBuffer = 300 * point; // 300 points buffer
	
	// Breakout dengan volume confirmation
	double currentVolume = iVolume(symbol, tf, 0);
	double avgVolume = 0;
	for(int i = 1; i <= 10; i++)
		avgVolume += iVolume(symbol, tf, i);
	avgVolume /= 10;
	
	// Breakout up dengan volume
	if(close0 > londonHigh + breakoutBuffer && currentVolume > avgVolume * 1.2)
	{
		if(!HasOpenOrderForStrategy(symbol, "LONDON_OPEN_BREAKOUT"))
			SendSignal("BUY", "LONDON_OPEN_BREAKOUT", symbol, tf, close0, londonHigh, londonLow);
		return;
	}
	
	// Breakout down dengan volume
	if(close0 < londonLow - breakoutBuffer && currentVolume > avgVolume * 1.2)
	{
		if(!HasOpenOrderForStrategy(symbol, "LONDON_OPEN_BREAKOUT"))
			SendSignal("SELL", "LONDON_OPEN_BREAKOUT", symbol, tf, close0, londonHigh, londonLow);
		return;
	}
}

//+------------------------------------------------------------------+
//| Check Support/Resistance Bounce Signal                          |
//+------------------------------------------------------------------+
void CheckSupportResistanceBounceSignal(string symbol, int tf)
{
	// Cari level support/resistance dalam 50 bar terakhir
	double supportLevel = 0;
	double resistanceLevel = 0;
	int supportTouches = 0;
	int resistanceTouches = 0;
	
	// Cari swing points
	for(int i = 5; i < 50; i++)
	{
		double high = iHigh(symbol, tf, i);
		double low = iLow(symbol, tf, i);
		
		// Cek apakah ini swing high
		bool isSwingHigh = true;
		for(int j = 1; j <= 3; j++)
		{
			if(iHigh(symbol, tf, i-j) >= high || iHigh(symbol, tf, i+j) >= high)
			{
				isSwingHigh = false;
				break;
			}
		}
		
		// Cek apakah ini swing low
		bool isSwingLow = true;
		for(int j = 1; j <= 3; j++)
		{
			if(iLow(symbol, tf, i-j) <= low || iLow(symbol, tf, i+j) <= low)
			{
				isSwingLow = false;
				break;
			}
		}
		
		if(isSwingHigh)
		{
			if(resistanceLevel == 0) resistanceLevel = high;
			else if(MathAbs(high - resistanceLevel) < 100 * MarketInfo(symbol, MODE_POINT))
			{
				resistanceTouches++;
			}
		}
		
		if(isSwingLow)
		{
			if(supportLevel == 0) supportLevel = low;
			else if(MathAbs(low - supportLevel) < 100 * MarketInfo(symbol, MODE_POINT))
			{
				supportTouches++;
			}
		}
	}
	
	if(supportTouches < 2 && resistanceTouches < 2) return;
	
	double close0 = iClose(symbol, tf, 0);
	double point = MarketInfo(symbol, MODE_POINT);
	double bounceTolerance = 200 * point; // 200 points tolerance
	
	// Bounce dari support dengan bullish pattern
	if(supportTouches >= 2 && MathAbs(close0 - supportLevel) < bounceTolerance)
	{
		if(IsBullEngulfing(symbol, tf, 0) || IsPinBarBull(symbol, tf, 0))
		{
			if(!HasOpenOrderForStrategy(symbol, "SUPPORT_RESISTANCE_BOUNCE"))
				SendSignal("BUY", "SUPPORT_RESISTANCE_BOUNCE", symbol, tf, close0, supportLevel, resistanceLevel);
			return;
		}
	}
	
	// Bounce dari resistance dengan bearish pattern
	if(resistanceTouches >= 2 && MathAbs(close0 - resistanceLevel) < bounceTolerance)
	{
		if(IsBearEngulfing(symbol, tf, 0) || IsPinBarBear(symbol, tf, 0))
		{
			if(!HasOpenOrderForStrategy(symbol, "SUPPORT_RESISTANCE_BOUNCE"))
				SendSignal("SELL", "SUPPORT_RESISTANCE_BOUNCE", symbol, tf, close0, supportLevel, resistanceLevel);
			return;
		}
	}
}

//+------------------------------------------------------------------+
//| Check Fibonacci Retracement Signal                               |
//+------------------------------------------------------------------+
void CheckFibonacciRetracementSignal(string symbol, int tf)
{
	// Cari swing high/low dalam 50 bar terakhir
	double swingHigh = 0;
	double swingLow = 999999;
	int swingHighBar = 0;
	int swingLowBar = 0;
	
	// Cari swing points
	for(int i = 10; i < 50; i++)
	{
		double high = iHigh(symbol, tf, i);
		double low = iLow(symbol, tf, i);
		
		// Cek swing high (5 bar terendah di kiri-kanan)
		bool isSwingHigh = true;
		for(int j = 1; j <= 5; j++)
		{
			if(iHigh(symbol, tf, i-j) >= high || iHigh(symbol, tf, i+j) >= high)
			{
				isSwingHigh = false;
				break;
			}
		}
		
		// Cek swing low (5 bar tertinggi di kiri-kanan)
		bool isSwingLow = true;
		for(int j = 1; j <= 5; j++)
		{
			if(iLow(symbol, tf, i-j) <= low || iLow(symbol, tf, i+j) <= low)
			{
				isSwingLow = false;
				break;
			}
		}
		
		if(isSwingHigh && high > swingHigh)
		{
			swingHigh = high;
			swingHighBar = i;
		}
		
		if(isSwingLow && low < swingLow)
		{
			swingLow = low;
			swingLowBar = i;
		}
	}
	
	if(swingHigh == 0 || swingLow == 999999) return;
	if(swingHighBar == 0 || swingLowBar == 0) return;
	
	// Pastikan swing high lebih baru dari swing low
	if(swingHighBar > swingLowBar) return;
	
	double close0 = iClose(symbol, tf, 0);
	double point = MarketInfo(symbol, MODE_POINT);
	double fibTolerance = 150 * point; // 150 points tolerance
	
	// Hitung Fibonacci levels
	double range = swingHigh - swingLow;
	double fib236 = swingHigh - range * 0.236;
	double fib382 = swingHigh - range * 0.382;
	double fib500 = swingHigh - range * 0.500;
	double fib618 = swingHigh - range * 0.618;
	
	// Bounce dari Fibonacci level dengan bullish pattern
	if(MathAbs(close0 - fib382) < fibTolerance)
	{
		if(IsBullEngulfing(symbol, tf, 0) || IsPinBarBull(symbol, tf, 0))
		{
			if(!HasOpenOrderForStrategy(symbol, "FIBONACCI_RETRACEMENT"))
				SendSignal("BUY", "FIBONACCI_RETRACEMENT", symbol, tf, close0, fib382, swingHigh);
			return;
		}
	}
	
	if(MathAbs(close0 - fib500) < fibTolerance)
	{
		if(IsBullEngulfing(symbol, tf, 0) || IsPinBarBull(symbol, tf, 0))
		{
			if(!HasOpenOrderForStrategy(symbol, "FIBONACCI_RETRACEMENT"))
				SendSignal("BUY", "FIBONACCI_RETRACEMENT", symbol, tf, close0, fib500, swingHigh);
			return;
		}
	}
	
	if(MathAbs(close0 - fib618) < fibTolerance)
	{
		if(IsBullEngulfing(symbol, tf, 0) || IsPinBarBull(symbol, tf, 0))
		{
			if(!HasOpenOrderForStrategy(symbol, "FIBONACCI_RETRACEMENT"))
				SendSignal("BUY", "FIBONACCI_RETRACEMENT", symbol, tf, close0, fib618, swingHigh);
			return;
		}
	}
}

//+------------------------------------------------------------------+
//| Check Trend Line Break Signal                                   |
//+------------------------------------------------------------------+
void CheckTrendLineBreakSignal(string symbol, int tf)
{
	// Cari trend line dari swing points
	double trendLineSlope = 0;
	double trendLineValue = 0;
	int trendLineTouches = 0;
	
	// Cari swing points untuk trend line
	double swingPoints[10][2]; // [price, bar_index]
	int swingCount = 0;
	
	for(int i = 10; i < 50; i++)
	{
		double high = iHigh(symbol, tf, i);
		double low = iLow(symbol, tf, i);
		
		// Cek swing high
		bool isSwingHigh = true;
		for(int j = 1; j <= 3; j++)
		{
			if(iHigh(symbol, tf, i-j) >= high || iHigh(symbol, tf, i+j) >= high)
			{
				isSwingHigh = false;
				break;
			}
		}
		
		// Cek swing low
		bool isSwingLow = true;
		for(int j = 1; j <= 3; j++)
		{
			if(iLow(symbol, tf, i-j) <= low || iLow(symbol, tf, i+j) <= low)
			{
				isSwingLow = false;
				break;
			}
		}
		
		if(isSwingHigh && swingCount < 10)
		{
			swingPoints[swingCount][0] = high;
			swingPoints[swingCount][1] = i;
			swingCount++;
		}
		
		if(isSwingLow && swingCount < 10)
		{
			swingPoints[swingCount][0] = low;
			swingPoints[swingCount][1] = i;
			swingCount++;
		}
	}
	
	if(swingCount < 3) return;
	
	// Cari trend line yang paling banyak touch
	for(int i = 0; i < swingCount - 1; i++)
	{
		for(int j = i + 1; j < swingCount; j++)
		{
			double slope = (swingPoints[i][0] - swingPoints[j][0]) / (swingPoints[i][1] - swingPoints[j][1]);
			double currentValue = swingPoints[i][0] - slope * swingPoints[i][1];
			
			int touches = 2; // i dan j
			
			// Hitung berapa banyak swing point yang dekat dengan trend line
			for(int k = 0; k < swingCount; k++)
			{
				if(k == i || k == j) continue;
				double lineValue = currentValue + slope * swingPoints[k][1];
				if(MathAbs(swingPoints[k][0] - lineValue) < 100 * MarketInfo(symbol, MODE_POINT))
				{
					touches++;
				}
			}
			
			if(touches > trendLineTouches)
			{
				trendLineTouches = touches;
				trendLineSlope = slope;
				trendLineValue = currentValue;
			}
		}
	}
	
	if(trendLineTouches < 3) return; // Minimal 3 touch
	
	double close0 = iClose(symbol, tf, 0);
	double point = MarketInfo(symbol, MODE_POINT);
	double breakBuffer = 200 * point; // 200 points buffer
	
	// Hitung nilai trend line di bar saat ini
	double currentTrendLineValue = trendLineValue + trendLineSlope * 0;
	
	// Break trend line dengan volume
	double currentVolume = iVolume(symbol, tf, 0);
	double avgVolume = 0;
	for(int i = 1; i <= 10; i++)
		avgVolume += iVolume(symbol, tf, i);
	avgVolume /= 10;
	
	// Breakout up dengan volume
	if(close0 > currentTrendLineValue + breakBuffer && currentVolume > avgVolume * 1.1)
	{
		if(!HasOpenOrderForStrategy(symbol, "TREND_LINE_BREAK"))
			SendSignal("BUY", "TREND_LINE_BREAK", symbol, tf, close0, currentTrendLineValue, trendLineSlope);
		return;
	}
	
	// Breakout down dengan volume
	if(close0 < currentTrendLineValue - breakBuffer && currentVolume > avgVolume * 1.1)
	{
		if(!HasOpenOrderForStrategy(symbol, "TREND_LINE_BREAK"))
			SendSignal("SELL", "TREND_LINE_BREAK", symbol, tf, close0, currentTrendLineValue, trendLineSlope);
		return;
	}
}

//+------------------------------------------------------------------+
//| Check Volume Profile Imbalance Signal                           |
//+------------------------------------------------------------------+
void CheckVolumeProfileImbalanceSignal(string symbol, int tf)
{
	// Hitung volume profile dalam 20 bar terakhir
	double avgVolume = 0;
	double maxVolume = 0;
	int maxVolumeBar = 0;
	
	for(int i = 0; i < 20; i++)
	{
		double volume = iVolume(symbol, tf, i);
		avgVolume += volume;
		if(volume > maxVolume)
		{
			maxVolume = volume;
			maxVolumeBar = i;
		}
	}
	avgVolume /= 20;
	
	// Deteksi volume spike (2x rata-rata)
	if(maxVolume < avgVolume * 2.0) return;
	
	// Volume spike harus di bar terbaru (0-2 bar)
	if(maxVolumeBar > 2) return;
	
	double close0 = iClose(symbol, tf, 0);
	double close1 = iClose(symbol, tf, 1);
	double atr = iATR(symbol, tf, 14, 0);
	
	// Volume spike dengan price movement yang signifikan
	if(close0 > close1 + atr * 0.3) // Price naik 30% ATR
	{
		if(!HasOpenOrderForStrategy(symbol, "VOLUME_PROFILE_IMBALANCE"))
			SendSignal("BUY", "VOLUME_PROFILE_IMBALANCE", symbol, tf, close0, maxVolume, avgVolume);
		return;
	}
	
	if(close0 < close1 - atr * 0.3) // Price turun 30% ATR
	{
		if(!HasOpenOrderForStrategy(symbol, "VOLUME_PROFILE_IMBALANCE"))
			SendSignal("SELL", "VOLUME_PROFILE_IMBALANCE", symbol, tf, close0, maxVolume, avgVolume);
		return;
	}
}

// Compose a datetime today from HH:MM string in UTC
datetime ComposeTimeUTC(datetime baseTime, string hhmm)
{
    string parts[];
    StringSplit(hhmm, ':', parts);
    if(ArraySize(parts) != 2) return 0;
    int hh = StringToInteger(parts[0]);
    int mm = StringToInteger(parts[1]);

    string d = TimeToString(baseTime, TIME_DATE);
    string ts = StringFormat("%s %02d:%02d:00", d, hh, mm);
    // This assumes terminal server time aligned with UTC; brokers differ.
    // For most use, the relative window works well enough.
    return(StringToTime(ts));
}

// Check if current time is within specified time range (UTC)
bool IsInTimeRange(string startTime, string endTime)
{
    datetime now = TimeCurrent();
    datetime start = ComposeTimeUTC(now, startTime);
    datetime end = ComposeTimeUTC(now, endTime);
    
    if(start == 0 || end == 0) return false;
    
    // Handle case where end time is next day (e.g., 23:00 to 01:00)
    if(end <= start) end += 24*60*60;
    
    return (now >= start && now <= end);
}

//+------------------------------------------------------------------+
//| Send Signal via WebRequest                                       |
//+------------------------------------------------------------------+
void SendSignal(string side, string strategy, string symbol, int tf, double price, double ref1, double ref2)
{
    // Hitung ATR untuk SL/TP dinamis
    double atr = iATR(symbol, tf, 14, 0);
    
    string json = "{";
    json += "\"token\":\"" + Api_Auth_Token + "\",";
    json += "\"symbol\":\"" + symbol + "\",";
    json += "\"timeframe\":" + IntegerToString(tf) + ",";
    json += "\"side\":\"" + side + "\",";
    json += "\"strategy\":\"" + strategy + "\",";
    json += "\"price\":" + DoubleToString(price, (int)MarketInfo(symbol, MODE_DIGITS)) + ",";
    json += "\"ref1\":" + DoubleToString(ref1, 5) + ",";
    json += "\"ref2\":" + DoubleToString(ref2, 5) + ",";
    json += "\"atr\":" + DoubleToString(atr, 5) + ",";
    json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
    json += "}";

    char post[]; StringToCharArray(json, post);
    char result[];
    string result_headers = "";
    // Add content-type via standard header rules handled internally by terminal
    ResetLastError();

    // POST to baseURL/signal
    string signalUrl = Backend_Base_URL + "/signal";
    int res = WebRequest("POST", signalUrl, "", "", 10000, post, ArraySize(post), result, result_headers);
    if(res == -1)
    {
        int err = GetLastError();
        Print("WebRequest failed ", err, ". Ensure URL is allowed in MT4 settings: ", signalUrl);
        return;
    }

    string resp = CharArrayToString(result, 0, -1);
    Print("Signal sent [", side, "] strategy=", strategy, " resp=", resp);
}

//+------------------------------------------------------------------+

// Read trade/close commands from Files/Common and execute
void CheckTradeCommands()
{
	// Trade command
	string tradeFile = "trade_command.json";
	int handle = FileOpen(tradeFile, FILE_READ|FILE_TXT|FILE_COMMON);
	if(handle == INVALID_HANDLE)
		handle = FileOpen(tradeFile, FILE_READ|FILE_TXT);
	if(handle != INVALID_HANDLE)
	{
		string command = "";
		while(!FileIsEnding(handle)) command += FileReadString(handle);
		FileClose(handle);
		// Attempt delete from both locations
		FileDelete(tradeFile);
		int h2 = FileOpen(tradeFile, FILE_WRITE|FILE_COMMON); if(h2 != INVALID_HANDLE){ FileClose(h2); FileDelete(tradeFile); }

		if(StringLen(command) > 0)
			ExecuteTradeCommand(command);
	}

	// Close command
	string closeFile = "close_command.json";
	handle = FileOpen(closeFile, FILE_READ|FILE_TXT|FILE_COMMON);
	if(handle == INVALID_HANDLE)
		handle = FileOpen(closeFile, FILE_READ|FILE_TXT);
	if(handle != INVALID_HANDLE)
	{
		string cmd = "";
		while(!FileIsEnding(handle)) cmd += FileReadString(handle);
		FileClose(handle);
		FileDelete(closeFile);
		int h3 = FileOpen(closeFile, FILE_WRITE|FILE_COMMON); if(h3 != INVALID_HANDLE){ FileClose(h3); FileDelete(closeFile); }

		if(StringLen(cmd) > 0)
			ExecuteCloseCommand(cmd);
	}
}

void ExecuteTradeCommand(string jsonCommand)
{
	Print("📥 Trade command received: ", jsonCommand);

	string symbol = ExtractJSONValue(jsonCommand, "symbol");
	string side = ExtractJSONValue(jsonCommand, "side");
	double lots = StringToDouble(ExtractJSONValue(jsonCommand, "lots"));
	double sl = StringToDouble(ExtractJSONValue(jsonCommand, "sl"));
	double tp = StringToDouble(ExtractJSONValue(jsonCommand, "tp"));
	string strategy = ExtractJSONValue(jsonCommand, "strategy");
	
	Print("🔍 Trade parameters: Symbol=", symbol, " Side=", side, " Lots=", lots, " SL=", sl, " TP=", tp, " Strategy=", strategy);

	if(symbol == "" || (side != "BUY" && side != "SELL") || lots <= 0)
	{
		Print("❌ Invalid trade parameters");
		return;
	}

	int orderType = (side == "BUY") ? OP_BUY : OP_SELL;
	
	// Refresh rates to ensure latest quotes
	RefreshRates();
	double price = (orderType == OP_BUY) ? MarketInfo(symbol, MODE_ASK) : MarketInfo(symbol, MODE_BID);
	
	// Validate price
	if(price <= 0)
	{
		Print("❌ Invalid price: ", price, " for symbol: ", symbol);
		return;
	}

	// Normalize lot and price
	int digits = (int)MarketInfo(symbol, MODE_DIGITS);
	double minLot = MarketInfo(symbol, MODE_MINLOT);
	double maxLot = MarketInfo(symbol, MODE_MAXLOT);
	double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
	if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
	if(lots < minLot) lots = minLot;
	if(lots > maxLot) lots = maxLot;
	price = NormalizeDouble(price, digits);

	// Validate and adjust SL/TP to prevent Error 130 (Invalid stops)
	double point = MarketInfo(symbol, MODE_POINT);
	double minStopLevel = MarketInfo(symbol, MODE_STOPLEVEL) * point;
	double spread = MarketInfo(symbol, MODE_SPREAD) * point;
	
	Print("🔍 Broker info: Point=", point, " StopLevel=", minStopLevel, " Spread=", spread);
	
	// Ensure minimum distance for SL/TP - use larger buffer for gold
	double minDistance = MathMax(minStopLevel, spread * 3);
	if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
	{
		// For gold, ensure minimum 15 points distance
		minDistance = MathMax(minDistance, 0.015);
	}
	
	Print("🔍 MinDistance=", minDistance, " Original SL=", sl, " Original TP=", tp);
	
	if(sl > 0)
	{
		double slDistance = MathAbs(price - sl);
		if(slDistance < minDistance)
		{
			double newSL = (orderType == OP_BUY) ? price - minDistance : price + minDistance;
			Print("⚠️ SL too close (", slDistance, " < ", minDistance, "), adjusting from ", sl, " to ", newSL);
			sl = NormalizeDouble(newSL, digits);
		}
		else
		{
			Print("✅ SL distance OK: ", slDistance, " >= ", minDistance);
		}
	}
	
	if(tp > 0)
	{
		double tpDistance = MathAbs(price - tp);
		if(tpDistance < minDistance)
		{
			double newTP = (orderType == OP_BUY) ? price + minDistance : price - minDistance;
			Print("⚠️ TP too close (", tpDistance, " < ", minDistance, "), adjusting from ", tp, " to ", newTP);
			tp = NormalizeDouble(newTP, digits);
		}
		else
		{
			Print("✅ TP distance OK: ", tpDistance, " >= ", minDistance);
		}
	}
	
	Print("🔍 Final SL/TP: SL=", sl, " TP=", tp);

	int ticket = OrderSend(symbol, orderType, lots, price, 10, sl, tp, "AutoTrade: " + strategy, 0, 0, clrGreen);
	if(ticket > 0)
	{
		Print("✅ Trade executed: #", ticket, " ", symbol, " ", side, " ", DoubleToString(lots, 2), " lots @ ", DoubleToString(price, (int)MarketInfo(symbol, MODE_DIGITS)));
		// Notify backend/Telegram with detailed info
		SendOpenConfirmation(ticket, symbol, side, lots, price, strategy);
	}
	else
	{
		Print("❌ Trade failed: Error ", GetLastError());
	}
}

void ExecuteCloseCommand(string jsonCommand)
{
	Print("📥 Close command received: ", jsonCommand);
	string targetSymbol = ExtractJSONValue(jsonCommand, "symbol");
	string rawStrategy = ExtractJSONValue(jsonCommand, "strategy");
	string strategy = rawStrategy;
	if(StringFind(strategy, "CLOSE_") == 0)
		strategy = StringSubstr(strategy, 6); // remove CLOSE_
	int ticket = (int)StringToDouble(ExtractJSONValue(jsonCommand, "ticket"));

	// 1) Try close by ticket if provided
	if(ticket > 0)
	{
		if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
		{
			double cp = (OrderType() == OP_BUY) ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK);
			double lots = OrderLots();
			if(OrderClose(OrderTicket(), lots, cp, 10, clrRed))
			{
				Print("✅ Order closed by ticket: #", OrderTicket());
				SendCloseConfirmation(OrderTicket(), OrderSymbol(), OrderType() == OP_BUY ? "BUY" : "SELL", OrderLots(), OrderOpenPrice(), cp, OrderProfit());
				return;
			}
			else
			{
				Print("❌ Close by ticket failed: #", OrderTicket(), " Error ", GetLastError());
			}
		}
	}

	// 2) Close by strategy (and symbol if provided)
	int closedCount = 0;
	for(int i = OrdersTotal() - 1; i >= 0; i--)
	{
		if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
			continue;

		// Relaxed symbol match to handle broker suffixes (e.g., XAUUSD.m)
		bool symbolMatch = true;
		if(targetSymbol != "")
		{
			string osym = OrderSymbol();
			symbolMatch = (osym == targetSymbol) || (StringFind(osym, targetSymbol) >= 0) || (StringFind(targetSymbol, osym) >= 0);
		}
		if(!symbolMatch) continue;

		// Ensure the order belongs to this EA (by comment)
		string c = OrderComment();
		if(StringFind(c, "AutoTrade") < 0)
			continue;

		// If strategy provided, enforce it; otherwise accept any AutoTrade order on symbol
		if(strategy != "" && StringFind(c, strategy) < 0)
			continue;

		double closePrice = (OrderType() == OP_BUY) ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK);
		double lots2 = OrderLots();
		int t = OrderTicket();
		if(OrderClose(t, lots2, closePrice, 10, clrRed))
		{
			closedCount++;
			Print("✅ Order closed: #", t, " strategy=", strategy);
			SendCloseConfirmation(t, OrderSymbol(), OrderType() == OP_BUY ? "BUY" : "SELL", OrderLots(), OrderOpenPrice(), closePrice, OrderProfit());
		}
		else
		{
			Print("❌ Close failed: Ticket #", t, " Error ", GetLastError());
		}
	}

	if(closedCount == 0)
	{
		Print("❌ No matching orders found to close for strategy=", strategy, " symbol=", targetSymbol);
	}
}

string ExtractJSONValue(string json, string key)
{
	string searchKey = "\"" + key + "\":";
	int startPos = StringFind(json, searchKey);
	if(startPos == -1) return "";
	startPos += StringLen(searchKey);
	while(startPos < StringLen(json) && (StringGetCharacter(json, startPos) == ' ' || StringGetCharacter(json, startPos) == '"')) startPos++;
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

// Poll backend /commands and execute returned commands
void PollBackendCommands()
{
    // Build URL from base; append token if not present
    string url = Backend_Base_URL + "/commands";
    if(StringFind(StringToLower(url), "token=") < 0)
    {
        string sep = (StringFind(url, "?") >= 0) ? "&" : "?";
        url = url + sep + "token=" + Api_Auth_Token;
    }

    char post[]; ArrayResize(post, 0);
    char result[]; string result_headers = "";
    ResetLastError();
    int res = WebRequest("GET", url, "", "", 5000, post, ArraySize(post), result, result_headers);
    if(res == -1)
    {
        Print("Commands poll failed ", GetLastError(), " URL=", url);
        return;
    }

    string body = CharArrayToString(result, 0, -1);
    // Find commands array
    int idx = StringFind(body, "\"commands\"");
    if(idx < 0) return;
    int arrStart = StringFind(body, "[", idx);
    if(arrStart < 0) return;
    int depth = 0;
    int i = arrStart;
    int arrEnd = -1;
    while(i < StringLen(body))
    {
        int ch = StringGetCharacter(body, i);
        if(ch == '[') depth++;
        if(ch == ']') { depth--; if(depth == 0) { arrEnd = i; break; } }
        i++;
    }
    if(arrEnd < 0) return;
    string arr = StringSubstr(body, arrStart+1, arrEnd - arrStart - 1);

    // Iterate JSON objects by matching braces
    int pos = 0;
    while(pos < StringLen(arr))
    {
        // Skip commas/whitespace
        while(pos < StringLen(arr))
        {
            int c = StringGetCharacter(arr, pos);
            if(c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == ',') { pos++; continue; }
            break;
        }
        if(pos >= StringLen(arr)) break;
        if(StringGetCharacter(arr, pos) != '{') { pos++; continue; }
        int objStart = pos;
        int brace = 0;
        while(pos < StringLen(arr))
        {
            int c2 = StringGetCharacter(arr, pos);
            if(c2 == '{') brace++;
            if(c2 == '}') { brace--; if(brace == 0) { pos++; break; } }
            pos++;
        }
        int objEnd = pos;
        if(objEnd > objStart)
        {
            string obj = StringSubstr(arr, objStart, objEnd - objStart);
            string action = ExtractJSONValue(obj, "action");
            if(StringFind(action, "close") >= 0 || StringFind(action, "CLOSE") >= 0)
                ExecuteCloseCommand(obj);
            else if(StringFind(StringToLower(action), "status") >= 0)
                SendOrdersStatus();
            else
                ExecuteTradeCommand(obj);
        }
    }
}

void SendOpenConfirmation(int ticket, string symbol, string side, double lots, double openPrice, string strategy)
{
	string json = "{";
	json += "\"token\":\"" + Api_Auth_Token + "\",";
	json += "\"symbol\":\"" + symbol + "\",";
	json += "\"timeframe\":0,";
	json += "\"side\":\"" + side + "\",";
	json += "\"strategy\":\"ORDER_OPENED_CONFIRMATION\",";
	json += "\"price\":" + DoubleToString(openPrice, (int)MarketInfo(symbol, MODE_DIGITS)) + ",";
	json += "\"ref1\":" + DoubleToString(lots, 2) + ",";
	json += "\"ref2\":" + DoubleToString(ticket, 0) + ",";
	json += "\"reason\":\"" + strategy + "\",";
	json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
	json += "}";

	char post[]; StringToCharArray(json, post);
	char result[]; string result_headers = "";
	ResetLastError();
	string url = Backend_Base_URL + "/signal";
	int res = WebRequest("POST", url, "", "", 10000, post, ArraySize(post), result, result_headers);
	if(res == -1)
	{
		Print("❌ Open confirmation WebRequest failed: ", GetLastError());
	}
}

void SendCloseConfirmation(int ticket, string symbol, string side, double lots, double openPrice, double closePrice, double profit)
{
	string json = "{";
	json += "\"token\":\"" + Api_Auth_Token + "\",";
	json += "\"symbol\":\"" + symbol + "\",";
	json += "\"timeframe\":0,";
	json += "\"side\":\"" + side + "\",";
	json += "\"strategy\":\"ORDER_CLOSED_CONFIRMATION\",";
	json += "\"price\":" + DoubleToString(closePrice, (int)MarketInfo(symbol, MODE_DIGITS)) + ",";
	json += "\"ref1\":" + DoubleToString(openPrice, (int)MarketInfo(symbol, MODE_DIGITS)) + ",";
	json += "\"ref2\":" + DoubleToString(ticket, 0) + ",";
	json += "\"reason\":\"" + DoubleToString(lots, 2) + ";" + DoubleToString(profit, 2) + ";" + AccountCurrency() + "\",";
	json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
	json += "}";

	char post[]; StringToCharArray(json, post);
	char result[]; string result_headers = "";
	ResetLastError();
	string url = Backend_Base_URL + "/signal";
	int res = WebRequest("POST", url, "", "", 10000, post, ArraySize(post), result, result_headers);
	if(res == -1)
	{
		Print("❌ Close confirmation WebRequest failed: ", GetLastError());
	}
}

void SendOrdersStatus()
{
	string lines = "";
	int count = 0;
	for(int i = 0; i < OrdersTotal(); i++)
	{
		if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
		string side = (OrderType() == OP_BUY) ? "BUY" : "SELL";
		string comment = OrderComment();
		lines += StringFormat("#%d | %s %s %.2f | open: %.*f | strat: %s\n",
			OrderTicket(), OrderSymbol(), side, OrderLots(), (int)MarketInfo(OrderSymbol(), MODE_DIGITS), OrderOpenPrice(), comment);
		count++;
	}
	if(count == 0) lines = "(no active orders)";

	// Build ORDERS_STATUS payload
	string json = "{";
	json += "\"token\":\"" + Api_Auth_Token + "\",";
	json += "\"symbol\":\"\","; // not required
	json += "\"timeframe\":0,";
	json += "\"side\":\"\",";
	json += "\"strategy\":\"ORDERS_STATUS\",";
	json += "\"price\":0,";
	json += "\"ref1\":0,";
	json += "\"ref2\":0,";
	json += "\"reason\":\"" + lines + "\",";
	json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
	json += "}";

	char post[]; StringToCharArray(json, post);
	char result[]; string result_headers = "";
	ResetLastError();
	string url = Backend_Base_URL + "/signal";
	int res = WebRequest("POST", url, "", "", 10000, post, ArraySize(post), result, result_headers);
	if(res == -1)
	{
		Print("❌ Orders status WebRequest failed: ", GetLastError());
	}
}

void SendAutoCloseSignal(int ticket, string symbol, string side, double openPrice, double currentPrice, string strategy, string reason)
{
	// Hitung P&L floating
	double floatingPL = 0;
	if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
	{
		floatingPL = OrderProfit() + OrderSwap() + OrderCommission();
	}
	
	string json = "{";
	json += "\"token\":\"" + Api_Auth_Token + "\",";
	json += "\"symbol\":\"" + symbol + "\",";
	json += "\"timeframe\":0,";
	json += "\"side\":\"CLOSE_" + side + "\",";
	json += "\"strategy\":\"CLOSE_" + strategy + "\",";
	json += "\"price\":" + DoubleToString(currentPrice, (int)MarketInfo(symbol, MODE_DIGITS)) + ",";
	json += "\"ref1\":" + DoubleToString(openPrice, (int)MarketInfo(symbol, MODE_DIGITS)) + ",";
	json += "\"ref2\":" + DoubleToString(ticket, 0) + ",";
	json += "\"reason\":\"" + reason + ";" + DoubleToString(floatingPL, 2) + ";" + AccountCurrency() + "\",";
	json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
	json += "}";

	char post[]; StringToCharArray(json, post);
	char result[]; string result_headers = "";
	ResetLastError();
	string url = Backend_Base_URL + "/signal";
	int res = WebRequest("POST", url, "", "", 10000, post, ArraySize(post), result, result_headers);
	if(res == -1)
	{
		Print("❌ Auto-close signal WebRequest failed: ", GetLastError());
	}
}

void MonitorOpenOrdersForExit(string symbol, int tf)
{
	for(int i = 0; i < OrdersTotal(); i++)
	{
		if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
		string osym = OrderSymbol();
		if(symbol != "" && osym != symbol) continue;

		string comment = OrderComment();
		if(StringFind(comment, "AutoTrade") < 0) continue;
		string strategy = comment;
		int idx = StringFind(strategy, ": ");
		if(idx >= 0) strategy = StringSubstr(strategy, idx + 2);

		string side = (OrderType() == OP_BUY) ? "BUY" : "SELL";
		double openPrice = OrderOpenPrice();
		double curPrice = (OrderType() == OP_BUY) ? MarketInfo(osym, MODE_BID) : MarketInfo(osym, MODE_ASK);

		// Common indicators
		double emaFast0, emaSlow0; GetEMAs(osym, tf, EMA_Fast, EMA_Slow, 0, emaFast0, emaSlow0);
		double rsi0 = iRSI(osym, tf, RSI_Period, PRICE_CLOSE, 0);

		bool shouldClose = false;
		string reason = "";

		if(strategy == "EMA_PULLBACK")
		{
			if(side == "BUY" && emaFast0 < emaSlow0) { shouldClose = true; reason = "EMA fast < EMA slow"; }
			if(side == "SELL" && emaFast0 > emaSlow0) { shouldClose = true; reason = "EMA fast > EMA slow"; }
		}
		else if(strategy == "RSI_PULLBACK")
		{
			if(side == "BUY")
			{
				if(emaFast0 < emaSlow0) { shouldClose = true; reason = "Trend flipped bearish"; }
				else if(rsi0 >= RSI_SellZone_High) { shouldClose = true; reason = "RSI exited buy zone"; }
				else if(IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0)) { shouldClose = true; reason = "Bearish reversal pattern"; }
			}
			else // SELL
			{
				if(emaFast0 > emaSlow0) { shouldClose = true; reason = "Trend flipped bullish"; }
				else if(rsi0 <= RSI_BuyZone_Low) { shouldClose = true; reason = "RSI exited sell zone"; }
				else if(IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0)) { shouldClose = true; reason = "Bullish reversal pattern"; }
			}
		}
		else if(strategy == "ASIA_RETEST")
		{
			// Generic reversal confirmation to exit
			if(side == "BUY" && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) { shouldClose = true; reason = "Bearish reversal on retest"; }
			if(side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) { shouldClose = true; reason = "Bullish reversal on retest"; }
		}
		else if(strategy == "ASIA_BREAKOUT")
		{
			// Recompute Asia range
			datetime now = TimeCurrent();
			datetime sessionStart = ComposeTimeUTC(now, Asia_Session_Start_UTC);
			datetime sessionEnd   = ComposeTimeUTC(now, Asia_Session_End_UTC);
			if(TimeCurrent() <= sessionEnd) { sessionStart -= 24*60*60; sessionEnd -= 24*60*60; }
			double highRange = -DBL_MAX; double lowRange = DBL_MAX;
			for(int k = 1; k < 500; k++)
			{
				datetime bt = iTime(osym, tf, k);
				if(bt == 0) break; if(bt < sessionStart) break;
				if(bt <= sessionEnd && bt >= sessionStart)
				{
					double bh = iHigh(osym, tf, k);
					double bl = iLow(osym, tf, k);
					if(bh > highRange) highRange = bh;
					if(bl < lowRange)  lowRange  = bl;
				}
			}
			if(highRange > -DBL_MAX && lowRange < DBL_MAX)
			{
				double tol = Retest_Tolerance_Points * MarketInfo(osym, MODE_POINT);
				if(side == "BUY")
				{
					// If price falls back below Asia high minus tolerance, consider invalid
					if(curPrice < (highRange - tol)) { shouldClose = true; reason = "Re-entered Asia range (BUY)"; }
					else if(IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0)) { shouldClose = true; reason = "Bearish reversal after breakout"; }
				}
				else // SELL
				{
					if(curPrice > (lowRange + tol)) { shouldClose = true; reason = "Re-entered Asia range (SELL)"; }
					else if(IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0)) { shouldClose = true; reason = "Bullish reversal after breakout"; }
				}
			}
		}
		else if(strategy == "VWAP_REVERSION" || strategy == "VWAP_CONTINUATION")
		{
			double vwapMon;
			if(ComputeSessionVWAP(osym, tf, VWAP_Session_Start_UTC, vwapMon))
			{
				double atrMon = iATR(osym, tf, VWAP_ATR_Period, 0);
				if(atrMon > 0)
				{
					double contBandUp = vwapMon + VWAP_Dev_Mult_Continuation * atrMon;
					double contBandDn = vwapMon - VWAP_Dev_Mult_Continuation * atrMon;
					if(strategy == "VWAP_REVERSION")
					{
						// Close when mean reached (crossed VWAP) or opposite reversal
						if( (side == "BUY"  && curPrice >= vwapMon) || (side == "SELL" && curPrice <= vwapMon) ) { shouldClose = true; reason = "VWAP reached (mean reversion)"; }
						else if( (side == "BUY"  && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) ||
						         (side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) ) { shouldClose = true; reason = "Opposite reversal vs reversion"; }
					}
					else // VWAP_CONTINUATION
					{
						// Close when price falls back inside vwap±1*ATR equivalent (use continuation band breach as invalidation)
						if( (side == "BUY"  && curPrice <= contBandUp) || (side == "SELL" && curPrice >= contBandDn) ) { shouldClose = true; reason = "Lost continuation beyond deviation"; }
						else if( (side == "BUY"  && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) ||
						         (side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) ) { shouldClose = true; reason = "Opposite reversal vs continuation"; }
					}
				}
			}
		}
		else if(strategy == "BB_SQUEEZE_BREAK")
		{
			double bbU = iBands(osym, tf, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 0);
			double bbL = iBands(osym, tf, BB_Period, BB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 0);
			if(bbU != 0 && bbL != 0)
			{
				if( (side == "BUY"  && curPrice < bbU) || (side == "SELL" && curPrice > bbL) ) { shouldClose = true; reason = "Back inside Bollinger band"; }
				else if( (side == "BUY"  && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) ||
				         (side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) ) { shouldClose = true; reason = "Opposite reversal after squeeze"; }
			}
		}
		else if(strategy == "KC_BB_EXPANSION")
		{
			double emaMon = iMA(osym, tf, KC_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
			double atrMon = iATR(osym, tf, KC_ATR_Period, 0);
			if(emaMon != 0 && atrMon != 0)
			{
				double kcUp = emaMon + KC_ATR_Mult * atrMon;
				double kcDn = emaMon - KC_ATR_Mult * atrMon;
				// Invalidate momentum when price returns inside Keltner
				if( (side == "BUY"  && curPrice <= kcUp) || (side == "SELL" && curPrice >= kcDn) ) { shouldClose = true; reason = "Back inside Keltner channel"; }
				else if( (side == "BUY"  && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) ||
				         (side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) ) { shouldClose = true; reason = "Opposite reversal after expansion"; }
			}
		}
		else if(strategy == "LONDON_OPEN_BREAKOUT")
		{
			// Close when London session ends (09:00 UTC) or opposite reversal
			if(!IsInTimeRange("07:00", "09:00"))
			{
				shouldClose = true;
				reason = "London session ended";
			}
			else if( (side == "BUY"  && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) ||
			         (side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) )
			{
				shouldClose = true;
				reason = "Opposite reversal after London breakout";
			}
		}
		else if(strategy == "SUPPORT_RESISTANCE_BOUNCE")
		{
			// Close when price moves away from S/R level or opposite reversal
			double point = MarketInfo(osym, MODE_POINT);
			double tolerance = 300 * point; // 300 points tolerance
			
			// Cari level S/R terdekat
			double nearestSR = 0;
			bool isNearSR = false;
			
			// Cari swing points untuk S/R
			for(int i = 5; i < 50; i++)
			{
				double high = iHigh(osym, tf, i);
				double low = iLow(osym, tf, i);
				
				if(MathAbs(curPrice - high) < tolerance || MathAbs(curPrice - low) < tolerance)
				{
					nearestSR = (MathAbs(curPrice - high) < MathAbs(curPrice - low)) ? high : low;
					isNearSR = true;
					break;
				}
			}
			
			// Close jika sudah jauh dari S/R level
			if(!isNearSR || MathAbs(curPrice - nearestSR) > tolerance * 2)
			{
				shouldClose = true;
				reason = "Moved away from S/R level";
			}
			else if( (side == "BUY"  && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) ||
			         (side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) )
			{
				shouldClose = true;
				reason = "Opposite reversal at S/R level";
			}
		}
		else if(strategy == "FIBONACCI_RETRACEMENT")
		{
			// Close ketika harga sudah jauh dari Fibonacci level atau reversal
			double point = MarketInfo(osym, MODE_POINT);
			double tolerance = 300 * point; // 300 points tolerance
			
			// Cari Fibonacci level terdekat
			double nearestFib = 0;
			bool isNearFib = false;
			
			// Cari swing high/low untuk Fibonacci
			double swingHigh = 0;
			double swingLow = 999999;
			for(int i = 10; i < 50; i++)
			{
				double high = iHigh(osym, tf, i);
				double low = iLow(osym, tf, i);
				if(high > swingHigh) swingHigh = high;
				if(low < swingLow) swingLow = low;
			}
			
			if(swingHigh > 0 && swingLow < 999999)
			{
				double range = swingHigh - swingLow;
				double fib382 = swingHigh - range * 0.382;
				double fib500 = swingHigh - range * 0.500;
				double fib618 = swingHigh - range * 0.618;
				
				// Cek level Fibonacci terdekat
				if(MathAbs(curPrice - fib382) < tolerance) { nearestFib = fib382; isNearFib = true; }
				else if(MathAbs(curPrice - fib500) < tolerance) { nearestFib = fib500; isNearFib = true; }
				else if(MathAbs(curPrice - fib618) < tolerance) { nearestFib = fib618; isNearFib = true; }
			}
			
			// Close jika sudah jauh dari Fibonacci level
			if(!isNearFib || MathAbs(curPrice - nearestFib) > tolerance * 2)
			{
				shouldClose = true;
				reason = "Moved away from Fibonacci level";
			}
			else if( (side == "BUY"  && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) ||
			         (side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) )
			{
				shouldClose = true;
				reason = "Opposite reversal at Fibonacci level";
			}
		}
		else if(strategy == "TREND_LINE_BREAK")
		{
			// Close ketika harga kembali ke trend line atau reversal
			double point = MarketInfo(osym, MODE_POINT);
			double tolerance = 250 * point; // 250 points tolerance
			
			// Cari trend line terdekat (simplified)
			double nearestTrendLine = 0;
			bool isNearTrendLine = false;
			
			// Cari swing points untuk trend line
			for(int i = 5; i < 30; i++)
			{
				double high = iHigh(osym, tf, i);
				double low = iLow(osym, tf, i);
				
				if(MathAbs(curPrice - high) < tolerance || MathAbs(curPrice - low) < tolerance)
				{
					nearestTrendLine = (MathAbs(curPrice - high) < MathAbs(curPrice - low)) ? high : low;
					isNearTrendLine = true;
					break;
				}
			}
			
			// Close jika kembali ke trend line
			if(isNearTrendLine && MathAbs(curPrice - nearestTrendLine) < tolerance)
			{
				shouldClose = true;
				reason = "Returned to trend line";
			}
			else if( (side == "BUY"  && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) ||
			         (side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) )
			{
				shouldClose = true;
				reason = "Opposite reversal after trend break";
			}
		}
		else if(strategy == "VOLUME_PROFILE_IMBALANCE")
		{
			// Close ketika volume kembali normal atau reversal
			double currentVolume = iVolume(osym, tf, 0);
			double avgVolume = 0;
			for(int i = 1; i <= 10; i++)
				avgVolume += iVolume(osym, tf, i);
			avgVolume /= 10;
			
			// Close jika volume sudah kembali normal
			if(currentVolume < avgVolume * 1.5) // Volume turun ke 1.5x rata-rata
			{
				shouldClose = true;
				reason = "Volume returned to normal";
			}
			else if( (side == "BUY"  && (IsBearEngulfing(osym, tf, 0) || IsPinBarBear(osym, tf, 0))) ||
			         (side == "SELL" && (IsBullEngulfing(osym, tf, 0) || IsPinBarBull(osym, tf, 0))) )
			{
				shouldClose = true;
				reason = "Opposite reversal after volume spike";
			}
		}

		if(shouldClose)
		{
			SendAutoCloseSignal(OrderTicket(), osym, side, openPrice, curPrice, strategy, reason);
		}
	}
}

// === VWAP helpers ===
bool ComputeSessionVWAP(string symbol, int tf, string sessionStartUTC, double &vwap)
{
	vwap = 0;
	datetime now = TimeCurrent();
	datetime sessionStart = ComposeTimeUTC(now, sessionStartUTC);
	if(TimeCurrent() <= sessionStart) sessionStart -= 24*60*60;
	double sumPV = 0.0;
	double sumV  = 0.0;
	for(int i = 0; i < 1500; i++)
	{
		datetime bt = iTime(symbol, tf, i);
		if(bt == 0) break;
		if(bt < sessionStart) break;
		double high = iHigh(symbol, tf, i);
		double low  = iLow(symbol, tf, i);
		double close= iClose(symbol, tf, i);
		double tp = (high + low + close) / 3.0;
		double vol = iVolume(symbol, tf, i);
		if(vol <= 0) vol = 1; // fallback for tick volume issues
		sumPV += tp * vol;
		sumV  += vol;
	}
	if(sumV <= 0) return false;
	vwap = sumPV / sumV;
	return true;
}

bool HasOpenOrderForStrategy(string symbol, string strategy)
{
	for(int i = 0; i < OrdersTotal(); i++)
	{
		if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
		string osym = OrderSymbol();
		// allow broker suffix tolerance
		bool symOk = (osym == symbol) || (StringFind(osym, symbol) >= 0) || (StringFind(symbol, osym) >= 0);
		if(!symOk) continue;
		string c = OrderComment();
		if(StringFind(c, "AutoTrade") >= 0 && StringFind(c, strategy) >= 0)
			return true;
	}
	return false;
}

bool WasTicketNotified(int ticket)
{
    for(int i = 0; i < g_closedNotifiedCount; i++)
        if(g_closedNotifiedTickets[i] == ticket) return true;
    return false;
}

void MarkTicketNotified(int ticket)
{
    // Simple ring buffer of last 200 tickets
    if(g_closedNotifiedCount < 200)
    {
        g_closedNotifiedTickets[g_closedNotifiedCount++] = ticket;
    }
    else
    {
        // shift left
        for(int i = 1; i < 200; i++) g_closedNotifiedTickets[i-1] = g_closedNotifiedTickets[i];
        g_closedNotifiedTickets[199] = ticket;
    }
}

void DetectAndNotifyClosedOrders()
{
    // Scan history for recently closed EA orders and send confirmation
    datetime since = TimeCurrent() - 24*60*60; // last 24h window
    int total = OrdersHistoryTotal();
    for(int i = total - 1; i >= 0; i--)
    {
        if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
        string comment = OrderComment();
        if(StringFind(comment, "AutoTrade") < 0) continue; // only EA orders

        datetime ctime = OrderCloseTime();
        if(ctime <= 0 || ctime < since) break; // history is chronological

        int ticket = OrderTicket();
        if(WasTicketNotified(ticket)) continue;

        string symbol = OrderSymbol();
        string side = (OrderType() == OP_BUY) ? "BUY" : "SELL";
        double lots = OrderLots();
        double openPrice = OrderOpenPrice();
        double closePrice = OrderClosePrice();
        double profit = OrderProfit() + OrderSwap() + OrderCommission();

        SendCloseConfirmation(ticket, symbol, side, lots, openPrice, closePrice, profit);
        MarkTicketNotified(ticket);
        // Continue scanning in case multiple closed this tick
    }
}

//+------------------------------------------------------------------+
//| Dashboard Functions                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| CreateDashboardPanel - Create the main dashboard panel           |
//+------------------------------------------------------------------+
void CreateDashboardPanel()
{
    // Cleanup existing objects first
    CleanupDashboard();
    
    // Main panel background
    string panelName = "EA_Dashboard_Panel";
    ObjectCreate(panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSet(panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSet(panelName, OBJPROP_XDISTANCE, 10);
    ObjectSet(panelName, OBJPROP_YDISTANCE, 30);
    ObjectSet(panelName, OBJPROP_XSIZE, 320);
    ObjectSet(panelName, OBJPROP_YSIZE, 400);
    ObjectSet(panelName, OBJPROP_BGCOLOR, C'15,15,25');
    ObjectSet(panelName, OBJPROP_BORDER_COLOR, C'60,60,80');
    ObjectSet(panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSet(panelName, OBJPROP_WIDTH, 2);
    ObjectSet(panelName, OBJPROP_BACK, false);
    ObjectSet(panelName, OBJPROP_SELECTABLE, false);
    ObjectSet(panelName, OBJPROP_HIDDEN, true);
    g_dashboardObjects[g_dashboardObjectCount++] = panelName;
    
    // Title
    string titleName = "EA_Dashboard_Title";
    ObjectCreate(titleName, OBJ_LABEL, 0, 0, 0);
    ObjectSet(titleName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSet(titleName, OBJPROP_XDISTANCE, 20);
    ObjectSet(titleName, OBJPROP_YDISTANCE, 40);
    ObjectSetText(titleName, "EA SIGNAL DASHBOARD", 12, "Arial Bold", C'255,255,255');
    ObjectSet(titleName, OBJPROP_SELECTABLE, false);
    ObjectSet(titleName, OBJPROP_HIDDEN, true);
    g_dashboardObjects[g_dashboardObjectCount++] = titleName;
    
    // Status line
    string statusName = "EA_Dashboard_Status";
    ObjectCreate(statusName, OBJ_LABEL, 0, 0, 0);
    ObjectSet(statusName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSet(statusName, OBJPROP_XDISTANCE, 20);
    ObjectSet(statusName, OBJPROP_YDISTANCE, 65);
    ObjectSetText(statusName, "Status: Active", 10, "Arial", C'0,255,0');
    ObjectSet(statusName, OBJPROP_SELECTABLE, false);
    ObjectSet(statusName, OBJPROP_HIDDEN, true);
    g_dashboardObjects[g_dashboardObjectCount++] = statusName;
    
    // Active strategies section
    string strategiesTitleName = "EA_Dashboard_Strategies_Title";
    ObjectCreate(strategiesTitleName, OBJ_LABEL, 0, 0, 0);
    ObjectSet(strategiesTitleName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSet(strategiesTitleName, OBJPROP_XDISTANCE, 20);
    ObjectSet(strategiesTitleName, OBJPROP_YDISTANCE, 90);
    ObjectSetText(strategiesTitleName, "Active Strategies:", 10, "Arial Bold", C'255,255,255');
    ObjectSet(strategiesTitleName, OBJPROP_SELECTABLE, false);
    ObjectSet(strategiesTitleName, OBJPROP_HIDDEN, true);
    g_dashboardObjects[g_dashboardObjectCount++] = strategiesTitleName;
    
    // Strategy status lines (will be updated dynamically)
    for(int i = 0; i < 15; i++)
    {
        string strategyName = "EA_Dashboard_Strategy_" + IntegerToString(i);
        ObjectCreate(strategyName, OBJ_LABEL, 0, 0, 0);
        ObjectSet(strategyName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSet(strategyName, OBJPROP_XDISTANCE, 30);
        ObjectSet(strategyName, OBJPROP_YDISTANCE, 110 + i * 14);
        ObjectSetText(strategyName, "", 9, "Arial", C'200,200,200');
        ObjectSet(strategyName, OBJPROP_SELECTABLE, false);
        ObjectSet(strategyName, OBJPROP_HIDDEN, true);
        g_dashboardObjects[g_dashboardObjectCount++] = strategyName;
    }
    
    // Orders section
    string ordersTitleName = "EA_Dashboard_Orders_Title";
    ObjectCreate(ordersTitleName, OBJ_LABEL, 0, 0, 0);
    ObjectSet(ordersTitleName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSet(ordersTitleName, OBJPROP_XDISTANCE, 20);
    ObjectSet(ordersTitleName, OBJPROP_YDISTANCE, 330);
    ObjectSetText(ordersTitleName, "Open Orders:", 10, "Arial Bold", C'255,255,255');
    ObjectSet(ordersTitleName, OBJPROP_SELECTABLE, false);
    ObjectSet(ordersTitleName, OBJPROP_HIDDEN, true);
    g_dashboardObjects[g_dashboardObjectCount++] = ordersTitleName;
    
    // Orders info
    string ordersInfoName = "EA_Dashboard_Orders_Info";
    ObjectCreate(ordersInfoName, OBJ_LABEL, 0, 0, 0);
    ObjectSet(ordersInfoName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSet(ordersInfoName, OBJPROP_XDISTANCE, 30);
    ObjectSet(ordersInfoName, OBJPROP_YDISTANCE, 350);
    ObjectSetText(ordersInfoName, "Total: 0", 9, "Arial", C'200,200,200');
    ObjectSet(ordersInfoName, OBJPROP_SELECTABLE, false);
    ObjectSet(ordersInfoName, OBJPROP_HIDDEN, true);
    g_dashboardObjects[g_dashboardObjectCount++] = ordersInfoName;
    
    Print("Dashboard panel created with ", g_dashboardObjectCount, " objects");
}

//+------------------------------------------------------------------+
//| UpdateDashboard - Update dashboard information                   |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    if(g_dashboardObjectCount == 0) return;
    
    // Update status
    string statusText = "Status: Active | Time: " + TimeToStr(TimeCurrent(), TIME_MINUTES);
    ObjectSetText("EA_Dashboard_Status", statusText, 10, "Arial", C'0,255,0');
    
    // Get strategy status with order counts
    string strategies[20];
    int strategyCount = 0;
    bool strategyEnabled[20];
    
    if(Enable_EMA_Pullback) { strategies[strategyCount] = "EMA Pullback"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_Engulfing) { strategies[strategyCount] = "Engulfing"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_Pin_Bar) { strategies[strategyCount] = "Pin Bar"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_Volume_Spike) { strategies[strategyCount] = "Volume Spike"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_Asia_Breakout) { strategies[strategyCount] = "Asia Breakout"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_London_Open_Breakout) { strategies[strategyCount] = "London Breakout"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_Support_Resistance_Bounce) { strategies[strategyCount] = "S/R Bounce"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_Fibonacci_Retracement) { strategies[strategyCount] = "Fibonacci"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_Trend_Line_Break) { strategies[strategyCount] = "Trend Line"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_Volume_Profile_Imbalance) { strategies[strategyCount] = "Volume Profile"; strategyEnabled[strategyCount] = true; strategyCount++; }
    
    // Add additional strategies that might have orders
    if(Enable_KC_BB_Expansion) { strategies[strategyCount] = "KC BB Expansion"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_BB_Squeeze) { strategies[strategyCount] = "BB Squeeze Break"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_VWAP) { strategies[strategyCount] = "VWAP Reversion"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_Asia_Retest) { strategies[strategyCount] = "Asia Retest"; strategyEnabled[strategyCount] = true; strategyCount++; }
    if(Enable_RSI_Pullback) { strategies[strategyCount] = "RSI Pullback"; strategyEnabled[strategyCount] = true; strategyCount++; }
    
    // Add disabled strategies
    if(!Enable_EMA_Pullback) { strategies[strategyCount] = "EMA Pullback"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_Engulfing) { strategies[strategyCount] = "Engulfing"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_Pin_Bar) { strategies[strategyCount] = "Pin Bar"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_Volume_Spike) { strategies[strategyCount] = "Volume Spike"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_Asia_Breakout) { strategies[strategyCount] = "Asia Breakout"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_London_Open_Breakout) { strategies[strategyCount] = "London Breakout"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_Support_Resistance_Bounce) { strategies[strategyCount] = "S/R Bounce"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_Fibonacci_Retracement) { strategies[strategyCount] = "Fibonacci"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_Trend_Line_Break) { strategies[strategyCount] = "Trend Line"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_Volume_Profile_Imbalance) { strategies[strategyCount] = "Volume Profile"; strategyEnabled[strategyCount] = false; strategyCount++; }
    
    // Add disabled additional strategies
    if(!Enable_KC_BB_Expansion) { strategies[strategyCount] = "KC BB Expansion"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_BB_Squeeze) { strategies[strategyCount] = "BB Squeeze Break"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_VWAP) { strategies[strategyCount] = "VWAP Reversion"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_Asia_Retest) { strategies[strategyCount] = "Asia Retest"; strategyEnabled[strategyCount] = false; strategyCount++; }
    if(!Enable_RSI_Pullback) { strategies[strategyCount] = "RSI Pullback"; strategyEnabled[strategyCount] = false; strategyCount++; }
    
    Print("DEBUG: Total strategies found: ", strategyCount);
    
    // If no strategies found, add some basic ones to show
    if(strategyCount == 0)
    {
        Print("DEBUG: No strategies found, adding basic ones");
        strategies[strategyCount] = "EMA Pullback"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "Engulfing"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "Pin Bar"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "Volume Spike"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "Asia Breakout"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "London Breakout"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "S/R Bounce"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "Fibonacci"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "Trend Line"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "Volume Profile"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "KC BB Expansion"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "BB Squeeze Break"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "VWAP Reversion"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "Asia Retest"; strategyEnabled[strategyCount] = false; strategyCount++;
        strategies[strategyCount] = "RSI Pullback"; strategyEnabled[strategyCount] = false; strategyCount++;
        Print("DEBUG: Added basic strategies, total now: ", strategyCount);
    }
    
    // Update strategy status with order counts
    for(int i = 0; i < 15 && i < strategyCount; i++)
    {
        string strategyName = "EA_Dashboard_Strategy_" + IntegerToString(i);
        string status = "";
        color statusColor = C'200,200,200';
        
        Print("DEBUG: Processing strategy ", i, ": ", strategies[i], " enabled: ", strategyEnabled[i]);
        
        // Count orders for this strategy
        string strategyCode = GetStrategyCode(strategies[i]);
        Print("DEBUG: Looking for strategy: ", strategies[i], " -> code: ", strategyCode);
        int orderCount = CountOrdersForStrategy(strategyCode);
        
        if(strategyEnabled[i])
        {
            status = "[ON] " + strategies[i] + " - " + IntegerToString(orderCount) + " orders";
            statusColor = C'0,255,0';
        }
        else
        {
            status = "[OFF] " + strategies[i] + " - " + IntegerToString(orderCount) + " orders";
            statusColor = C'255,100,100';
        }
        
        ObjectSetText(strategyName, status, 9, "Arial", statusColor);
    }
    
    // Update orders info
    int totalOrders = OrdersTotal();
    int eaOrders = 0;
    double totalProfit = 0;
    
    for(int i = 0; i < totalOrders; i++)
    {
        if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
        string comment = OrderComment();
        if(StringFind(comment, "AutoTrade") >= 0)
        {
            eaOrders++;
            totalProfit += OrderProfit() + OrderSwap() + OrderCommission();
        }
    }
    
    string ordersText = "Total: " + IntegerToString(totalOrders) + " | EA: " + IntegerToString(eaOrders);
    if(eaOrders > 0)
    {
        ordersText += " | P&L: " + DoubleToString(totalProfit, 2);
    }
    
    color profitColor = C'200,200,200';
    if(totalProfit > 0) profitColor = C'0,255,0';
    else if(totalProfit < 0) profitColor = C'255,0,0';
    
    ObjectSetText("EA_Dashboard_Orders_Info", ordersText, 9, "Arial", profitColor);
}

//+------------------------------------------------------------------+
//| CountOrdersForStrategy - Count orders for specific strategy      |
//+------------------------------------------------------------------+
int CountOrdersForStrategy(string strategy)
{
    int count = 0;
    int total = OrdersTotal();
    
    Print("DEBUG: Counting orders for strategy: ", strategy, " (Total orders: ", total, ")");
    
    for(int i = 0; i < total; i++)
    {
        if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) 
        {
            Print("DEBUG: Failed to select order ", i);
            continue;
        }
        
        string comment = OrderComment();
        Print("DEBUG: Order ", i, " comment: '", comment, "'");
        
        // Check if this order belongs to the strategy
        if(StringFind(comment, "AutoTrade") >= 0)
        {
            Print("DEBUG: Found AutoTrade order: ", comment);
            // Extract strategy from comment
            string orderStrategy = ExtractStrategyFromComment(comment);
            Print("DEBUG: Extracted strategy: '", orderStrategy, "' vs looking for: '", strategy, "'");
            
            if(orderStrategy == strategy)
            {
                count++;
                Print("DEBUG: Match found! Count now: ", count);
            }
            else
            {
                Print("DEBUG: No match - orderStrategy='", orderStrategy, "' strategy='", strategy, "'");
            }
        }
        else
        {
            Print("DEBUG: Order ", i, " is not AutoTrade order");
        }
    }
    
    Print("DEBUG: Final count for strategy '", strategy, "': ", count);
    return count;
}

//+------------------------------------------------------------------+
//| GetStrategyCode - Convert display name to strategy code          |
//+------------------------------------------------------------------+
string GetStrategyCode(string displayName)
{
    if(displayName == "EMA Pullback") return "EMA_PULLBACK";
    if(displayName == "Engulfing") return "ENGULFING";
    if(displayName == "Pin Bar") return "PIN_BAR";
    if(displayName == "Volume Spike") return "VOLUME_SPIKE";
    if(displayName == "Asia Breakout") return "ASIA_BREAKOUT";
    if(displayName == "London Breakout") return "LONDON_OPEN_BREAKOUT";
    if(displayName == "S/R Bounce") return "SUPPORT_RESISTANCE_BOUNCE";
    if(displayName == "Fibonacci") return "FIBONACCI_RETRACEMENT";
    if(displayName == "Trend Line") return "TREND_LINE_BREAK";
    if(displayName == "Volume Profile") return "VOLUME_PROFILE_IMBALANCE";
    
    // Additional strategies that might be used
    if(displayName == "RSI Pullback") return "RSI_PULLBACK";
    if(displayName == "Asia Retest") return "ASIA_RETEST";
    if(displayName == "VWAP Reversion") return "VWAP_REVERSION";
    if(displayName == "VWAP Continuation") return "VWAP_CONTINUATION";
    if(displayName == "BB Squeeze Break") return "BB_SQUEEZE_BREAK";
    if(displayName == "KC BB Expansion") return "KC_BB_EXPANSION";
    
    return displayName;
}

//+------------------------------------------------------------------+
//| ExtractStrategyFromComment - Extract strategy name from comment  |
//+------------------------------------------------------------------+
string ExtractStrategyFromComment(string comment)
{
    Print("DEBUG: Extracting strategy from comment: '", comment, "'");
    
    // Comment format: "AutoTrade: STRATEGY_NAME"
    if(StringFind(comment, "AutoTrade: ") == 0)
    {
        string strategy = StringSubstr(comment, 11); // Remove "AutoTrade: "
        Print("DEBUG: Extracted strategy: '", strategy, "'");
        return strategy;
    }
    
    // Try alternative format: "AutoTrade_STRATEGY_NAME"
    if(StringFind(comment, "AutoTrade_") == 0)
    {
        string strategy = StringSubstr(comment, 10); // Remove "AutoTrade_"
        Print("DEBUG: Extracted strategy (alt format): '", strategy, "'");
        return strategy;
    }
    
    Print("DEBUG: No AutoTrade prefix found in comment");
    return "";
}

//+------------------------------------------------------------------+
//| CheckConfigChanges - Detect config changes and refresh dashboard  |
//+------------------------------------------------------------------+
void CheckConfigChanges()
{
    bool configChanged = false;
    
    if(g_lastEnableEMA != Enable_EMA_Pullback) { g_lastEnableEMA = Enable_EMA_Pullback; configChanged = true; }
    if(g_lastEnableEngulfing != Enable_Engulfing) { g_lastEnableEngulfing = Enable_Engulfing; configChanged = true; }
    if(g_lastEnablePinBar != Enable_Pin_Bar) { g_lastEnablePinBar = Enable_Pin_Bar; configChanged = true; }
    if(g_lastEnableVolumeSpike != Enable_Volume_Spike) { g_lastEnableVolumeSpike = Enable_Volume_Spike; configChanged = true; }
    if(g_lastEnableAsiaBreakout != Enable_Asia_Breakout) { g_lastEnableAsiaBreakout = Enable_Asia_Breakout; configChanged = true; }
    if(g_lastEnableLondonBreakout != Enable_London_Open_Breakout) { g_lastEnableLondonBreakout = Enable_London_Open_Breakout; configChanged = true; }
    if(g_lastEnableSRBounce != Enable_Support_Resistance_Bounce) { g_lastEnableSRBounce = Enable_Support_Resistance_Bounce; configChanged = true; }
    if(g_lastEnableFibonacci != Enable_Fibonacci_Retracement) { g_lastEnableFibonacci = Enable_Fibonacci_Retracement; configChanged = true; }
    if(g_lastEnableTrendLine != Enable_Trend_Line_Break) { g_lastEnableTrendLine = Enable_Trend_Line_Break; configChanged = true; }
    if(g_lastEnableVolumeProfile != Enable_Volume_Profile_Imbalance) { g_lastEnableVolumeProfile = Enable_Volume_Profile_Imbalance; configChanged = true; }
    
    if(configChanged)
    {
        Print("Config change detected, refreshing dashboard...");
        RefreshDashboard();
    }
}

//+------------------------------------------------------------------+
//| RefreshDashboard - Force refresh dashboard panel                 |
//+------------------------------------------------------------------+
void RefreshDashboard()
{
    Print("Refreshing dashboard panel...");
    CleanupDashboard();
    CreateDashboardPanel();
}

//+------------------------------------------------------------------+
//| CleanupDashboard - Remove all dashboard objects                  |
//+------------------------------------------------------------------+
void CleanupDashboard()
{
    for(int i = 0; i < g_dashboardObjectCount; i++)
    {
        ObjectDelete(g_dashboardObjects[i]);
    }
    g_dashboardObjectCount = 0;
}
