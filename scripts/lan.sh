#!/usr/bin/env bash
# The local shop on the current Wi-Fi over HTTPS, so a phone can install it and get web push.
#
# A CA of its own signs a certificate for this Mac's LAN address and .local name. The CA is name
# constrained to private addresses and that name: installed on a phone, it cannot vouch for any
# other site, even if its key leaked. The key stays in ~/.config/nothingeats/lan, never in a repo.
set -euo pipefail

dir="${NOTHINGEATS_LAN_DIR:-$HOME/.config/nothingeats/lan}"
https_port="${LAN_HTTPS_PORT:-8443}"
http_port="${LAN_HTTP_PORT:-8080}"
ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
name="$(scutil --get LocalHostName).local"
if [ -z "$ip" ]; then
    echo "No Wi-Fi address found (en0/en1)." >&2
    exit 1
fi

mkdir -p "$dir"
chmod 700 "$dir"
openssl=/usr/bin/openssl

if [ ! -f "$dir/ca.key" ]; then
    cat > "$dir/ca.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = NothingEats LAN CA ($name)
[ca]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
nameConstraints = critical, permitted;DNS:$name, permitted;IP:10.0.0.0/255.0.0.0, permitted;IP:172.16.0.0/255.240.0.0, permitted;IP:192.168.0.0/255.255.0.0
CNF
    "$openssl" ecparam -name prime256v1 -genkey -noout -out "$dir/ca.key"
    chmod 600 "$dir/ca.key"
    "$openssl" req -x509 -new -key "$dir/ca.key" -sha256 -days 825 -config "$dir/ca.cnf" -extensions ca -out "$dir/ca.crt"
    echo "Created a new LAN CA. Install it on the phone (see below) before opening the shop."
fi

# The server certificate is cheap: a new one on every start, for the address the Mac has now.
cat > "$dir/server.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $name
[server]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:$name, IP:$ip
CNF
"$openssl" ecparam -name prime256v1 -genkey -noout -out "$dir/server.key"
chmod 600 "$dir/server.key"
"$openssl" req -new -key "$dir/server.key" -config "$dir/server.cnf" -out "$dir/server.csr"
# 397 days: Apple refuses server certificates that live longer.
"$openssl" x509 -req -in "$dir/server.csr" -CA "$dir/ca.crt" -CAkey "$dir/ca.key" -CAcreateserial \
    -days 397 -sha256 -extfile "$dir/server.cnf" -extensions server -out "$dir/server.crt" 2>/dev/null
"$openssl" verify -CAfile "$dir/ca.crt" "$dir/server.crt" > /dev/null

cat <<MSG

  Shop on the Wi-Fi:  https://$ip:$https_port   (also https://$name:$https_port)
  CA for the phone:   http://$ip:$http_port/nothingeats-lan-ca.crt

  iPhone:  open the CA link in Safari, allow the profile; Settings > General > VPN & Device
           Management > install it; Settings > General > About > Certificate Trust Settings >
           switch it on. Then open the shop in Safari, Share > Add to Home Screen, and switch
           push on in the installed app (/account).
  Android: open the CA link in Chrome, then Settings > Security > Encryption & credentials >
           Install a certificate > CA certificate. Open the shop in Chrome.

  Remove the CA from the phone when you are done. Anyone on this Wi-Fi reaches the shop while
  this runs; Ctrl-C stops it.

MSG

export LAN_DIR="$dir" LAN_IP="$ip" LAN_NAME="$name" LAN_HTTPS_PORT="$https_port" LAN_HTTP_PORT="$http_port"
exec caddy run --config "$(dirname "$0")/../lan/Caddyfile" --adapter caddyfile
