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
  if [[ $TEST_CASE == rebind_success ]]; then
    count=$(cat "$MOCK_SLEEP_COUNT")
    printf '%s\n' "$((count + 1))" > "$MOCK_SLEEP_COUNT"
    ((count == 0)) && exit 0
  fi
  /bin/sleep 60
fi
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
case " $* " in
  *generateToken*)
    [[ " $* " != *' --insecure '* ]] || argument_error
    [[ " $* " != *' --connect-to '* && " $* " != *' --cacert '* ]] || argument_error
    assert_config "$(printf 'request = "POST"\nuser = "fake-pia-user:fake-pia-password"')"
    [[ $TEST_CASE == token_http ]] && exit 22
    [[ $TEST_CASE == token_json ]] && { printf '{invalid'; exit 0; }
    printf '{"token":"fake-token-value"}'
    ;;
  *getSignature*)
    [[ " $* " != *' --insecure '* ]] || argument_error
    [[ " $* " == *' --cacert '"$PIA_CA"' '* ]] || argument_error
    [[ " $* " == *' --connect-to amsterdam429::10.0.0.1: '* ]] || argument_error
    [[ " $* " == *' https://amsterdam429:19999/getSignature '* ]] || argument_error
    assert_config "$(printf 'get\ndata-urlencode = "token=fake-token-value"')"
    [[ $TEST_CASE == signature_tls ]] && exit 60
    [[ $TEST_CASE == signature_http ]] && exit 7
    [[ $TEST_CASE == signature_status ]] && { printf '{"status":"ERROR","payload":"fake-payload-value"}'; exit 0; }
    [[ $TEST_CASE == signature_missing ]] && { printf '{"status":"OK","payload":"fake-payload-value"}'; exit 0; }
    payload=$(printf '{"port":51414,"expires_at":"2099-01-01T00:00:00Z"}' | base64 -w0)
    [[ $TEST_CASE == port_invalid ]] && payload=$(printf '{"port":70000,"expires_at":"2099-01-01T00:00:00Z"}' | base64 -w0)
    [[ $TEST_CASE == expiry_invalid ]] && payload=$(printf '{"port":51414,"expires_at":"invalid"}' | base64 -w0)
    printf '{"status":"OK","payload":"%s","signature":"fake-signature-value"}' "$payload"
    ;;
  *bindPort*)
    [[ " $* " != *' --insecure '* ]] || argument_error
    [[ " $* " == *' --cacert '"$PIA_CA"' '* ]] || argument_error
    [[ " $* " == *' --connect-to amsterdam429::10.0.0.1: '* ]] || argument_error
    [[ " $* " == *' https://amsterdam429:19999/bindPort '* ]] || argument_error
    expected_payload=$(printf '{"port":51414,"expires_at":"2099-01-01T00:00:00Z"}' | base64 -w0)
    assert_config "$(printf 'get\ndata-urlencode = "payload=%s"\ndata-urlencode = "signature=fake-signature-value"' "$expected_payload")"
    count=$(cat "$MOCK_BIND_COUNT")
    printf '%s\n' "$((count + 1))" > "$MOCK_BIND_COUNT"
    [[ $TEST_CASE == bind_tls ]] && exit 60
    [[ $TEST_CASE == bind_http ]] && exit 7
    [[ $TEST_CASE == bind_status ]] && { printf '{"status":"ERROR"}'; exit 0; }
    [[ $TEST_CASE == rebind_status && $count -ge 1 ]] && { printf '{"status":"ERROR"}'; exit 0; }
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
    printf 'private-torrent-name\n'
    ;;
  *' -si '*)
    [[ $TEST_CASE == rpc_read ]] && exit 1
    if [[ $TEST_CASE == rpc_listen_space ]]; then
      printf 'Listen port: 51413\n'
    else
      printf 'Listenport: 51413\n'
    fi
    ;;
  *' -p 51414 '*)
    [[ $TEST_CASE == rpc_write ]] && exit 1
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
export TRANSMISSION_PIA_PF_HOSTNAME=amsterdam429 PIA_CA="$repo_root/openvpn/pia-ca.rsa.4096.crt"
passed=0
run_case() {
  local scenario=$1 expected=$2 status=0 hostname=$TRANSMISSION_PIA_PF_HOSTNAME
  [[ $scenario != hostname_missing ]] || hostname=
  : > "$MOCK_ARGS"
  : > "$MOCK_RPC_CALLS"
  rm -f "$MOCK_ASSERT_FAIL"
  printf '0\n' > "$MOCK_BIND_COUNT"
  printf '0\n' > "$MOCK_SLEEP_COUNT"
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
    fi
  else
    [[ $status != 0 && $status != 124 ]] || { printf '%s: unexpected status %s\n' "$scenario" "$status" >&2; exit 1; }
    grep -q 'Port: 51414' "$tmp/output"
  fi
  if grep -Eq 'fake-(pia|rpc|token|payload|signature)|private-torrent-name' "$tmp/output" "$MOCK_ARGS"; then
    printf '%s: secret or torrent name leaked\n' "$scenario" >&2
    exit 1
  fi
  ((passed += 1))
}

run_case success success
run_case rpc_auth_disabled success
run_case rpc_listen_space success
run_case hostname_missing failure
for scenario in token_http token_json signature_http signature_tls signature_status signature_missing \
  port_invalid expiry_invalid bind_http bind_tls bind_status readiness rpc_read rpc_write rpc_test; do
  run_case "$scenario" failure
done
run_case rebind_status rebind_failure
run_case rebind_success success
printf '%s mock cases passed\n' "$passed"
