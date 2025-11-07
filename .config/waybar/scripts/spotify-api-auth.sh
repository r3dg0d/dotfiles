#!/usr/bin/env bash

# Helper script to get/refresh Spotify OAuth access token
# This needs to be run once to authorize, then tokens are stored

CONFIG_FILE="$HOME/.config/mufetch/config.yaml"
TOKEN_FILE="$HOME/.config/waybar/spotify_token.json"
REDIRECT_URI="http://localhost:8888/callback"

# Read credentials
if [ ! -f "$CONFIG_FILE" ]; then
    exit 1
fi

CLIENT_ID=$(grep "spotify_client_id:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
CLIENT_SECRET=$(grep "spotify_client_secret:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    exit 1
fi

# Check if we have a valid access token
if [ -f "$TOKEN_FILE" ]; then
    ACCESS_TOKEN=$(jq -r '.access_token' "$TOKEN_FILE" 2>/dev/null)
    EXPIRES_AT=$(jq -r '.expires_at' "$TOKEN_FILE" 2>/dev/null)
    REFRESH_TOKEN=$(jq -r '.refresh_token' "$TOKEN_FILE" 2>/dev/null)
    
    # Check if token is still valid (with 60 second buffer)
    if [ -n "$EXPIRES_AT" ] && [ "$EXPIRES_AT" != "null" ]; then
        CURRENT_TIME=$(date +%s)
        if [ "$CURRENT_TIME" -lt "$((EXPIRES_AT - 60))" ] && [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
            echo "$ACCESS_TOKEN"
            exit 0
        fi
    fi
    
    # Try to refresh token if we have refresh_token (with timeout to prevent freezing)
    if [ -n "$REFRESH_TOKEN" ] && [ "$REFRESH_TOKEN" != "null" ]; then
        RESPONSE=$(curl -s --max-time 3 --connect-timeout 1 -X POST "https://accounts.spotify.com/api/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=refresh_token" \
            -d "refresh_token=$REFRESH_TOKEN" \
            -d "client_id=$CLIENT_ID" \
            -d "client_secret=$CLIENT_SECRET" 2>/dev/null)
        
        NEW_ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token' 2>/dev/null)
        NEW_EXPIRES_IN=$(echo "$RESPONSE" | jq -r '.expires_in' 2>/dev/null)
        
        if [ -n "$NEW_ACCESS_TOKEN" ] && [ "$NEW_ACCESS_TOKEN" != "null" ]; then
            CURRENT_TIME=$(date +%s)
            EXPIRES_AT=$((CURRENT_TIME + NEW_EXPIRES_IN))
            echo "{\"access_token\":\"$NEW_ACCESS_TOKEN\",\"expires_at\":$EXPIRES_AT,\"refresh_token\":\"$REFRESH_TOKEN\"}" > "$TOKEN_FILE"
            echo "$NEW_ACCESS_TOKEN"
            exit 0
        fi
    fi
fi

# No valid token
exit 1
