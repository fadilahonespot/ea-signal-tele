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
input double Max_Spread_Points = 350;          // Batas spread (points)
input bool Filter_News = false;                // Placeholder (integrasi optional)

input group "=== Webhook/Backend Settings ==="
input string Backend_URL = "http://localhost:8080/signal"; // URL Go backend
input string Api_Auth_Token = "changeme";                   // Opsi auth sederhana

input group "=== Health Check Settings ==="
input bool   Enable_Health_Ping = true;                      // Aktifkan ping kesehatan backend
input string Backend_Health_URL = "http://localhost:8080/health"; // URL health backend
input int    Health_Ping_Interval_Sec = 60;                  // Interval ping (detik)

input group "=== Symbol/Run Settings ==="
input bool Only_Current_Symbol = true;
input int Magic_Number = 0;                   // not used here, reserved
input bool Send_Once_Per_Candle = true;       // Hindari spam setiap tick

//=== Globals ===
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Signal Notifier EA started. Add backend URL to MT4 WebRequest whitelist: Tools > Options > Expert Advisors > Allow WebRequest for listed URL: ", Backend_URL);

    // Setup health ping timer if enabled
    if(Enable_Health_Ping && Health_Ping_Interval_Sec > 0 && StringLen(Backend_Health_URL) > 0)
    {
        // EventSetTimer uses seconds
        EventSetTimer(Health_Ping_Interval_Sec);
        Print("Health ping enabled every ", Health_Ping_Interval_Sec, "s to ", Backend_Health_URL);
    }
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Kill timer if set
    if(Enable_Health_Ping && Health_Ping_Interval_Sec > 0)
        EventKillTimer();

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
}

//+------------------------------------------------------------------+
//| OnTimer - periodic health ping                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(!Enable_Health_Ping) return;
    if(Health_Ping_Interval_Sec <= 0) return;
    if(StringLen(Backend_Health_URL) == 0) return;

    // Prepare empty body (backend health accepts any method)
    char post[];
    ArrayResize(post, 0);
    char result[];
    string headers;

    ResetLastError();
    int res = WebRequest("application/json", Backend_Health_URL, post, ArraySize(post), result, headers);
    if(res == -1)
    {
        int err = GetLastError();
        Print("Health ping failed ", err, ". Ensure URL is allowed in MT4 settings: ", Backend_Health_URL);
        return;
    }

    string resp = CharArrayToString(result, 0, -1);
    // Keep logs concise; only print brief success message
    Print("Health OK resp=", resp);
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

    if(uptrend && nearPullback && bullCandle)
    {
        SendSignal("BUY", "EMA_PULLBACK", symbol, tf, close0, emaFast0, emaSlow0);
    }
    else if(downtrend && nearPullback && bearCandle)
    {
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
        SendSignal("BUY", "ASIA_BREAKOUT", symbol, tf, close0, highRange, lowRange);
    }
    else if(close0 < lower)
    {
        SendSignal("SELL", "ASIA_BREAKOUT", symbol, tf, close0, highRange, lowRange);
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

//+------------------------------------------------------------------+
//| Send Signal via WebRequest                                       |
//+------------------------------------------------------------------+
void SendSignal(string side, string strategy, string symbol, int tf, double price, double ref1, double ref2)
{
    string json = "{";
    json += "\"token\":\"" + Api_Auth_Token + "\",";
    json += "\"symbol\":\"" + symbol + "\",";
    json += "\"timeframe\":" + IntegerToString(tf) + ",";
    json += "\"side\":\"" + side + "\",";
    json += "\"strategy\":\"" + strategy + "\",";
    json += "\"price\":" + DoubleToString(price, (int)MarketInfo(symbol, MODE_DIGITS)) + ",";
    json += "\"ref1\":" + DoubleToString(ref1, 5) + ",";
    json += "\"ref2\":" + DoubleToString(ref2, 5) + ",";
    json += "\"timestamp\":" + IntegerToString((int)TimeCurrent());
    json += "}";

    char post[]; StringToCharArray(json, post);
    char result[];
    string headers;
    int    status = 0;
    ResetLastError();

    // Ensure Backend_URL is whitelisted in Tools > Options > Expert Advisors > WebRequest
    int res = WebRequest("application/json", Backend_URL, post, ArraySize(post), result, headers);
    if(res == -1)
    {
        int err = GetLastError();
        Print("WebRequest failed ", err, ". Ensure URL is allowed in MT4 settings: ", Backend_URL);
        return;
    }

    string resp = CharArrayToString(result, 0, -1);
    Print("Signal sent [", side, "] strategy=", strategy, " resp=", resp);
}

//+------------------------------------------------------------------+
