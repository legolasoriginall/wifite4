# wifite4

مجموعه‌ای از اسکریپت‌های نصب و اجرا برای زنجیره‌ی تست نفوذ وای‌فای روی لینوکس، حول ابزار `autopwn-ng`.

> ⚠️ **فقط روی شبکه‌های خودت یا شبکه‌هایی که اجازه‌ی کتبی برای تستشان داری.** تست نفوذ وای‌فای بدون مجوز در بیشتر کشورها جرم است. مسئولیت استفاده با خودت است.

---

## ساختار مخزن

| مسیر | توضیح |
|---|---|
| [`autopwn-ng.sh`](autopwn-ng.sh) | خودِ ابزار: زنجیره‌ی کامل برداشت → کرک → evil twin → post-exploit و تولید گزارش |
| [`setup.sh`](setup.sh) | نصب خودکار همه‌ی مراحل به ترتیب، با بررسی پیش‌نیازها (root، اینترنت، `git`/`wget`، فضای دیسک، اینترفیس وای‌فای). گزینه‌های `--quick` (بدون وردلیست‌ها) و `--only-autopwn` (فقط autopwn-ng) |
| [`uninstall.sh`](uninstall.sh) | حذف کامل: binaries، directories، rules |
| [`install/01-install-packages.sh`](install/01-install-packages.sh) | نصب بسته‌های پایه: `aircrack-ng`، `hcxtools`، `hcxdumptool`، `hashcat`، `reaver`، `mdk4`، `bettercap`، `iw`، `xxd`، `jq`، `bully`، `tshark`، `dnsmasq`، `nmap` (`wash` با `reaver`، `kismet` اختیاری) |
| [`install/02-build-hostapd-mana.sh`](install/02-build-hostapd-mana.sh) | نصب پیش‌نیازهای کامپایل و ساخت `hostapd-mana` و نصب آن در `/usr/local/bin` |
| [`install/03-download-wordlists.sh`](install/03-download-wordlists.sh) | دانلود `rockyou`، `SecLists`، `Probable-Wordlists`، ruleهای تهاجمی در `/opt/wordlists` |
| [`examples/run-autopwn-ng.sh`](examples/run-autopwn-ng.sh) | نمونه‌ی فراخوانی‌ها: پیش‌فرض، `stealth`، `brute`، هدف مشخص، بدون فازهای بلند |

---

## پیش‌نیازها

- لینوکس با `apt` (کالی، پارروت، اوبونتو و مشابه)
- `sudo` / دسترسی root
- **دو** دانگل وای‌فای برای فاز evil twin (یکی برای مانیتور مود، یکی برای AP قلابی)؛ با یک دانگل هم اجرا می‌شود ولی twin خودکار غیرفعال می‌شود
- فضای کافی برای وردلیست‌ها (چند صد مگابایت)

## نصب

یک دستور، همه‌ی مراحل به ترتیب:

```bash
sudo bash setup.sh                  # نصب کامل (پیش‌فرض، شامل وردلیست‌ها)
    sudo bash setup.sh --quick          # بدون مرحله‌ی دانلود وردلیست‌ها
  sudo bash setup.sh --only-autopwn   # فقط نصب مجدد autopwn-ng (بدون بسته‌ها/وردلیست)
  bash setup.sh --dry-run             # فقط بررسی پیش‌نیازها و نمایش مراحل، بدون تغییر سیستم
bash setup.sh --help                # راهنما
```

  `setup.sh` پیش از هر کاری root، وجود `apt-get`، دسترسی به اینترنت، `git`/`wget`/`curl`، فضای دیسک و تعداد اینترفیس‌های وای‌فای را بررسی می‌کند، ابزارهای پایه‌ی جاافتاده را نصب می‌کند و در صورت شکست هر مرحله متوقف می‌شود. گزارش اجرا در `/var/log/wifite4-setup.log` ذخیره می‌شود.
  - فراخوانی‌های `apt-get` با `-o APT::Sandbox::User=root` انجام می‌شوند تا در کانتینرها و user namespaceهای محدود (بدون امتیاز) نیز کار کنند.

اجرای مرحله‌به‌مرحله (اگر ترتیب دستی می‌خواهی):

```bash
sudo bash install/01-install-packages.sh
sudo bash install/02-build-hostapd-mana.sh
sudo bash install/03-download-wordlists.sh
sudo bash install-autopwn-ng.sh
```

## چک‌لیست ترتیب اجرای اسکریپت‌ها

<|start|> فایل | توضیح |
|------|--------|
| [`setup.sh`](setup.sh) | نصب خودکار (کامل یا سریع با `--quick`، یا فقط autopwn-ng با `--only-autopwn`) + بررسی پیش‌نیازها |
| [`uninstall.sh`](uninstall.sh) | حذف کامل: binaries + directories + rules |
| [`install-autopwn-ng.sh`](install-autopwn-ng.sh) | نصب autopwn-ng در /usr/local/bin (اعتبارسنجی منبع، `bash -n`) — گزینه‌های `--dry-run` / `--help` |

### روش ۱: نصب خودکار (توصیه‌شده)

```bash
# ۱. بررسی پیش‌نیازها + نصب همه‌چیز به ترتیب (شامل وردلیست‌ها)
sudo bash setup.sh

# ۲. (اختیاری) فقط بررسی بدون تغییر
bash setup.sh --dry-run

# ۳. (اختیاری) نصب سریع بدون دانلود وردلیست‌ها
sudo bash setup.sh --quick
```

### روش ۲: اجرای مرحله‌به‌مرحله (دستی)

```bash
# مرحله ۱ — بسته‌های پایه (aircrack-ng, hashcat, hcxtools, ...)
sudo bash install/01-install-packages.sh

# مرحله ۲ — ساخت و نصب hostapd-mana
sudo bash install/02-build-hostapd-mana.sh

# مرحله ۳ — دانلود وردلیست‌ها و ruleها
sudo bash install/03-download-wordlists.sh

# مرحله ۴ — نصب autopwn-ng در /usr/local/bin
sudo bash install-autopwn-ng.sh
# بررسی بدون تغییر / راهنما:
bash install-autopwn-ng.sh --dry-run
bash install-autopwn-ng.sh --help
```

### روش ۳: اجرای autopwn-ng

```bash
# پس از نصب کامل:
sudo autopwn-ng --help                  # راهنما
sudo autopwn-ng -i wlan1 -I wlan2       # اجرای کامل
sudo autopwn-ng --dry-run               # شبیه‌سازی بدون ابزار
sudo autopwn-ng --simulate              # همان --dry-run
sudo autopwn-ng --doctor                # بررسی سلامت: وابستگی‌ها، GPU/OpenCL، رابط‌ها، وردلیست‌ها
sudo autopwn-ng --color                 # اجبار رنگ حتی در پایپ/لاگ (برای less -R)
sudo autopwn-ng --no-color              # خروجی ساده بدون رنگ (یا متغیر NO_COLOR=1)
sudo autopwn-ng --interactive           # اسکن کوتاه + انتخاب هدف با شماره (مثل wifite2)
sudo autopwn-ng --auto                 # یک کلیک: اسکن + برداشت از همه + کرک + گزارش
  sudo autopwn-ng --pmkid-only           # برداشت کوتاه PMKID (۱۵s)؛ در صورت یافتن مستقیم به کرک
     sudo autopwn-ng --scope scope.txt --authorize   # محدود به scope + اجازهٔ صریح
   sudo autopwn-ng --allow-all --authorize          # همهٔ شبکه‌ها (نیازمند --allow-all یا تأیید تعاملی)
  sudo autopwn-ng --from-pcap FILE.pcap # حالت offline/crack-only: استخراج + کرک روی pcap موجود (بدون رادیو)
  sudo autopwn-ng --resume  # ادامه از checkpoint؛ session/workload/profile ذخیره‌شده بازیابی می‌شوند
sudo autopwn-ng --session myrun --restore  # از سرگیری کرک قطع‌شده (hashcat session)
  sudo autopwn-ng --auto  # انتخاب خودکار قوی‌ترین شبکهٔ WPA2 + برداشت + کرک + گزارش
  sudo autopwn-ng --wep  # کرک شبکه‌های WEP (ARP replay / chopchop / fragmentation)
  sudo autopwn-ng --no-config-extract  # غیرفعال‌کردن استخراج پیکربندی محلی
  sudo autopwn-ng --compute-wps-pins C8:3A:35:00:B0:0C  # تولید PINهای WPS شناخته‌شده از BSSID
  # پایگاه دادهٔ PINهای شناخته‌شده: wps-pins.db (OUI -> PIN)، قابل گسترش

```

### روش ۴: حذف (uninstall)

```bash
# حذف کامل (autopwn-ng + hostapd-mana + وردلیست‌ها)
sudo bash uninstall.sh

# حفظ وردلیست‌ها
sudo bash uninstall.sh --keep-wordlists

# پیش‌نمایش حذف
bash uninstall.sh --dry-run
```

### نکات مهم

- **ترتیب نصب مهم است**: بسته‌ها → hostapd-mana → وردلیست‌ها → autopwn-ng
- **rerun امن**: همه‌ی اسکریپت‌ها idempotent هستند — اگر نصب نیمه‌کاره ماند، `sudo bash setup.sh` را دوباره اجرا کنید
- **بدون root**: فقط `--dry-run` و `--help` بدون root کار می‌کنند
- **دو دانگل**: برای فاز evil twin به دو اینترفیس نیاز است؛ با یکی هم کار می‌کند ولی twin غیرفعال می‌شود

---

## استفاده

```bash
sudo autopwn-ng -i wlan1 -I wlan2                 # پیش‌فرض، همه‌ی فازها
sudo autopwn-ng -i wlan1 -p stealth               # برداشت طولانی‌تر، MAC رندوم
sudo autopwn-ng -i wlan1 -I wlan2 -p brute        # تهاجمی، workload بالا
sudo autopwn-ng -i wlan1 --target AA:BB:CC:DD:EE:FF
sudo autopwn-ng --no-twin --no-post -t 90
sudo autopwn-ng --help
```

### گزینه‌ها

| گزینه | توضیح | پیش‌فرض |
|---|---|---|
| `-p` | پروفایل: `stealth` \| `normal` \| `brute` | `normal` |
| `-t` | مدت برداشت به ثانیه | `120` |
| `-i` | اینترفیس اصلی (مانیتور مود) | اولین اینترفیس وای‌فای |
| `-I` | اینترفیس دوم برای evil twin | دومین اینترفیس |
| `-w` | فایل وردلیست اضافی | — |
| `-d` | پوشه‌ی دیکشنری‌ها | `/opt/wordlists` |
| `--target` | BSSID هدف | — |
| `--no-wps` | رد کردن فاز WPS | — |
| `--no-twin` | رد کردن فاز evil twin | — |
| `--no-post` | رد کردن فاز post-exploit | — |

خروجی‌ها و گزارش هر اجرا در یک پوشه‌ی موقت `/tmp/autopwn.XXXXXX/report/` ساخته می‌شود (`summary.md` و `summary.json`).

## فازهای اجرا

0. **آماده‌سازی** — انتخاب اینترفیس‌ها، تشخیص GPU برای hashcat، مانیتور مود، رندوم کردن MAC در حالت `stealth`
1. **برداشت** — `hcxdumptool` برای PMKID/EAPOL/EAP، `mdk4` برای دِاوث، `airodump-ng` برای اسکن موازی
2. **نرمال‌سازی** — `hcxpcapngtool` و `hcxhashtool` برای استخراج و حذف تکراری هش‌ها
3. **کرک** — لایه‌لایه با hashcat: دیکشنری مشتق از SSID، `rockyou`، ruleها، ماسک عددی/موبایل ایرانی، هیبرید، و MSCHAPv2 برای Enterprise
4. **WPS** — Pixie Dust با `reaver` + brute-force با `bully` + اسکن با `wash`
5. **Evil Twin** — `hostapd-mana` (یا `wifiphisher`) و جمع‌آوری اعتبارنامه
6. **Post-exploit** — ساخت اسکریپت اتصال به شبکه کرک‌شده + MITM با `bettercap` + اسکن با `nmap`
7. **تحلیل بسته‌ها** — `tshark` برای شناسایی Enterprise/WPS/کلاینت‌ها
8. **شناسایی منفعل** — `kismet` برای کشف شبکه‌های پنهان و کلاینت‌ها

## نکات شناخته‌شده

- `-h/--help` با `sed -n '2,8p'` سرصفحه‌ی فایل را چاپ می‌کند، پس با تغییر هدر اسکریپت راهنما هم تغییر می‌کند.
- فاز evil twin ۱۸۰ ثانیه منتظر قربانی می‌ماند؛ در محیط شلوغ ممکن است کافی نباشد.

## سلب مسئولیت

این ابزار برای تست نفوذ مجاز و آموزش ساخته شده است. استفاده‌ی آن روی شبکه‌هایی که مالکشان نیستی یا اجازه نداری، نقض قوانین است.

## --dry-run و --simulate

هر دو گزینه `--dry-run` و `--simulate` اسکریپت `autopwn-ng.sh` را در حالت شبیه‌سازی (بدون دست‌زدن به رادیو و بدون اجرای ابزارها) اجرا می‌کنند. خروجی هر دو یکسان است و اسکریپت با کد خروج `0` پایان می‌یابد.

```bash
sudo autopwn-ng --dry-run
sudo autopwn-ng --simulate
```

### خروجی نمونه

```text
SIMULATION MODE: autopwn-ng dry-run / --simulate

Profile: normal
Capture: 120s
Workload: 3

═══════════════════════════════════════════════════
  Planned execution (no tools will run)
═══════════════════════════════════════════════════

[0] Setup
    airmon-ng check kill
    airmon-ng start $IFACE

[1] Capture (120s)
    hcxdumptool -i $MON -o $CAP [filterlist_ap=$TARGET]
    mdk4 $MON d -b $WORK/blacklist  (background, every 5s)
    airodump-ng --band abg --output-format csv -w $WORK/scan $MON
    tshark -r $CAP -Y 'eap' -T fields -e wlan.sa -e eap.identity
    tshark -r $CAP -Y 'wps' -T fields -e wlan.bssid

[2] Extract & normalize
    hcxpcapngtool -o $WORK/raw.hc22000 -E $WORK/essids.txt --eapmschapv2=$WORK/mschapv2.txt $CAP
    hcxhashtool -i $WORK/raw.hc22000 -o $HASH --essid-group

[3] Crack (hashcat layers 1-8)
    1: hashcat -m 22000 -a 0 $HASH $WORK/dicts/vendor.txt
    ...

[4] WPS (if DO_WPS and WPS-enabled APs found)
    wash -i $MON -o $WORK/wps-scan.txt
    reaver -i $MON -b <bssid> -c <ch> -K 1 -N -vv -d 5
    bully -b <bssid> -c <ch> -d $WORK/bully-<bssid> $MON

[5] Evil Twin (if no cracks and DO_TWIN)
    hostapd-mana $WORK/mana.conf  (or wifiphisher)
    sleep 180

[6] Post-exploit (if cracks found and DO_POST)
    nmap -sn 192.168.1.0/24
    nmap -sV -p 22,80,443,445,3389,8080 192.168.1.0/24
    generate $REPORT/connect.sh (nmcli + bettercap)

[7] Report
    $REPORT/summary.md
    $REPORT/summary.json

✓ Simulation complete. No changes were made.
```

### ویژگی‌ها

- **بدون تغییر روی سیستم**: هیچ ابزار وای‌فای اجرا نمی‌شود، اینترفیس‌ها تغییر حالت نمی‌دهند و فایلی ساخته/تغییر نمی‌شود.
- **نمایش برنامهٔ اجرا**: پروفایل انتخاب‌شده، زمان برداشت و فازهای برنامه‌ریزی‌شده (همه به‌صورت `echo only`) چاپ می‌شوند.
- **مناسب برای تست**: امکان بررسی جریان اجرا و آرگومان‌ها بدون نیاز به دانگل وای‌فای یا دسترسی سخت‌افزاری.

## --resume

گزینه `--resume` اجرای قبلی را از آخرین فاز تکمیل‌شده ادامه می‌دهد. پس از هر فاز موفق، یک فایل checkpoint در `/tmp/autopwn-ng.checkpoint` ذخیره می‌شود که شامل مسیر دایرکتوری کار، شمارهٔ آخرین فاز تکمیل‌شده و مقادیر hashcat است: `SESSION`، `WLIMIT` و `PROFILE`.

هنگام resume، فایل بدون `source` خوانده و اعتبارسنجی می‌شود (فاز عددی، دایرکتوری کار موجود و متعلق به همان کاربر، session/profile با کاراکترهای مجاز، workload بین ۱ تا ۴). مقادیر ذخیره‌شده بر `--session`/`-p` خط فرمان اولویت دارند و در صورت اختلاف، هشدار داده می‌شود.

```bash
sudo autopwn-ng --resume
```

- اگر فایل checkpoint وجود نداشته باشد یا دایرکتوری کار حذف شده باشد، از ابتدا شروع می‌شود.
- می‌توان با `--dry-run` ترکیب کرد: `sudo autopwn-ng --resume --dry-run`

### تفاوت `--dry-run` و `--simulate`

از نظر رفتار تفاوتی ندارند؛ هر دو پرچم `DRY_RUN=1` را تنظیم می‌کنند و پس از چاپ خلاصهٔ شبیه‌سازی خارج می‌شوند. `--dry-run` نام رایج در ابزارهاست و `--simulate` همان مفهوم را با تأکید بر شبیه‌سازی بیان می‌کند.
```

## حالت یک کلیک (`--auto`)

پرچم `--auto` کل زنجیره را بدون نیاز به آرگومان اضافی اجرا می‌کند: اسکن شبکه‌ها، برداشت از همهٔ شبکه‌ها (بدون فیلتر هدف)، کرک و تولید گزارش — همه با یک دستور.

```bash
sudo autopwn-ng --auto
```

### ویژگی‌ها

- **بدون پیکربندی**: پروفایل normal، زمان برداشت ۹۰ ثانیه، تمام فازها (WPS، Evil Twin، Post-exploit) فعال.
- **بدون انتخاب هدف**: برداشت از تمام شبکه‌های WPA2/WPA3 در محدوده؛ هر هشی که یافت شود کرک می‌شود.
- **گزارش خودکار**: نتایج در `$WORK/report/summary.md` و `summary.json` ذخیره می‌شوند.
- **مناسب برای شروع سریع**: بدون نیاز به دانش قبلی از آرگومان‌ها.

### تفاوت با اجرای دستی

| ویژگی | اجرای دستی | `--auto` |
|-------|-----------|----------|
| پروفایل | قابل انتخاب (stealth/normal/brute) | normal ثابت |
| زمان برداشت | قابل تنظیم (`-t`) | ۹۰ ثانیه |
| انتخاب هدف | دستی (`--target`) | همهٔ شبکه‌ها |
| فازها | قابل غیرفعال‌سازی (`--no-*`) | همه فعال |

---
