#!/bin/bash

# Gatto API Secrets Setup for Fly.io
# Sets up required environment variables and secrets

set -e

APP_NAME="gatto-api"

echo "🔐 Gatto API Secrets Setup"
echo "=========================="
echo "📱 App: $APP_NAME"
echo ""

# Check if flyctl is installed and user is logged in
if ! command -v flyctl &> /dev/null; then
    echo "❌ flyctl is not installed. Please install it first."
    exit 1
fi

if ! flyctl auth whoami &> /dev/null; then
    echo "❌ You are not logged in to Fly.io"
    echo "   Run: flyctl auth login"
    exit 1
fi

echo "Current secrets (if any):"
flyctl secrets list -a "$APP_NAME" 2>/dev/null || echo "No secrets set yet."
echo ""

# Function to set secret with prompt
set_secret() {
    local key="$1"
    local description="$2"
    local current_value="$3"
    
    echo "Setting $key ($description):"
    if [ -n "$current_value" ]; then
        echo "Current value: $current_value"
        read -p "Keep current value? (y/n): " keep
        if [ "$keep" = "y" ] || [ "$keep" = "Y" ]; then
            return
        fi
    fi
    
    read -s -p "Enter $key: " value
    echo ""
    
    if [ -n "$value" ]; then
        flyctl secrets set "$key=$value" -a "$APP_NAME"
        echo "✅ $key set successfully"
    else
        echo "⚠️  Skipping $key (empty value)"
    fi
    echo ""
}

# Read from .env file if it exists
if [ -f ".env" ]; then
    echo "📄 Found .env file. Reading values..."
    source .env 2>/dev/null || true
    echo ""
fi

echo "🔧 Setting up Supabase secrets:"
echo ""

set_secret "SUPABASE_URL" "Supabase project URL" "$SUPABASE_URL"
set_secret "SUPABASE_SERVICE_ROLE_KEY" "Supabase service role key" "$SUPABASE_SERVICE_ROLE_KEY"

echo "🔧 Additional secrets (optional):"
echo ""

set_secret "DATABASE_URL" "Database connection string" "$DATABASE_URL"
set_secret "JWT_SECRET" "JWT signing secret" "$JWT_SECRET"
set_secret "API_KEY" "API key for external services" "$API_KEY"

echo "📋 Final secrets list:"
flyctl secrets list -a "$APP_NAME"

echo ""
echo "✅ Secrets setup completed!"
echo ""
echo "💡 Tips:"
echo "   - Secrets are encrypted and only accessible to your app"
echo "   - Use 'flyctl secrets unset KEY -a $APP_NAME' to remove secrets"
echo "   - Never commit secrets to your repository"
echo "   - Consider using 'flyctl secrets import' for bulk operations"