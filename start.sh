#!/bin/bash

# Matrix homeserver setup and start script for Ratio1 Worker App
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
CONFIG_FILE="${CONFIG_FILE:-$DATA_DIR/homeserver.yaml}"
PORT="${MATRIX_PORT:-8008}"
SERVER_NAME="${MATRIX_SERVER_NAME:-matrix.local}"
REPORT_STATS="${SYNAPSE_REPORT_STATS:-no}"
SYNAPSE_VERSION="${SYNAPSE_VERSION:-1.115.0}"
VENV_DIR="${SYNAPSE_VENV_DIR:-$DATA_DIR/synapse-venv}"

echo "Setting up Matrix homeserver..."
echo "Server name: $SERVER_NAME"
echo "Port: $PORT"
echo "Synapse version: $SYNAPSE_VERSION"

install_deps() {
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        libffi-dev \
        libssl-dev \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv
}

if ! command -v python3 >/dev/null 2>&1; then
    echo "Installing Python dependencies..."
    install_deps
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
    echo "Installing python3-venv package..."
    install_deps
fi

mkdir -p "$DATA_DIR"

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

CURRENT_VERSION="$($VENV_DIR/bin/python -c 'import synapse; print(synapse.__version__)' 2>/dev/null || true)"
if [ "$CURRENT_VERSION" != "$SYNAPSE_VERSION" ]; then
    echo "Installing Synapse into venv..."
    "$VENV_DIR/bin/python" -m pip install --upgrade pip
    "$VENV_DIR/bin/python" -m pip install "matrix-synapse==$SYNAPSE_VERSION"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Generating homeserver configuration..."
    "$VENV_DIR/bin/python" -m synapse.app.homeserver \
        --generate-config \
        --config-path "$CONFIG_FILE" \
        --data-directory "$DATA_DIR" \
        --server-name "$SERVER_NAME" \
        --report-stats="$REPORT_STATS"
fi

# Update config for Worker App environment
if grep -q "bind_addresses:" "$CONFIG_FILE"; then
    sed -i "s|bind_addresses: \[[^]]*\]|bind_addresses: ['0.0.0.0']|" "$CONFIG_FILE"
fi

if grep -q "^# public_baseurl:" "$CONFIG_FILE"; then
    sed -i "s|^# public_baseurl:.*|public_baseurl: http://localhost:$PORT/|" "$CONFIG_FILE"
elif grep -q "^public_baseurl:" "$CONFIG_FILE"; then
    sed -i "s|^public_baseurl:.*|public_baseurl: http://localhost:$PORT/|" "$CONFIG_FILE"
else
    printf "\npublic_baseurl: http://localhost:%s/\n" "$PORT" >> "$CONFIG_FILE"
fi

echo "Starting Matrix homeserver on port $PORT..."
exec "$VENV_DIR/bin/python" -m synapse.app.homeserver --config-path "$CONFIG_FILE"
