# Deployment Guide for Render

## Quick Deploy to Render

### Option 1: Using render.yaml (Recommended)

1. Push your code to GitHub
2. Connect your GitHub repo to Render
3. Render will automatically detect `render.yaml` and use those settings
4. Set your environment variables in Render dashboard:
   - `TELEGRAM_BOT_TOKEN`: Your Telegram bot token
   - `TELEGRAM_CHAT_ID`: Your Telegram chat ID

### Option 2: Manual Configuration

1. Create a new Web Service in Render
2. Connect your GitHub repository
3. Use these settings:
   - **Build Command**: `go build -o main ./main.go`
   - **Start Command**: `./main`
   - **Environment**: `Docker`
   - **Dockerfile Path**: `./Dockerfile`

## Environment Variables

Set these in your Render dashboard:

### Required:
- `TELEGRAM_BOT_TOKEN`: Your Telegram bot token
- `TELEGRAM_CHAT_ID`: Your Telegram chat ID

### Optional (with defaults):
- `PORT`: `:8080` (Render will override this)
- `API_AUTH_TOKEN`: `fadil123` (change this for security)
- `MT4_DATA_PATH`: `/opt/render/project/src/mt4-files`
- `ATR_PERIOD`: `14`
- `SL_MULTIPLIER`: `1.5`
- `TP_MULTIPLIER`: `2.0`
- `GOLD_DIGITS`: `3`
- `FOREX_DIGITS`: `5`

## MT4 EA Configuration

Update your EA with the Render URL:

```mql4
input string Backend_Base_URL = "https://your-app-name.onrender.com";
```

## Testing

After deployment, test the endpoints:

- Health: `https://your-app-name.onrender.com/health`
- Signal: `https://your-app-name.onrender.com/signal`
- Webhook: `https://your-app-name.onrender.com/webhook`

## Troubleshooting

### Common Issues:

1. **Build fails**: Check that all Go dependencies are in `go.mod`
2. **Service won't start**: Check environment variables are set
3. **MT4 connection fails**: Ensure `MT4_DATA_PATH` is writable
4. **Telegram not working**: Verify bot token and chat ID

### Logs:

Check Render logs for debugging:
```bash
# In Render dashboard, go to your service -> Logs
```

## Local Development

For local development:

```bash
# Copy environment template
cp config.env.example .env

# Edit .env with your values
nano .env

# Run locally
go run main.go
```
