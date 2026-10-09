#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
printf 'set -x\n' > "$tmp/utils.sh"
printf 'TRANSMISSION_HOME=%s/home\nTRANSMISSION_RPC_PORT=9091\nTRANSMISSION_RPC_URL=/transmission/rpc\n' "$tmp" > "$tmp/environment.sh"
printf 'fake-rpc-user\nfake-rpc-password\n' > "$tmp/transmission-credentials.txt"
printf 'fake-pia-user\nfake-pia-password\n' > "$tmp/openvpn-credentials.txt"
printf '{"rpc-authentication-required":true}\n' > "$tmp/home/settings.json"
printf '{"rpc-url":"/transmission/rpc"}\n' > "$tmp/default-settings.json"

sed -e "s|/etc/openvpn/utils.sh|$tmp/utils.sh|" \
    -e "s|/etc/transmission/environment-variables.sh|$tmp/environment.sh|" \
    -e "s|/etc/transmission/default-settings.json|$tmp/default-settings.json|" \
    -e "s|/etc/openvpn/pia-ca.rsa.4096.crt|$repo_root/openvpn/pia-ca.rsa.4096.crt|" \
    -e "s|/config/transmission-credentials.txt|$tmp/transmission-credentials.txt|" \
    -e "s|/config/openvpn-credentials.txt|$tmp/openvpn-credentials.txt|" \
    "$repo_root/openvpn/pia/update-port.sh" > "$tmp/update-port.sh"

cat > "$tmp/bin/ip" <<'MOCK'
#!/bin/bash
printf '10.0.0.0/8 via 10.0.0.1 dev tun0\n'
MOCK
cat > "$tmp/bin/sleep" <<'MOCK'
#!/bin/bash
if [[ $1 == 900 ]]; then
  if [[ $TEST_CASE == rebind_status ]]; then exit 0; fi
  case $TEST_CASE in
    rebind_success|token_refresh_*|reservation_*)
    count=$(cat "$MOCK_SLEEP_COUNT")
    printf '%s\n' "$((count + 1))" > "$MOCK_SLEEP_COUNT"
    limit=1 delta=900
    case $TEST_CASE in
      token_refresh_boundary)
        limit=2
        if ((count == 0)); then delta=82799; else delta=1; fi ;;
      token_refresh_retry|token_refresh_invalid)
        limit=2
        ((count != 0)) || delta=82800 ;;
      token_refresh_auth) delta=82800 ;;
      token_refresh_request_delay) delta=82680 ;;
      token_refresh_expired|reservation_expired_token|reservation_refresh_failed) delta=86400 ;;
      reservation_*) delta=1800 ;;
    esac
    if ((count < limit)); then
      printf '%s\n' "$(($(cat "$MOCK_NOW") + delta))" > "$MOCK_NOW"
      exit 0
    fi
    ;;
  esac
  /bin/sleep 60
fi
MOCK
cat > "$tmp/bin/date" <<'MOCK'
#!/bin/bash
if [[ $* == '+%s' ]]; then cat "$MOCK_NOW"; else /bin/date "$@"; fi
MOCK
cat > "$tmp/bin/curl" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_ARGS"
config=$(cat)
assert_config() {
  if [[ $config != "$1" ]]; then
    printf 'curl config mismatch\n' > "$MOCK_ASSERT_FAIL"
    exit 97
  fi
}
argument_error() {
  printf 'curl arguments mismatch\n' > "$MOCK_ASSERT_FAIL"
  exit 98
}
[[ $config != *'fake-rpc-password'* ]] || { printf 'RPC password in curl config\n' > "$MOCK_ASSERT_FAIL"; exit 97; }
[[ " $* " == *' --disable --config - '* ]] || argument_error
[[ " $* " == *' --silent --fail --connect-timeout 10 --max-time 15 '* ]] || argument_error
[[ " $* " == *' --retry 5 --retry-delay 15 --retry-max-time 120 '* ]] || argument_error
case " $* " in
  *'/api/client/v2/token'*)
    [[ " $* " != *' --insecure '* ]] || argument_error
    [[ " $* " != *' --connect-to '* && " $* " != *' --cacert '* ]] || argument_error
    [[ " $* " == *' https://www.privateinternetaccess.com/api/client/v2/token '* ]] || argument_error
    assert_config "$(printf 'request = "POST"\ndata-urlencode = "username=fake-pia-user"\ndata-urlencode = "password=fake-pia-password"')"
    count=$(cat "$MOCK_TOKEN_COUNT")
    printf '%s\n' "$((count + 1))" > "$MOCK_TOKEN_COUNT"
    [[ $TEST_CASE != token_refresh_boundary || $count == 0 || $(cat "$MOCK_NOW") -ge 1700082800 ]] || argument_error
    [[ $TEST_CASE == token_http ]] && { printf '\n500'; exit 22; }
    [[ $TEST_CASE == token_auth_401 ]] && { printf '\n401'; exit 22; }
    [[ $TEST_CASE == token_auth_403 ]] && { printf '\n403'; exit 22; }
    [[ $TEST_CASE == token_tls ]] && { printf '\n000'; exit 60; }
    [[ $TEST_CASE == token_redirect ]] && { printf '{"token":"fake-token-value"}\n302'; exit 0; }
    [[ $TEST_CASE == token_refresh_retry && $count == 1 ]] && { printf '\n503'; exit 22; }
    [[ $TEST_CASE == token_refresh_invalid && $count == 1 ]] && { printf '{"token":null}\n200'; exit 0; }
    if [[ $TEST_CASE == token_refresh_request_delay && $count == 0 ]]; then
      printf '%s\n' "$(($(cat "$MOCK_NOW") + 120))" > "$MOCK_NOW"
    fi
    [[ $TEST_CASE == token_refresh_auth && $count -gt 0 ]] && { printf '\n401'; exit 22; }
    [[ $TEST_CASE == token_refresh_expired && $count -gt 0 ]] && { printf '\n503'; exit 22; }
    [[ $TEST_CASE == reservation_refresh_failed && $count -gt 0 ]] && { printf '\n503'; exit 22; }
    case $TEST_CASE in
      token_json) printf '{invalid\n200' ;;
      token_empty_body) printf '\n200' ;;
      token_missing) printf '{}\n200' ;;
      token_null) printf '{"token":null}\n200' ;;
      token_literal_null) printf '{"token":"null"}\n200' ;;
      token_empty) printf '{"token":""}\n200' ;;
      token_number) printf '{"token":123}\n200' ;;
      token_array) printf '[{"token":"fake-token-value"}]\n200' ;;
      token_whitespace) printf '{"token":" \\t"}\n200' ;;
      token_control) printf '{"token":"fake-token-value\\n"}\n200' ;;
      token_status) printf '{"status":"ERROR","token":"fake-token-value"}\n200' ;;
      token_error) printf '{"error":"fake-pia-password","token":"fake-token-value"}\n200' ;;
      token_multiple) printf '{"token":"fake-token-value"}\n{"token":"fake-token-value"}\n200' ;;
      *)
        token=fake-token-value
        if ((count > 0)); then token=fake-token-refreshed; fi
        printf '%s\n' "$token" > "$MOCK_ACTIVE_TOKEN"
        printf '{"token":"%s"}\n200' "$token"
        ;;
    esac
    ;;
  *getSignature*)
    [[ " $* " != *' --insecure '* ]] || argument_error
    [[ " $* " == *' --cacert '"$PIA_CA"' '* ]] || argument_error
    [[ " $* " == *' --connect-to amsterdam429::10.0.0.1: '* ]] || argument_error
    [[ " $* " == *' https://amsterdam429:19999/getSignature '* ]] || argument_error
    assert_config "$(printf 'get\ndata-urlencode = "token=%s"' "$(cat "$MOCK_ACTIVE_TOKEN")")"
    count=$(cat "$MOCK_SIG_COUNT")
    printf '%s\n' "$((count + 1))" > "$MOCK_SIG_COUNT"
    [[ $TEST_CASE == signature_tls ]] && exit 60
    [[ $TEST_CASE == signature_http ]] && exit 7
    [[ $TEST_CASE == signature_status ]] && { printf '{"status":"ERROR","payload":"fake-payload-value"}'; exit 0; }
    [[ $TEST_CASE == signature_missing ]] && { printf '{"status":"OK","payload":"fake-payload-value"}'; exit 0; }
    payload=$(printf '{"port":51414,"expires_at":"2099-01-01T00:00:00Z"}' | base64 -w0)
    if [[ $TEST_CASE == reservation_* ]]; then
      port=51414 expiry=$(/bin/date -u -d '@1700605700' '+%Y-%m-%dT%H:%M:%SZ')
      if ((count > 0)); then port=51415 expiry=2099-01-01T00:00:00Z; fi
      payload=$(printf '{"port":%s,"expires_at":"%s"}' "$port" "$expiry" | base64 -w0)
    fi
    [[ $TEST_CASE == port_invalid ]] && payload=$(printf '{"port":70000,"expires_at":"2099-01-01T00:00:00Z"}' | base64 -w0)
    [[ $TEST_CASE == expiry_invalid ]] && payload=$(printf '{"port":51414,"expires_at":"invalid"}' | base64 -w0)
    printf '%s\n' "$payload" > "$MOCK_PAYLOAD"
    printf '{"status":"OK","payload":"%s","signature":"fake-signature-value"}' "$payload"
    ;;
  *bindPort*)
    [[ " $* " != *' --insecure '* ]] || argument_error
    [[ " $* " == *' --cacert '"$PIA_CA"' '* ]] || argument_error
    [[ " $* " == *' --connect-to amsterdam429::10.0.0.1: '* ]] || argument_error
    [[ " $* " == *' https://amsterdam429:19999/bindPort '* ]] || argument_error
    expected_payload=$(cat "$MOCK_PAYLOAD")
    assert_config "$(printf 'get\ndata-urlencode = "payload=%s"\ndata-urlencode = "signature=fake-signature-value"' "$expected_payload")"
    count=$(cat "$MOCK_BIND_COUNT")
    printf '%s\n' "$((count + 1))" > "$MOCK_BIND_COUNT"
    [[ $TEST_CASE == bind_tls ]] && exit 60
    [[ $TEST_CASE == bind_http ]] && exit 7
    [[ $TEST_CASE == bind_status ]] && { printf '{"status":"ERROR"}'; exit 0; }
    [[ $TEST_CASE == rebind_status && $count -ge 1 ]] && { printf '{"status":"ERROR"}'; exit 0; }
    [[ $TEST_CASE == reservation_bind_fail && $count -ge 2 ]] && { printf '{"status":"ERROR"}'; exit 0; }
    printf '{"status":"OK"}'
    ;;
esac
MOCK
cat > "$tmp/bin/transmission-remote" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$MOCK_ARGS"
printf 'called\n' >> "$MOCK_RPC_CALLS"
if [[ $TEST_CASE == rpc_auth_disabled ]]; then
  [[ -z ${TR_AUTH:-} && " $* " != *' --authenv '* ]] || exit 99
else
  [[ ${TR_AUTH:-} == 'fake-rpc-user:fake-rpc-password' && " $* " == *' --authenv '* ]] || exit 99
fi
case " $* " in
  *' -l '*)
    [[ $TEST_CASE == readiness ]] && { printf 'private-torrent-name\n'; exit 1; }
    [[ $TEST_CASE == readiness_recovery && $(wc -l < "$MOCK_RPC_CALLS") -le 2 ]] && { printf 'private-torrent-name\n'; exit 1; }
    printf 'private-torrent-name\n'
    ;;
  *' -si '*)
    [[ $TEST_CASE == rpc_read ]] && exit 1
    if [[ $TEST_CASE == rpc_listen_space ]]; then
      printf 'Listen port: %s\n' "$(cat "$MOCK_RPC_PORT")"
    else
      printf 'Listenport: %s\n' "$(cat "$MOCK_RPC_PORT")"
    fi
    ;;
  *' -p '*)
    [[ $TEST_CASE == rpc_write ]] && exit 1
    printf '%s\n' "${@: -1}" > "$MOCK_RPC_PORT"
    exit 0
    ;;
  *' -pt '*)
    [[ $TEST_CASE == rpc_test ]] && exit 1
    exit 0
    ;;
esac
MOCK
chmod +x "$tmp/bin/"*

export PATH="$tmp/bin:$PATH" MOCK_ARGS="$tmp/args" MOCK_BIND_COUNT="$tmp/bind-count" MOCK_SLEEP_COUNT="$tmp/sleep-count" MOCK_ASSERT_FAIL="$tmp/assert-fail" MOCK_RPC_CALLS="$tmp/rpc-calls"
export MOCK_NOW="$tmp/now" MOCK_TOKEN_COUNT="$tmp/token-count" MOCK_SIG_COUNT="$tmp/sig-count" MOCK_ACTIVE_TOKEN="$tmp/active-token" MOCK_PAYLOAD="$tmp/payload" MOCK_RPC_PORT="$tmp/rpc-port"
export TRANSMISSION_PIA_PF_HOSTNAME=amsterdam429 PIA_CA="$repo_root/openvpn/pia-ca.rsa.4096.crt"
passed=0
run_case() {
  local scenario=$1 expected=$2 status=0 hostname=$TRANSMISSION_PIA_PF_HOSTNAME
  [[ $scenario != hostname_missing ]] || hostname=
  : > "$MOCK_ARGS"
  : > "$MOCK_RPC_CALLS"
  : > "$MOCK_PAYLOAD"
  rm -f "$MOCK_ASSERT_FAIL"
  printf '0\n' > "$MOCK_BIND_COUNT"
  printf '0\n' > "$MOCK_SLEEP_COUNT"
  printf '0\n' > "$MOCK_TOKEN_COUNT"
  printf '0\n' > "$MOCK_SIG_COUNT"
  printf '1700000000\n' > "$MOCK_NOW"
  printf '51413\n' > "$MOCK_RPC_PORT"
  [[ $scenario != rpc_same_port ]] || printf '51414\n' > "$MOCK_RPC_PORT"
  if [[ $scenario == rpc_auth_disabled ]]; then
    printf '{"rpc-authentication-required":false}\n' > "$tmp/home/settings.json"
  else
    printf '{"rpc-authentication-required":true}\n' > "$tmp/home/settings.json"
  fi
  TEST_CASE=$scenario TRANSMISSION_PIA_PF_HOSTNAME=$hostname DEBUG=true timeout 1s bash "$tmp/update-port.sh" > "$tmp/output" 2>&1 || status=$?
  if [[ -e $MOCK_ASSERT_FAIL ]]; then
    printf '%s: curl mock assertion failed\n' "$scenario" >&2
    exit 1
  fi
  if [[ $expected == success ]]; then
    [[ $status == 124 ]] || { printf '%s: unexpected status %s\n' "$scenario" "$status" >&2; cat "$tmp/output" "$MOCK_ARGS" >&2; exit 1; }
    grep -q 'Port: 51414' "$tmp/output"
    if [[ $scenario == rebind_success ]]; then
      [[ $(cat "$MOCK_BIND_COUNT") == 2 ]]
      [[ $(grep -c '^Reserved Port: 51414' "$tmp/output") == 2 ]]
    fi
  elif [[ $expected == failure ]]; then
    [[ $status != 0 && $status != 124 ]] || { printf '%s: unexpected status %s\n' "$scenario" "$status" >&2; exit 1; }
    ! grep -q 'Port: 51414' "$tmp/output"
    if [[ $scenario == signature_tls ]]; then
      grep -q 'getSignature request failed' "$tmp/output"
      ! grep -q 'bindPort' "$MOCK_ARGS"
      [[ ! -s $MOCK_RPC_CALLS ]]
    elif [[ $scenario == bind_tls ]]; then
      grep -q 'bindPort request failed' "$tmp/output"
      [[ ! -s $MOCK_RPC_CALLS ]]
    elif [[ $scenario == hostname_missing ]]; then
      grep -q 'PIA PF hostname unavailable or invalid' "$tmp/output"
      [[ ! -s $MOCK_ARGS ]]
    elif [[ $scenario == token_* ]]; then
      [[ $(cat "$MOCK_SIG_COUNT") == 0 && $(cat "$MOCK_BIND_COUNT") == 0 && ! -s $MOCK_RPC_CALLS ]]
      if [[ $scenario == token_auth_* ]]; then
        grep -q 'token authentication failed' "$tmp/output"
      fi
    fi
  else
    [[ $status != 0 && $status != 124 ]] || { printf '%s: unexpected status %s\n' "$scenario" "$status" >&2; exit 1; }
    grep -q 'Port: 51414' "$tmp/output"
  fi
  if grep -Eq 'fake-(pia|rpc|token|payload|signature)|private-torrent-name' "$tmp/output" "$MOCK_ARGS"; then
    printf '%s: secret or torrent name leaked\n' "$scenario" >&2
    exit 1
  fi
  if [[ -s $MOCK_PAYLOAD ]] && grep -Fq "$(cat "$MOCK_PAYLOAD")" "$tmp/output" "$MOCK_ARGS"; then
    printf '%s: PF payload leaked\n' "$scenario" >&2
    exit 1
  fi
  case $scenario in
    token_refresh_*)
      [[ $(cat "$MOCK_SIG_COUNT") == 1 && $(cat "$MOCK_RPC_PORT") == 51414 ]]
      [[ $(grep -c ' -p ' "$MOCK_ARGS") == 1 ]]
      [[ $(cat "$MOCK_BIND_COUNT") -ge 2 ]]
      if [[ $scenario == token_refresh_retry || $scenario == token_refresh_invalid ]]; then
        [[ $(cat "$MOCK_TOKEN_COUNT") == 3 ]]
        grep -q 'will retry token refresh' "$tmp/output"
        grep -q 'PIA authentication token refreshed' "$tmp/output"
      else
        [[ $(cat "$MOCK_TOKEN_COUNT") == 2 ]]
      fi
      ;;
    reservation_renewal|reservation_expired_token)
      [[ $(cat "$MOCK_SIG_COUNT") == 2 && $(cat "$MOCK_RPC_PORT") == 51415 ]]
      [[ $(grep -c ' -p ' "$MOCK_ARGS") == 2 ]]
      [[ $(cat "$MOCK_BIND_COUNT") == 3 ]]
      if [[ $scenario == reservation_renewal ]]; then
        [[ $(cat "$MOCK_TOKEN_COUNT") == 1 ]]
      else
        [[ $(cat "$MOCK_TOKEN_COUNT") == 2 ]]
      fi
      ;;
    reservation_refresh_failed)
      [[ $(cat "$MOCK_SIG_COUNT") == 1 && $(cat "$MOCK_RPC_PORT") == 51414 ]]
      ;;
    reservation_bind_fail)
      [[ $(cat "$MOCK_RPC_PORT") == 51414 ]]
      [[ $(grep -c ' -p ' "$MOCK_ARGS") == 1 ]]
      ;;
    rpc_same_port)
      ! grep -q ' -p ' "$MOCK_ARGS"
      ;;
    readiness_recovery)
      [[ $(grep -c ' -l$' "$MOCK_ARGS") == 3 ]]
      ;;
  esac
  ((passed += 1))
}

run_case success success
run_case rpc_auth_disabled success
run_case rpc_listen_space success
run_case rpc_same_port success
run_case readiness_recovery success
run_case hostname_missing failure
for scenario in token_http token_auth_401 token_auth_403 token_tls token_redirect token_json token_empty_body \
  token_missing token_null token_literal_null token_empty token_number token_array token_whitespace token_control \
  token_status token_error token_multiple signature_http signature_tls signature_status signature_missing \
  port_invalid expiry_invalid bind_http bind_tls bind_status readiness rpc_read rpc_write rpc_test; do
  run_case "$scenario" failure
done
run_case rebind_status rebind_failure
run_case rebind_success success
for scenario in token_refresh_boundary token_refresh_request_delay token_refresh_retry token_refresh_invalid token_refresh_auth token_refresh_expired \
  reservation_renewal reservation_expired_token; do
  run_case "$scenario" success
done
run_case reservation_refresh_failed rebind_failure
run_case reservation_bind_fail rebind_failure
printf '%s mock cases passed\n' "$passed"
