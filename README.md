## EA Signal Tele — MT4 to Telegram Trading System

A lightweight system connecting an MT4 Expert Advisor (EA) with a Go backend to relay trading signals to Telegram and bridge simple file-based trade commands for MT4. Includes Docker support and optional periodic health checks from the EA.

### Project Structure
- `Signal_Notifier.mq4`: MT4 EA. Generates signals (EMA Pullback, Asia Breakout), sends to backend via WebRequest, and can ping backend health on a timer.
- `telegram-trading-system/`: Go backend service.
  - `main.go`: HTTP server, Telegram integration, MT4 file-bridge.
  - `Dockerfile`: Multi-stage build to containerize the backend.
  - `config.env.example`: Example environment variables.

### Backend (Go)
- Requirements: Go 1.22+ or Docker.
- Key env vars:
  - `TELEGRAM_BOT_TOKEN`: Telegram bot token.
  - `TELEGRAM_CHAT_ID`: Target chat ID.
  - `API_AUTH_TOKEN`: Simple token checked by `/signal`.
  - `PORT`: Default `:8080`.
  - `MT4_DATA_PATH`: Folder for MT4 bridge files (default `./mt4-files`).

Run locally:
```bash
cd telegram-trading-system
cp config.env.example .env  # edit values
go run .
```

Docker build/run:
```bash
docker build -t telegram-trading-system:latest telegram-trading-system

docker run -d --name tele-signal \
  -p 8080:8080 \
  -e TELEGRAM_BOT_TOKEN=xxxxx \
  -e TELEGRAM_CHAT_ID=xxxxx \
  -e API_AUTH_TOKEN=changeme \
  -e PORT=":8080" \
  -e MT4_DATA_PATH="/data/mt4-files" \
  -v $(pwd)/telegram-trading-system/mt4-files:/data/mt4-files \
  telegram-trading-system:latest
```

HTTP endpoints:
- `POST /signal`: Accepts JSON `{ token, symbol, timeframe, side, strategy, price, ref1, ref2, timestamp }`.
- `POST /webhook`: Telegram callback webhook (for inline buttons).
- `GET /health`: Health/status probe.

### MT4 Expert Advisor
- Configure inputs in `Signal_Notifier.mq4`:
  - Backend: `Backend_URL`, `Api_Auth_Token`.
  - Health: `Enable_Health_Ping`, `Backend_Health_URL`, `Health_Ping_Interval_Sec`.
- Add backend base URLs to MT4 whitelist: Tools → Options → Expert Advisors → "Allow WebRequest for listed URL".
- Attach EA to a chart, adjust strategy inputs, and check the Experts tab for logs.

### MT4 ↔ Backend Bridge
- Backend writes command files to `MT4_DATA_PATH` for MT4-side tools to consume:
  - `trade_command.json` (open trade), `close_command.json` (close trade).
- Ensure the directory exists and is writable (mount as a volume when using Docker).

### Notes
- HTTPS calls from MT4 require valid TLS certificates.
- Open required ports and allow outbound connectivity if running on a VPS.
