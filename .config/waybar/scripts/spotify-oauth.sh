#!/usr/bin/env bash

# Script to complete Spotify OAuth flow and get initial tokens
# This only needs to be run once to authorize the application

CONFIG_FILE="$HOME/.config/mufetch/config.yaml"
TOKEN_FILE="$HOME/.config/waybar/spotify_token.json"
REDIRECT_URI="http://localhost:8888/callback"
SCOPES="user-read-currently-playing user-read-playback-state"

# Read credentials
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

CLIENT_ID=$(grep "spotify_client_id:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
CLIENT_SECRET=$(grep "spotify_client_secret:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "Error: Could not read client ID or secret from config file"
    exit 1
fi

# Check if we already have valid tokens
if [ -f "$TOKEN_FILE" ]; then
    EXPIRES_AT=$(jq -r '.expires_at' "$TOKEN_FILE" 2>/dev/null)
    if [ -n "$EXPIRES_AT" ] && [ "$EXPIRES_AT" != "null" ]; then
        CURRENT_TIME=$(date +%s)
        if [ "$CURRENT_TIME" -lt "$((EXPIRES_AT - 60))" ]; then
            echo "You already have valid tokens! No need to re-authenticate."
            echo "Token file: $TOKEN_FILE"
            exit 0
        fi
    fi
fi

# Generate state for security
STATE=$(openssl rand -hex 16 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1)

# Build authorization URL
AUTH_URL="https://accounts.spotify.com/authorize?response_type=code&client_id=${CLIENT_ID}&scope=$(echo -n "$SCOPES" | jq -sRr @uri)&redirect_uri=$(echo -n "$REDIRECT_URI" | jq -rR @uri)&state=${STATE}"

echo "Starting OAuth flow..."
echo ""
echo "1. Opening browser for authorization..."
echo "2. After authorizing, you'll be redirected to localhost"
echo "3. The script will automatically complete the authentication"
echo ""
echo "If the browser doesn't open automatically, visit this URL:"
echo "$AUTH_URL"
echo ""

# Open browser
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$AUTH_URL" 2>/dev/null &
elif command -v open >/dev/null 2>&1; then
    open "$AUTH_URL" 2>/dev/null &
else
    echo "Please open the URL above in your browser"
fi

# Start temporary HTTP server to receive callback
echo "Waiting for authorization callback..."

# Create Python script for HTTP server
TEMP_SERVER=$(mktemp)
cat > "$TEMP_SERVER" << 'PYTHON_EOF'
import http.server
import socketserver
import urllib.parse
import sys
import json

class CallbackHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if '/callback' in self.path:
            parsed = urllib.parse.urlparse(self.path)
            params = urllib.parse.parse_qs(parsed.query)
            
            if 'code' in params:
                code = params['code'][0]
                state = params.get('state', [None])[0]
                
                # Send response to browser
                self.send_response(200)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                self.wfile.write(b'<html><body><h1>Authorization successful!</h1><p>You can close this window.</p></body></html>')
                
                # Write code and state to file for parent script
                with open('/tmp/spotify_oauth_code.txt', 'w') as f:
                    f.write(f"{code}\n{state}\n")
                
                print("Authorization code received!", file=sys.stderr)
            else:
                error = params.get('error', ['Unknown error'])[0]
                self.send_response(400)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                self.wfile.write(f'<html><body><h1>Error: {error}</h1></body></html>'.encode())
                with open('/tmp/spotify_oauth_code.txt', 'w') as f:
                    f.write(f"ERROR\n{error}\n")
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

PORT = 8888
with socketserver.TCPServer(("", PORT), CallbackHandler) as httpd:
    httpd.timeout = 300  # 5 minute timeout
    httpd.handle_request()
PYTHON_EOF

# Run the server
python3 "$TEMP_SERVER" 2>&1 &
SERVER_PID=$!

# Wait for callback (max 5 minutes)
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if [ -f /tmp/spotify_oauth_code.txt ]; then
        sleep 1  # Give server time to write
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Kill the server
kill $SERVER_PID 2>/dev/null
rm -f "$TEMP_SERVER"

# Check if we got the code
if [ ! -f /tmp/spotify_oauth_code.txt ]; then
    echo "Error: Authorization timeout or callback not received"
    exit 1
fi

AUTH_CODE=$(head -n 1 /tmp/spotify_oauth_code.txt)
RECEIVED_STATE=$(sed -n '2p' /tmp/spotify_oauth_code.txt)
rm -f /tmp/spotify_oauth_code.txt

if [ "$AUTH_CODE" = "ERROR" ]; then
    ERROR_MSG=$(sed -n '2p' /tmp/spotify_oauth_code.txt 2>/dev/null || echo "Unknown error")
    echo "Error during authorization: $ERROR_MSG"
    exit 1
fi

# Verify state
if [ "$RECEIVED_STATE" != "$STATE" ]; then
    echo "Error: State mismatch. Possible security issue."
    exit 1
fi

echo "Authorization code received!"
echo "Exchanging code for tokens..."

# Exchange authorization code for tokens
TOKEN_RESPONSE=$(curl -s -X POST "https://accounts.spotify.com/api/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "code=$AUTH_CODE" \
    -d "redirect_uri=$REDIRECT_URI" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET")

# Check for errors
if echo "$TOKEN_RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
    ERROR_MSG=$(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error' 2>/dev/null)
    echo "Error exchanging code for tokens: $ERROR_MSG"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

# Extract tokens
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null)
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token' 2>/dev/null)
EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in' 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo "Error: Failed to get access token"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

# Calculate expiration time
CURRENT_TIME=$(date +%s)
EXPIRES_AT=$((CURRENT_TIME + EXPIRES_IN))

# Save tokens
mkdir -p "$(dirname "$TOKEN_FILE")"
echo "{\"access_token\":\"$ACCESS_TOKEN\",\"expires_at\":$EXPIRES_AT,\"refresh_token\":\"$REFRESH_TOKEN\"}" > "$TOKEN_FILE"

echo "Success! Tokens saved to $TOKEN_FILE"
echo ""
echo "You can now use the spotify-info.sh and spotify-art.sh scripts."
echo "The tokens will be automatically refreshed when needed."

