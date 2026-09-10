#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
V2RAY_AGENT_LIB_ONLY=true source "${repo_dir}/install.sh"
initVar ""

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"
}

tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

clients='[{"id":"00000000-0000-4000-8000-000000000001","email":"test"}]'
direct_config="${tmp_dir}/direct.json"
tunnel_config="${tmp_dir}/tunnel.json"
dual_config="${tmp_dir}/dual.json"

buildXrayXHTTPTLSConfig 11451 us02.1080999.xyz demo "${clients}" direct >"${direct_config}"
assert_eq "$(jq -r '.inbounds | length' "${direct_config}")" "1"
assert_eq "$(getXHTTPTLSListenPort "${direct_config}")" "11451"
assert_eq "$(getXHTTPTLSEntryMode "${direct_config}")" "direct"

buildXrayXHTTPTLSConfig 11451 us02.1080999.xyz demo "${clients}" direct h2,h3 >"${dual_config}"
assert_eq "$(jq -r '.inbounds | length' "${dual_config}")" "2"
assert_eq "$(jq -r '[.inbounds[].streamSettings.tlsSettings.alpn[0]] | sort | join(",")' "${dual_config}")" "h2,h3"

buildXrayXHTTPTLSConfig 11452 us02.1080999.xyz demo "${clients}" tunnel >"${tunnel_config}"
assert_eq "$(jq -r '.inbounds | length' "${tunnel_config}")" "2"
assert_eq "$(getXHTTPTLSListenPort "${tunnel_config}")" "11452"
assert_eq "$(getXHTTPTLSEntryMode "${tunnel_config}")" "tunnel"

isValidXHTTPTLSPort 1 || fail 'port 1 should be accepted'
isValidXHTTPTLSPort 65535 || fail 'port 65535 should be accepted'
if isValidXHTTPTLSPort 65536; then fail 'port 65536 should be rejected'; fi

xhttpTLSEndpointConfigFile="${tmp_dir}/xhttp_tls.json"
xhttpTLSEntryMode=direct
xHTTPTLSPort=11451
xhttpTLSAdvertiseAddress=us02.1080999.xyz
xhttpTLSAdvertisePort=11451
xhttpTLSALPN=h2,h3
writeXHTTPTLSEndpointSettings
assert_eq "$(jq -r '.entry_mode' "${xhttpTLSEndpointConfigFile}")" "direct"
assert_eq "$(listXHTTPTLSEndpoints 38.55.146.16 11451 '' | cut -f1-4)" $'us02.1080999.xyz\t11451\tauto\th2,h3'

jq '.endpoints += [{name:"split",address:"relay.example.com",port:8443,mode:"stream-up",alpn:"h3",sni:"origin.example.com",host:"origin.example.com",download_settings:{address:"cdn.example.com",port:443,network:"xhttp",security:"tls",tlsSettings:{serverName:"origin.example.com",alpn:["h2"]},xhttpSettings:{path:"/demoxHTTP",host:"origin.example.com"}}}]' \
    "${xhttpTLSEndpointConfigFile}" >"${tmp_dir}/with-endpoint.json"
mv "${tmp_dir}/with-endpoint.json" "${xhttpTLSEndpointConfigFile}"
custom_endpoint=$(listXHTTPTLSEndpoints 38.55.146.16 11451 '' | tail -1)
assert_eq "$(cut -f1-6 <<<"${custom_endpoint}")" $'relay.example.com\t8443\tstream-up\th3\torigin.example.com\torigin.example.com'
decoded_extra=$(cut -f7 <<<"${custom_endpoint}" | base64 -d)
assert_eq "$(jq -r '.downloadSettings.address' <<<"${decoded_extra}")" "cdn.example.com"

extra='{"downloadSettings":{"address":"cdn.example.com","port":443,"network":"xhttp","security":"tls","tlsSettings":{"serverName":"example.com"},"xhttpSettings":{"path":"/demo","host":"example.com"}}}'
uri=$(buildVLESSXHTTPTLSURI edge.example.com 443 '00000000-0000-4000-8000-000000000001' example.com demo stream-up test h2 example.com "${extra}")
[[ "${uri}" == *'mode=stream-up&extra='* ]] || fail 'split download settings missing from URI'

printf 'xhttp tls helper tests passed\n'
