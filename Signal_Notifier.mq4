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

//=== Globals ===
datetime g_lastBarTime = 0;
datetime g_lastHttpPollTime = 0;

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
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Kill timer
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

    // Execute incoming trade/close commands from backend
    CheckTradeCommands();
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

	if(symbol == "" || (side != "BUY" && side != "SELL") || lots <= 0)
	{
		Print("❌ Invalid trade parameters");
		return;
	}

	int orderType = (side == "BUY") ? OP_BUY : OP_SELL;
	double price = (orderType == OP_BUY) ? MarketInfo(symbol, MODE_ASK) : MarketInfo(symbol, MODE_BID);

	// Normalize lot and price only; do not set SL/TP (managed by close signals)
	int digits = (int)MarketInfo(symbol, MODE_DIGITS);
	double minLot = MarketInfo(symbol, MODE_MINLOT);
	double maxLot = MarketInfo(symbol, MODE_MAXLOT);
	double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
	if(lotStep > 0) lots = MathFloor(lots / lotStep) * lotStep;
	if(lots < minLot) lots = minLot;
	if(lots > maxLot) lots = maxLot;
	price = NormalizeDouble(price, digits);

	// Force SL/TP to zero; EA will send close signals when criteria fail
	sl = 0; tp = 0;

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
