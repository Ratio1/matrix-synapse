#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8008}"
WAIT_SECONDS="${WAIT_SECONDS:-120}"
SLEEP_SECONDS=2

usage() {
    cat <<'EOF'
Matrix smoke test

Usage:
  ./smoke-test.sh [--base-url URL] [--wait-seconds N]

Examples:
  ./smoke-test.sh
  ./smoke-test.sh --base-url http://127.0.0.1:8008
  BASE_URL=https://your-tunnel-host ./smoke-test.sh
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --base-url)
            BASE_URL="$2"
            shift 2
            ;;
        --wait-seconds)
            WAIT_SECONDS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 2
            ;;
    esac
done

BASE_URL="${BASE_URL%/}"

pass_count=0
fail_count=0

print_ok() {
    printf '[PASS] %s\n' "$1"
    pass_count=$((pass_count + 1))
}

print_fail() {
    printf '[FAIL] %s\n' "$1"
    fail_count=$((fail_count + 1))
}

http_code() {
    curl -sS -o /tmp/matrix_smoke_body.txt -w '%{http_code}' "$1" || true
}

wait_for_server() {
    echo "Waiting up to ${WAIT_SECONDS}s for ${BASE_URL}/_matrix/client/versions ..."
    elapsed=0
    while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
        code="$(http_code "${BASE_URL}/_matrix/client/versions")"
        if [ "$code" = "200" ]; then
            print_ok "Server is reachable (${BASE_URL})"
            return 0
        fi
        sleep "$SLEEP_SECONDS"
        elapsed=$((elapsed + SLEEP_SECONDS))
    done

    print_fail "Server did not become ready within ${WAIT_SECONDS}s"
    return 1
}

check_endpoint() {
    name="$1"
    path="$2"
    expected_code="$3"
    must_contain="${4:-}"

    url="${BASE_URL}${path}"
    code="$(http_code "$url")"
    body="$(cat /tmp/matrix_smoke_body.txt 2>/dev/null || true)"

    if [ "$code" != "$expected_code" ]; then
        print_fail "${name}: expected HTTP ${expected_code}, got ${code} (${url})"
        return
    fi

    if [ -n "$must_contain" ] && ! printf '%s' "$body" | grep -q "$must_contain"; then
        print_fail "${name}: HTTP ${code} but response missing '${must_contain}'"
        return
    fi

    print_ok "${name}: HTTP ${code}"
}

echo "Running Matrix smoke test against ${BASE_URL}"
wait_for_server || true

check_endpoint "Health endpoint" "/health" "200"
check_endpoint "Client versions" "/_matrix/client/versions" "200" "versions"
check_endpoint "Federation version" "/_matrix/federation/v1/version" "200"

# This path is commonly misconfigured in health checks. Report for visibility.
server_versions_code="$(http_code "${BASE_URL}/_matrix/server/versions")"
if [ "$server_versions_code" = "200" ]; then
    print_ok "Server versions endpoint is available (/_matrix/server/versions)"
else
    echo "[INFO] /_matrix/server/versions returned HTTP ${server_versions_code} (often expected on Synapse)"
fi

echo
echo "Smoke test results: ${pass_count} passed, ${fail_count} failed"

if [ "$fail_count" -gt 0 ]; then
    exit 1
fi

exit 0
