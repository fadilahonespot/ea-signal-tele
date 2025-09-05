package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"sync"

	"github.com/joho/godotenv"
)

// ============ CONFIGURATION ============
type Config struct {
	TelegramBotToken string
	TelegramChatID   string
	APIAuthToken     string
	Port             string
	MT4DataPath      string
}

func loadConfig() *Config {
	return &Config{
		TelegramBotToken: getEnv("TELEGRAM_BOT_TOKEN", ""),
		TelegramChatID:   getEnv("TELEGRAM_CHAT_ID", ""),
		APIAuthToken:     getEnv("API_AUTH_TOKEN", "changeme"),
		Port:             getEnv("PORT", ":8080"),
		MT4DataPath:      getEnv("MT4_DATA_PATH", getDefaultMT4Path()),
	}
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getDefaultMT4Path() string {
	home := os.Getenv("HOME")
	// Try common MT4 paths
	paths := []string{
		filepath.Join(home, ".wine/drive_c/Program Files/MetaTrader 4/MQL4/Files"),
		filepath.Join(home, "AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
		"./mt4-files", // Local fallback
	}

	for _, path := range paths {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}

	// Create local fallback
	localPath := "./mt4-files"
	os.MkdirAll(localPath, 0755)
	return localPath
}

// ============ TYPES ============
type SignalPayload struct {
	Token     string  `json:"token"`
	Symbol    string  `json:"symbol"`
	Timeframe int     `json:"timeframe"`
	Side      string  `json:"side"`
	Strategy  string  `json:"strategy"`
	Price     float64 `json:"price"`
	Ref1      float64 `json:"ref1"`
	Ref2      float64 `json:"ref2"`
	Reason    string  `json:"reason,omitempty"`
	Timestamp int64   `json:"timestamp"`
}

type TelegramMessage struct {
	ChatID      string                  `json:"chat_id"`
	Text        string                  `json:"text"`
	ReplyMarkup *TelegramInlineKeyboard `json:"reply_markup,omitempty"`
}

type TelegramInlineKeyboard struct {
	InlineKeyboard [][]TelegramInlineButton `json:"inline_keyboard"`
}

type TelegramInlineButton struct {
	Text         string `json:"text"`
	CallbackData string `json:"callback_data"`
}

type TelegramCallbackQuery struct {
	ID   string `json:"id"`
	From struct {
		ID int64 `json:"id"`
	} `json:"from"`
	Data    string `json:"data"`
	Message struct {
		MessageID int `json:"message_id"`
		Chat      struct {
			ID int64 `json:"id"`
		} `json:"chat"`
	} `json:"message"`
}

type TelegramUpdate struct {
	UpdateID      int                    `json:"update_id"`
	Message       *TelegramMessage       `json:"message,omitempty"`
	CallbackQuery *TelegramCallbackQuery `json:"callback_query,omitempty"`
}

type TradeCommand struct {
	Action   string  `json:"action"`
	Symbol   string  `json:"symbol"`
	Side     string  `json:"side"`
	Lots     float64 `json:"lots"`
	Price    float64 `json:"price"`
	SL       float64 `json:"sl"`
	TP       float64 `json:"tp"`
	Strategy string  `json:"strategy"`
	Ticket   int     `json:"ticket,omitempty"`
}

// ============ GLOBALS ============
var config *Config
var queueMu sync.Mutex
var commandQueue []TradeCommand

// ============ TELEGRAM FUNCTIONS ============
func sendTelegramWithButtons(text string, buttons *TelegramInlineKeyboard) error {
	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", config.TelegramBotToken)
	msg := TelegramMessage{ChatID: config.TelegramChatID, Text: text, ReplyMarkup: buttons}
	b, _ := json.Marshal(msg)
	resp, err := http.Post(url, "application/json", bytes.NewReader(b))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("telegram send failed: %s", resp.Status)
	}
	return nil
}

func sendTelegram(text string) error {
	return sendTelegramWithButtons(text, nil)
}

func answerCallbackQuery(callbackQueryID, text string) error {
	url := fmt.Sprintf("https://api.telegram.org/bot%s/answerCallbackQuery", config.TelegramBotToken)
	payload := map[string]string{
		"callback_query_id": callbackQueryID,
		"text":              text,
	}
	b, _ := json.Marshal(payload)
	resp, err := http.Post(url, "application/json", bytes.NewReader(b))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	return nil
}

func removeInlineKeyboard(chatID int64, messageID int) error {
	url := fmt.Sprintf("https://api.telegram.org/bot%s/editMessageReplyMarkup", config.TelegramBotToken)
	payload := map[string]interface{}{
		"chat_id":    chatID,
		"message_id": messageID,
		"reply_markup": map[string]interface{}{
			"inline_keyboard": [][]interface{}{},
		},
	}
	b, _ := json.Marshal(payload)
	resp, err := http.Post(url, "application/json", bytes.NewReader(b))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("editMessageReplyMarkup failed: %s", resp.Status)
	}
	return nil
}

// ============ MT4 COMMUNICATION ============
func sendTradeToMT4(trade TradeCommand) error {
	commandFile := filepath.Join(config.MT4DataPath, "trade_command.json")

	data, err := json.Marshal(trade)
	if err != nil {
		return fmt.Errorf("failed to marshal trade: %v", err)
	}

	if err := ioutil.WriteFile(commandFile, data, 0644); err != nil {
		return fmt.Errorf("failed to write trade command: %v", err)
	}

	log.Printf("✅ Trade command sent: %s %s %.2f lots", trade.Symbol, trade.Side, trade.Lots)
	return nil
}

func enqueueTrade(trade TradeCommand) {
	queueMu.Lock()
	defer queueMu.Unlock()
	commandQueue = append(commandQueue, trade)
	log.Printf("📥 Enqueued trade for HTTP bridge: %s %s %.2f lots", trade.Symbol, trade.Side, trade.Lots)
}

func sendCloseToMT4(ticket int, symbol string) error {
	closeCommand := TradeCommand{
		Action: "close",
		Ticket: ticket,
		Symbol: symbol,
	}

	commandFile := filepath.Join(config.MT4DataPath, "close_command.json")
	data, _ := json.Marshal(closeCommand)

	if err := ioutil.WriteFile(commandFile, data, 0644); err != nil {
		return fmt.Errorf("failed to write close command: %v", err)
	}

	log.Printf("🔴 Close command sent: ticket #%d", ticket)
	return nil
}

func enqueueClose(ticket int, symbol string, strategy string) {
	queueMu.Lock()
	defer queueMu.Unlock()
	commandQueue = append(commandQueue, TradeCommand{Action: "close", Ticket: ticket, Symbol: symbol, Strategy: strategy})
	if strategy != "" {
		log.Printf("📥 Enqueued close for HTTP bridge: ticket #%d strategy=%s", ticket, strategy)
	} else {
		log.Printf("📥 Enqueued close for HTTP bridge: ticket #%d", ticket)
	}
}

// ============ MT4 BRIDGE FUNCTIONS ============
func checkMT4Connection() error {
	// Check if MT4 data path exists and is writable
	if _, err := os.Stat(config.MT4DataPath); os.IsNotExist(err) {
		return fmt.Errorf("MT4 data path not found: %s", config.MT4DataPath)
	}

	// Test write permission
	testFile := filepath.Join(config.MT4DataPath, "connection_test.txt")
	if err := ioutil.WriteFile(testFile, []byte("test"), 0644); err != nil {
		return fmt.Errorf("cannot write to MT4 data path: %v", err)
	}
	os.Remove(testFile)

	return nil
}

func waitForMT4Response(responseFile string, timeout time.Duration) ([]byte, error) {
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		if _, err := os.Stat(responseFile); err == nil {
			data, err := ioutil.ReadFile(responseFile)
			if err == nil {
				os.Remove(responseFile) // Clean up
				return data, nil
			}
		}
		time.Sleep(500 * time.Millisecond)
	}

	return nil, fmt.Errorf("timeout waiting for MT4 response")
}

// ============ SIGNAL CALCULATION ============
func calculateSLTP(symbol, side string, price float64) (sl, tp float64) {
	var slPips, tpPips float64

	if strings.Contains(symbol, "XAU") || strings.Contains(symbol, "GOLD") {
		slPips = 5.0  // $5.00 for gold
		tpPips = 10.0 // $10.00 for gold
	} else {
		slPips = 0.0050 // 50 pips for forex (5-digit)
		tpPips = 0.0100 // 100 pips for forex
	}

	if side == "BUY" {
		sl = price - slPips
		tp = price + tpPips
	} else {
		sl = price + slPips
		tp = price - tpPips
	}

	return sl, tp
}

// ============ HTTP HANDLERS ============
func signalHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var p SignalPayload
	if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprintf(w, "invalid json: %v", err)
		return
	}

	if p.Token != config.APIAuthToken {
		w.WriteHeader(http.StatusUnauthorized)
		fmt.Fprint(w, "unauthorized")
		return
	}

	ts := time.Unix(p.Timestamp, 0).Format("15:04:05")

	// Handle different signal types
	var msg string
	var buttons *TelegramInlineKeyboard

	// Handle open confirmation
	if p.Strategy == "ORDER_OPENED_CONFIRMATION" {
		// ref1 = lots, ref2 = ticket, reason = original strategy
		lots := p.Ref1
		msg = fmt.Sprintf(
			"✅ [ORDER OPENED]\n🎫 Ticket: #%.0f\n📊 %s %s %.2f lots\n💰 Entry: %.2f\n🎯 Strategy: %s\n🕐 %s",
			p.Ref2, p.Symbol, p.Side, lots, p.Price, p.Reason, ts,
		)

		signalData := fmt.Sprintf("%s|%s|%.2f|%s", p.Symbol, p.Side, p.Price, p.Reason)
		buttons = &TelegramInlineKeyboard{
			InlineKeyboard: [][]TelegramInlineButton{
				{
					{Text: "❌ DONE", CallbackData: "ignore|" + signalData},
				},
				{
					{Text: "📊 0.1 LOT", CallbackData: "lot|0.1|" + signalData},
					{Text: "📊 0.2 LOT", CallbackData: "lot|0.2|" + signalData},
					{Text: "📊 0.5 LOT", CallbackData: "lot|0.5|" + signalData},
				},
				{
					{Text: "📊 0.7 LOT", CallbackData: "lot|0.7|" + signalData},
					{Text: "📊 1.0 LOT", CallbackData: "lot|1.0|" + signalData},
				},
			},
		}

		// Handle close confirmation
	} else if p.Strategy == "ORDER_CLOSED_CONFIRMATION" {
		// Parse lots;profit;currency from reason field
		reasonParts := strings.Split(p.Reason, ";")
		if len(reasonParts) >= 3 {
			lots, _ := strconv.ParseFloat(reasonParts[0], 64)
			profit, _ := strconv.ParseFloat(reasonParts[1], 64)
			currency := reasonParts[2]

			profitEmoji := "✅"
			profitSign := ""
			if profit < 0 {
				profitEmoji = "❌"
			} else if profit > 0 {
				profitSign = "+"
			}

			msg = fmt.Sprintf(
				"%s [ORDER CLOSED]\n🎫 Ticket: #%.0f\n📊 %s %s %.2f lots\n💰 Open: %.2f\n💰 Close: %.2f\n💵 P&L: %s%.2f %s\n🕐 %s",
				profitEmoji, p.Ref2, p.Symbol, p.Side, lots, p.Ref1, p.Price, profitSign, profit, currency, ts,
			)

			// No buttons for confirmation
			buttons = nil
		}
	} else if strings.HasPrefix(p.Side, "CLOSE_") {
		// CLOSE SIGNAL
		actualSide := strings.TrimPrefix(p.Side, "CLOSE_")
		msg = fmt.Sprintf(
			"🔴 [CLOSE SIGNAL]\n📊 %s %s\n🎯 %s\n💰 Price: %.2f\n📍 Entry: %.2f\n📝 %s\n🕐 %s",
			p.Symbol, actualSide, p.Strategy, p.Price, p.Ref1, p.Reason, ts,
		)

		actualStrategy := strings.TrimPrefix(p.Strategy, "CLOSE_")
		closeData := fmt.Sprintf("%s|%.0f|%s", p.Symbol, p.Ref2, actualStrategy) // Ref2 = ticket
		buttons = &TelegramInlineKeyboard{
			InlineKeyboard: [][]TelegramInlineButton{
				{
					{Text: "🔴 CLOSE ORDER", CallbackData: "close|" + closeData},
					{Text: "⏳ KEEP OPEN", CallbackData: "keep|" + closeData},
				},
			},
		}
	} else if p.Strategy == "ORDERS_STATUS" {
		// EA pushed active orders status in Reason
		msg = fmt.Sprintf("📋 Active Orders\n%s", p.Reason)
		buttons = nil
	} else {
		// OPEN SIGNAL
		msg = fmt.Sprintf(
			"🚨 [OPEN SIGNAL]\n📊 %s\n📈 %s\n🎯 %s\n💰 Price: %.2f\n📝 Pilih ukuran lot di bawah untuk eksekusi.\n🕐 %s",
			p.Symbol, p.Side, p.Strategy, p.Price, ts,
		)

		signalData := fmt.Sprintf("%s|%s|%.2f|%s", p.Symbol, p.Side, p.Price, p.Strategy)
		buttons = &TelegramInlineKeyboard{
			InlineKeyboard: [][]TelegramInlineButton{
				{
					{Text: "❌ IGNORE", CallbackData: "ignore|" + signalData},
				},
				{
					{Text: "📊 0.1 LOT", CallbackData: "lot|0.1|" + signalData},
					{Text: "📊 0.2 LOT", CallbackData: "lot|0.2|" + signalData},
					{Text: "📊 0.5 LOT", CallbackData: "lot|0.5|" + signalData},
				},
				{
					{Text: "📊 0.7 LOT", CallbackData: "lot|0.7|" + signalData},
					{Text: "📊 1.0 LOT", CallbackData: "lot|1.0|" + signalData},
				},
				{
					{Text: "📋 ACTIVE ORDERS", CallbackData: "status"},
				},
			},
		}
	}

	if err := sendTelegramWithButtons(msg, buttons); err != nil {
		log.Printf("❌ Telegram error: %v", err)
		w.WriteHeader(http.StatusBadGateway)
		return
	}

	log.Printf("📱 Signal sent: %s %s", p.Side, p.Strategy)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"ok":true}`))
}

func webhookHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	log.Printf("📩 /webhook from %s", r.RemoteAddr)

	var update TelegramUpdate
	if err := json.NewDecoder(r.Body).Decode(&update); err != nil {
		log.Printf("❌ webhook decode error: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	if update.CallbackQuery != nil {
		log.Printf("🧲 CallbackQuery: id=%s chat=%d msgId=%d data=%q", update.CallbackQuery.ID, update.CallbackQuery.Message.Chat.ID, update.CallbackQuery.Message.MessageID, update.CallbackQuery.Data)
		handleCallbackQuery(update.CallbackQuery)
	} else if update.Message != nil {
		// Handle text commands (no-buttons)
		text := strings.TrimSpace(update.Message.Text)
		if strings.HasPrefix(text, "/orders") || strings.HasPrefix(text, "/status") {
			queueMu.Lock()
			commandQueue = append(commandQueue, TradeCommand{Action: "status"})
			queueMu.Unlock()
			_ = sendTelegram("📋 Fetching active orders...")
		} else {
			log.Printf("💬 Non-callback message received: %q", text)
		}
	}

	w.WriteHeader(http.StatusOK)
}

func handleCallbackQuery(callback *TelegramCallbackQuery) {
	parts := strings.Split(callback.Data, "|")
	if len(parts) < 1 {
		log.Printf("⚠️  Invalid callback data: %q", callback.Data)
		return
	}

	action := parts[0]
	log.Printf("🎛️  Action=%s raw=%q", action, callback.Data)

	switch action {
	case "trade":
		if len(parts) >= 5 {
			symbol := parts[1]
			side := parts[2]
			price, _ := strconv.ParseFloat(parts[3], 64)
			strategy := parts[4]

			lots := 0.1
			sl, tp := calculateSLTP(symbol, side, price)

			log.Printf("🟢 TRADE request: %s %s price=%.2f lots=%.1f sl=%.2f tp=%.2f strat=%s", symbol, side, price, lots, sl, tp, strategy)

			trade := TradeCommand{
				Action:   "open",
				Symbol:   symbol,
				Side:     side,
				Lots:     lots,
				Price:    price,
				SL:       sl,
				TP:       tp,
				Strategy: strategy,
			}

			if err := sendTradeToMT4(trade); err != nil {
				answerCallbackQuery(callback.ID, "❌ Trade failed")
				sendTelegram("❌ Trade failed: " + err.Error())
				log.Printf("❌ sendTradeToMT4 error: %v", err)
			} else {
				answerCallbackQuery(callback.ID, "✅ Trade sent!")
				sendTelegram(fmt.Sprintf("✅ Trade: %s %s %.1f lots @ %.2f", symbol, side, lots, price))
				log.Printf("✅ Trade command dispatched to MT4")
				// Remove inline buttons from the original message (best-effort)
				_ = removeInlineKeyboard(callback.Message.Chat.ID, callback.Message.MessageID)
			}
			enqueueTrade(trade)
		}

	case "lot":
		if len(parts) >= 6 {
			lots, _ := strconv.ParseFloat(parts[1], 64)
			symbol := parts[2]
			side := parts[3]
			price, _ := strconv.ParseFloat(parts[4], 64)
			strategy := parts[5]

			sl, tp := calculateSLTP(symbol, side, price)

			log.Printf("🟢 TRADE request (custom lot): %s %s price=%.2f lots=%.2f sl=%.2f tp=%.2f strat=%s", symbol, side, price, lots, sl, tp, strategy)

			trade := TradeCommand{
				Action:   "open",
				Symbol:   symbol,
				Side:     side,
				Lots:     lots,
				Price:    price,
				SL:       sl,
				TP:       tp,
				Strategy: strategy,
			}

			if err := sendTradeToMT4(trade); err != nil {
				answerCallbackQuery(callback.ID, "❌ Failed")
				log.Printf("❌ sendTradeToMT4 error: %v", err)
			} else {
				answerCallbackQuery(callback.ID, fmt.Sprintf("✅ %.1f lot sent!", lots))
				log.Printf("✅ Trade command dispatched to MT4")
				_ = removeInlineKeyboard(callback.Message.Chat.ID, callback.Message.MessageID)
			}
			enqueueTrade(trade)
		}

	case "close":
		if len(parts) >= 3 {
			symbol := parts[1]
			ticket, _ := strconv.ParseFloat(parts[2], 64)
			actualStrategy := ""
			if len(parts) >= 4 {
				actualStrategy = parts[3]
			}

			log.Printf("🔴 CLOSE request: ticket=%.0f symbol=%s strategy=%s", ticket, symbol, actualStrategy)

			if err := sendCloseToMT4(int(ticket), symbol); err != nil {
				answerCallbackQuery(callback.ID, "❌ Close failed")
				log.Printf("❌ sendCloseToMT4 error: %v", err)
			} else {
				answerCallbackQuery(callback.ID, "✅ Close sent!")
				sendTelegram(fmt.Sprintf("🔴 Close order #%.0f", ticket))
				log.Printf("✅ Close command dispatched to MT4")
				_ = removeInlineKeyboard(callback.Message.Chat.ID, callback.Message.MessageID)
			}
			enqueueClose(int(ticket), symbol, actualStrategy)
		}

	case "status":
		// Enqueue a status command for EA to publish active orders
		queueMu.Lock()
		commandQueue = append(commandQueue, TradeCommand{Action: "status"})
		queueMu.Unlock()
		answerCallbackQuery(callback.ID, "📋 Fetching active orders...")
		_ = removeInlineKeyboard(callback.Message.Chat.ID, callback.Message.MessageID)
	case "ignore":
		answerCallbackQuery(callback.ID, "Signal ignored")
		log.Printf("🚫 Signal ignored by user")

	case "keep":
		answerCallbackQuery(callback.ID, "Order will remain open")
		log.Printf("⏳ Keep order open selected by user")
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	status := map[string]interface{}{
		"status":    "OK",
		"timestamp": time.Now().Unix(),
		"mt4_path":  config.MT4DataPath,
		"telegram":  config.TelegramChatID != "",
		"version":   "2.0.0",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

// ============ HTTP BRIDGE: COMMANDS QUEUE ==========
func commandsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	token := r.URL.Query().Get("token")
	if token == "" {
		token = r.Header.Get("X-API-Token")
	}
	if token != config.APIAuthToken {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte("unauthorized"))
		return
	}

	queueMu.Lock()
	cmds := make([]TradeCommand, len(commandQueue))
	copy(cmds, commandQueue)
	commandQueue = commandQueue[:0]
	queueMu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"ok":       true,
		"count":    len(cmds),
		"commands": cmds,
		"ts":       time.Now().Unix(),
	})
}

// ============ STARTUP ============
func validateConfig() error {
	if config.TelegramBotToken == "" {
		return fmt.Errorf("TELEGRAM_BOT_TOKEN required")
	}
	if config.TelegramChatID == "" {
		return fmt.Errorf("TELEGRAM_CHAT_ID required")
	}

	// Test Telegram connection
	url := fmt.Sprintf("https://api.telegram.org/bot%s/getMe", config.TelegramBotToken)
	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("failed to connect to Telegram: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return fmt.Errorf("invalid Telegram bot token")
	}

	// Ensure MT4 path exists
	if err := os.MkdirAll(config.MT4DataPath, 0755); err != nil {
		return fmt.Errorf("failed to create MT4 path: %v", err)
	}

	return nil
}

func main() {
	log.Println("🚀 Telegram Trading System Starting...")

	// Load .env file
	if err := godotenv.Load(); err != nil {
		log.Printf("⚠️  .env file not found, using environment variables")
	} else {
		log.Println("✅ .env file loaded successfully")
	}

	// Load configuration
	config = loadConfig()

	// Validate configuration
	if err := validateConfig(); err != nil {
		log.Fatalf("❌ Configuration error: %v", err)
	}

	// Check MT4 connection
	if err := checkMT4Connection(); err != nil {
		log.Printf("⚠️  MT4 connection warning: %v", err)
		log.Printf("📁 Using fallback path: %s", config.MT4DataPath)
	} else {
		log.Printf("✅ MT4 connection OK")
	}

	log.Printf("✅ Telegram bot connected")
	log.Printf("📁 MT4 data path: %s", config.MT4DataPath)
	log.Printf("🔑 Auth token: %s...", config.APIAuthToken[:5])

	// Setup HTTP routes
	mux := http.NewServeMux()
	mux.HandleFunc("/signal", signalHandler)     // Receive signals from MT4
	mux.HandleFunc("/webhook", webhookHandler)   // Telegram webhook
	mux.HandleFunc("/health", healthHandler)     // Health check
	mux.HandleFunc("/commands", commandsHandler) // HTTP bridge for remote EA

	// Start server
	log.Printf("🌐 Server starting on %s", config.Port)
	log.Printf("📱 Send test message to verify Telegram...")

	// Send startup notification
	startupMsg := fmt.Sprintf("🚀 Trading System Online\n🕐 %s\n💻 Ready for signals!",
		time.Now().Format("2006-01-02 15:04:05"))
	sendTelegram(startupMsg)

	log.Printf("🎯 Waiting for MT4 signals...")
	log.Printf("🛑 Press Ctrl+C to stop")

	if err := http.ListenAndServe(config.Port, mux); err != nil {
		log.Fatalf("❌ Server failed: %v", err)
	}
}
