#!/bin/bash
source /etc/openvpn/utils.sh
# DEBUG in utils.sh can enable xtrace, which would expose credentials and PF data.
set +x
. /etc/transmission/environment-variables.sh
set +x

fail() { printf 'PIA port forwarding: %s\n' "$1" >&2; exit 1; }

# Supply secrets to curl through stdin, never process arguments.
curl_quote() {
  [[ $1 != *[$'\r\n']* ]] || return 1
  local value=${1//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

pia_request() {
  local url=$1 auth=${2-} token=${3-} payload=${4-} signature=${5-}
  local a t p s
  local curl_opts=()
  if [[ -z $auth ]]; then
    curl_opts+=(--cacert "$pia_ca" --connect-to "$pf_hostname::$pf_host:")
  fi
  a=$(curl_quote "$auth") || return 1
  t=$(curl_quote "$token") || return 1
  p=$(curl_quote "$payload") || return 1
  s=$(curl_quote "$signature") || return 1
  {
    if [[ -n $auth ]]; then
      printf 'request = "POST"\nuser = "%s"\n' "$a"
    else
      printf 'get\n'
      if [[ -n $token ]]; then
        printf 'data-urlencode = "token=%s"\n' "$t"
      else
        printf 'data-urlencode = "payload=%s"\ndata-urlencode = "signature=%s"\n' "$p" "$s"
      fi
    fi
  } | curl --config - "${curl_opts[@]}" --silent --fail --connect-timeout 10 --max-time 15 \
      --retry 5 --retry-delay 15 --retry-max-time 120 "$url" 2>/dev/null
}

transmission_credentials_file=/config/transmission-credentials.txt
[[ -r $transmission_credentials_file ]] || fail 'Transmission credentials unavailable'
transmission_username=$(head -n 1 "$transmission_credentials_file") || fail 'Transmission credentials unavailable'
transmission_passwd=$(tail -n 1 "$transmission_credentials_file") || fail 'Transmission credentials unavailable'
transmission_settings_file=${TRANSMISSION_HOME}/settings.json
if [[ -z ${TRANSMISSION_RPC_URL:-} ]]; then
  TRANSMISSION_RPC_URL=$(jq -er '."rpc-url" | select(type == "string" and length > 0)' \
    /etc/transmission/default-settings.json 2>/dev/null) || fail 'RPC URL unavailable'
fi
TRANSMISSION_HOST="http://localhost:${TRANSMISSION_RPC_PORT}${TRANSMISSION_RPC_URL%/}"
sleep 5
[[ -r /config/openvpn-credentials.txt ]] || fail 'PIA credentials unavailable'
user=$(sed -n '1p' /config/openvpn-credentials.txt) || fail 'PIA credentials unavailable'
pass=$(sed -n '2p' /config/openvpn-credentials.txt) || fail 'PIA credentials unavailable'
[[ -n $user && -n $pass ]] || fail 'PIA credentials unavailable'
pf_host=$(ip route 2>/dev/null | awk '/tun/ && !/src/ {print $3; exit}')
[[ -n $pf_host ]] || fail 'PIA gateway unavailable'
pia_ca=/etc/openvpn/pia-ca.rsa.4096.crt
[[ -r $pia_ca ]] || fail 'PIA CA unavailable'
pf_hostname=${TRANSMISSION_PIA_PF_HOSTNAME:-}
[[ $pf_hostname =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || fail 'PIA PF hostname unavailable or invalid'

get_auth_token() {
  local response
  response=$(pia_request 'https://www.privateinternetaccess.com/gtoken/generateToken' "$user:$pass") \
    || fail 'token request failed'
  tok=$(jq -er '.token | select(type == "string" and length > 0)' <<< "$response" 2>/dev/null) \
    || fail 'token response invalid'
}

get_sig() {
  local response decoded
  response=$(pia_request "https://$pf_hostname:19999/getSignature" '' "$tok") \
    || fail 'getSignature request failed'
  [[ $(jq -er '.status | select(. == "OK")' <<< "$response" 2>/dev/null) == OK ]] \
    || fail 'getSignature response invalid'
  pf_payload=$(jq -er '.payload | select(type == "string" and length > 0)' <<< "$response" 2>/dev/null) \
    || fail 'getSignature payload missing'
  pf_getsignature=$(jq -er '.signature | select(type == "string" and length > 0)' <<< "$response" 2>/dev/null) \
    || fail 'getSignature signature missing'
  decoded=$(base64 -d <<< "$pf_payload" 2>/dev/null) || fail 'getSignature payload invalid'
  pf_port=$(jq -er '.port | select(type == "number" and . == floor and . >= 1 and . <= 65535)' \
    <<< "$decoded" 2>/dev/null) || fail 'getSignature port invalid'
  pf_token_expiry_raw=$(jq -er '.expires_at | select(type == "string" and length > 0)' \
    <<< "$decoded" 2>/dev/null) || fail 'getSignature expiration invalid'
  pf_token_expiry=$(date --date="$pf_token_expiry_raw" +%s 2>/dev/null) \
    || fail 'getSignature expiration invalid'
  [[ $pf_token_expiry =~ ^[0-9]+$ ]] || fail 'getSignature expiration invalid'
}

bind_port() {
  local response
  response=$(pia_request "https://$pf_hostname:19999/bindPort" '' '' "$pf_payload" "$pf_getsignature") \
    || fail 'bindPort request failed'
  [[ $(jq -er '.status | select(. == "OK")' <<< "$response" 2>/dev/null) == OK ]] \
    || fail 'bindPort response invalid'
  printf 'Reserved Port: %s %s\n' "$pf_port" "$(date)"
}

remote() {
  timeout 15s transmission-remote "$TRANSMISSION_HOST" "${auth_args[@]}" "$@" 2>/dev/null
}

bind_trans() {
  local attempt info current_port auth_setting
  auth_setting=$(jq -er '."rpc-authentication-required" | select(type == "boolean") | tostring' \
    "$transmission_settings_file" 2>/dev/null) || fail 'Transmission authentication setting invalid'
  auth_args=()
  if [[ $auth_setting == true ]]; then
    export TR_AUTH="$transmission_username:$transmission_passwd"
    auth_args=(--authenv)
  fi
  printf 'Waiting for Transmission to become responsive\n'
  for ((attempt = 1; attempt <= 12; attempt++)); do
    if remote -l >/dev/null; then break; fi
    (( attempt < 12 )) || fail 'Transmission readiness timed out'
    sleep 10
  done
  printf 'Transmission became responsive\n'
  info=$(remote -si) || fail 'Transmission session read failed'
  [[ $info =~ Listen[[:space:]]*port:[[:space:]]*([0-9]+) ]] || fail 'Transmission listening port invalid'
  current_port=${BASH_REMATCH[1]}
  ((current_port >= 1 && current_port <= 65535)) || fail 'Transmission listening port invalid'
  if [[ $pf_port != "$current_port" ]]; then
    if [[ ${ENABLE_UFW:-false} == true ]]; then
      ufw deny "$current_port" >/dev/null 2>&1 || fail 'UFW deny failed'
      ufw allow "$pf_port" >/dev/null 2>&1 || fail 'UFW allow failed'
    fi
    remote -p "$pf_port" >/dev/null || fail 'Transmission port update failed'
    sleep 10
    remote -pt >/dev/null || fail 'Transmission port test failed'
  fi
}

printf 'Running PIA token based port forwarding\n'
get_auth_token
get_sig
bind_port
bind_trans
format_expiry=$(date -d "@$pf_token_expiry" 2>/dev/null) || fail 'Expiration formatting failed'
printf 'Port: %s\nExpiration: %s\nEvery 15 minutes, check port status\n' "$pf_port" "$format_expiry"
pf_minreuse=$((60 * 60 * 24 * 7))
while true; do
  now=$(date +%s) || fail 'Clock unavailable'
  pf_remaining=$((pf_token_expiry - now))
  if ((pf_remaining < pf_minreuse)); then
    printf 'Port reservation nearing expiration; requesting a new one\n'
    get_auth_token
    get_sig
    bind_port
    bind_trans
  fi
  sleep 900 &
  wait $! || fail 'Port rebind timer failed'
  bind_port
done
