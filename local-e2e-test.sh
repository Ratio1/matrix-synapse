#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8008}"
CONTAINER_NAME="${CONTAINER_NAME:-matrix-r1-local-test}"
HOMESERVER_CONFIG="${HOMESERVER_CONFIG:-/data/homeserver.yaml}"
PASSWORD="${PASSWORD:-TestPassw0rd!123}"
SUFFIX="$(date +%s)"
ALICE_USER="${ALICE_USER:-alice_${SUFFIX}}"
BOB_USER="${BOB_USER:-bob_${SUFFIX}}"

usage() {
    cat <<'EOF'
Creates two local Matrix users and verifies room/message sync.

Usage:
  ./local-e2e-test.sh [--base-url URL] [--container NAME]
                      [--alice-user USER] [--bob-user USER] [--password PASS]

Examples:
  ./local-e2e-test.sh
  ./local-e2e-test.sh --base-url http://127.0.0.1:8008 --container matrix-r1-local-test
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --base-url) BASE_URL="$2"; shift 2 ;;
        --container) CONTAINER_NAME="$2"; shift 2 ;;
        --alice-user) ALICE_USER="$2"; shift 2 ;;
        --bob-user) BOB_USER="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

BASE_URL="${BASE_URL%/}"

json_get() {
    local key="$1"
    local json_input
    json_input="$(cat)"
    python3 - "$key" "$json_input" <<'PY'
import json
import sys

key = sys.argv[1]
data = json.loads(sys.argv[2])
value = data.get(key)
if value is None:
    sys.exit(1)
print(value)
PY
}

urlencode() {
    python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
}

wait_for_server() {
    echo "Waiting for ${BASE_URL}/_matrix/client/versions ..."
    for _ in $(seq 1 60); do
        if curl -fsS "${BASE_URL}/_matrix/client/versions" >/dev/null 2>&1; then
            echo "Server is reachable."
            return 0
        fi
        sleep 1
    done
    echo "Server not reachable on ${BASE_URL}" >&2
    return 1
}

register_user() {
    local user="$1"
    echo "Registering user '${user}' in container '${CONTAINER_NAME}' ..."
    if ! docker exec "$CONTAINER_NAME" register_new_matrix_user \
        -u "$user" \
        -p "$PASSWORD" \
        --no-admin \
        -c "$HOMESERVER_CONFIG" \
        "$BASE_URL" >/dev/null 2>&1; then
        echo "Registration command failed for '${user}' (may already exist). Continuing to login check."
    fi
}

login_user() {
    local user="$1"
    local attempt
    for attempt in $(seq 1 10); do
        local body code retry_ms retry_s
        body="$(curl -sS -o /tmp/matrix_login_resp.json -w '%{http_code}' -X POST "${BASE_URL}/_matrix/client/v3/login" \
            -H 'Content-Type: application/json' \
            -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"${user}\"},\"password\":\"${PASSWORD}\"}" || true)"
        code="$body"
        body="$(cat /tmp/matrix_login_resp.json 2>/dev/null || true)"

        if [ "$code" = "200" ]; then
            printf '%s' "$body" | json_get access_token
            return 0
        fi

        if [ "$code" = "429" ]; then
            retry_ms="$(printf '%s' "$body" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read() or "{}"); print(d.get("retry_after_ms", 1000))' 2>/dev/null || echo 1000)"
            retry_s=$(( (retry_ms + 999) / 1000 ))
            if [ "$retry_s" -lt 1 ]; then retry_s=1; fi
            echo "Login rate-limited for '${user}' (attempt ${attempt}/10). Retrying in ${retry_s}s..." >&2
            sleep "$retry_s"
            continue
        fi

        echo "Login failed for '${user}' with HTTP ${code}: ${body}" >&2
        return 1
    done

    echo "Login failed for '${user}' after repeated rate limits." >&2
    return 1
}

wait_for_server
register_user "$ALICE_USER"
register_user "$BOB_USER"

echo "Logging in users..."
ALICE_TOKEN="$(login_user "$ALICE_USER")"
BOB_TOKEN="$(login_user "$BOB_USER")"

echo "Creating a public room as '${ALICE_USER}' ..."
CREATE_RESP="$(curl -fsS -X POST "${BASE_URL}/_matrix/client/v3/createRoom" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${ALICE_TOKEN}" \
    -d '{"name":"Local E2E Room","preset":"public_chat"}')"
ROOM_ID="$(printf '%s' "$CREATE_RESP" | json_get room_id)"
ROOM_PATH="$(urlencode "$ROOM_ID")"

echo "Joining '${BOB_USER}' to room ${ROOM_ID} ..."
curl -fsS -X POST "${BASE_URL}/_matrix/client/v3/rooms/${ROOM_PATH}/join" \
    -H "Authorization: Bearer ${BOB_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{}' >/dev/null

MSG="hello-from-${ALICE_USER}-to-${BOB_USER}"
TXN="txn$(date +%s)"
echo "Sending message: ${MSG}"
curl -fsS -X PUT "${BASE_URL}/_matrix/client/v3/rooms/${ROOM_PATH}/send/m.room.message/${TXN}" \
    -H "Authorization: Bearer ${ALICE_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "{\"msgtype\":\"m.text\",\"body\":\"${MSG}\"}" >/dev/null

echo "Checking Bob sync for message..."
SYNC_RESP="$(curl -fsS "${BASE_URL}/_matrix/client/v3/sync?timeout=3000" \
    -H "Authorization: Bearer ${BOB_TOKEN}")"

if printf '%s' "$SYNC_RESP" | grep -q "$MSG"; then
    echo
    echo "E2E OK"
    echo "- Alice user: $ALICE_USER"
    echo "- Bob user:   $BOB_USER"
    echo "- Password:   $PASSWORD"
    echo "- Room ID:    $ROOM_ID"
    exit 0
fi

echo "Did not find expected message in Bob's sync response." >&2
exit 1
