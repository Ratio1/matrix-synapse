#!/bin/bash

# Matrix homeserver setup and start script for Ratio1 Worker App
set -e

DATA_DIR="/data"
CONFIG_FILE="$DATA_DIR/homeserver.yaml"
PORT=8008

echo "Setting up Matrix homeserver..."

# Install Synapse if not present
if ! python3 -c "import synapse" 2>/dev/null; then
    echo "Installing Synapse..."
    apt-get update
    apt-get install -y python3-pip python3-dev libffi-dev libssl-dev python3-venv
    python3 -m pip install --upgrade pip
    python3 -m pip install "matrix-synapse==1.99.0"
fi

# Create data directory if it doesn't exist
mkdir -p $DATA_DIR

# Generate config if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Generating homeserver configuration..."
    python3 -m synapse.app.homeserver \
        --generate-config \
        --config-path $CONFIG_FILE \
        --data-directory $DATA_DIR \
        --server-name "matrix.local" \
        --report-stats=no
fi

# Update config for Worker App environment
sed -i "s/bind_addresses: \['::1'*, '127.0.0.1'*\]/bind_addresses: ['0.0.0.0']/" $CONFIG_FILE
sed -i "s/# public_baseurl: https:\/\/example.com\//public_baseurl: http:\/\/localhost:$PORT\//" $CONFIG_FILE

# Start Synapse
echo "Starting Matrix homeserver on port $PORT..."
exec python3 -m synapse.app.homeserver --config-path $CONFIG_FILE
