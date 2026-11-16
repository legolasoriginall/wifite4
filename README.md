# wifite4

مجموعه‌ای از اسکریپت‌های نصب و اجرا برای زنجیره‌ی تست نفوذ وای‌فای روی لینوکس، حول ابزار `autopwn-ng`.

> ⚠️ **فقط روی شبکه‌های خودت یا شبکه‌هایی که اجازه‌ی کتبی برای تستشان داری.** تست نفوذ وای‌فای بدون مجوز در بیشتر کشورها جرم است. مسئولیت استفاده با خودت است.

---

## ساختار مخزن

| مسیر | توضیح |
|---|---|
| [`autopwn-ng.sh`](autopwn-ng.sh) | خودِ ابزار: زنجیره‌ی کامل برداشت → کرک → evil twin → post-exploit و تولید گزارش |
| [`setup.sh`](setup.sh) | نصب خودکار همه‌ی مراحل به ترتیب، با بررسی پیش‌نیازها (root، اینترنت، `git`/`wget`، فضای دیسک، اینترفیس وای‌فای) |
| [`install-all.sh`](install-all.sh) | نصب سریع: بسته‌ها + hostapd-mana + autopwn-ng + chmod +x (بدون وردلیست‌ها) |
| [`uninstall.sh`](uninstall.sh) | حذف کامل: binaries، directories، rules |
| [`install/01-install-packages.sh`](install/01-install-packages.sh) | نصب بسته‌های پایه: `aircrack-ng`، `hcxtools`، `hcxdumptool`، `hashcat`، `reaver`، `mdk4`، `bettercap`، `iw`، `pocl-opencl-icd`، `xxd`، `jq` |
| [`install/02-build-hostapd-mana.sh`](install/02-build-hostapd-mana.sh) | نصب پیش‌نیازهای کامپایل و ساخت `hostapd-mana` و نصب آن در `/usr/local/bin` |
| [`install/03-download-wordlists.sh`](install/03-download-wordlists.sh) | دانلود `rockyou`، `SecLists`، `Probable-Wordlists`، ruleهای تهاجمی و ساخت `kwp` در `/opt/wordlists` |
| [`install/04-install-autopwn-ng.sh`](install/04-install-autopwn-ng.sh) | نصب `autopwn-ng` در `/usr/local/bin/autopwn-ng` با مجوز اجرا (`755`) و بررسی سینتکس پیش از نصب |
| [`install-autopwn-ng.sh`](install-autopwn-ng.sh) | نصب مستقل `autopwn-ng` با `chmod +x` در مسیر سیستم (جایگزین مرحله‌ی nano) |
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
sudo bash setup.sh                  # نصب کامل، شامل دانلود وردلیست‌ها
sudo bash setup.sh --no-wordlists   # بدون مرحله‌ی دانلود وردلیست‌ها
bash setup.sh --dry-run             # فقط بررسی پیش‌نیازها و نمایش مراحل، بدون تغییر سیستم
bash setup.sh --help                # راهنما
```

`setup.sh` پیش از هر کاری root، وجود `apt-get`، دسترسی به اینترنت، `git`/`wget`/`curl`، فضای دیسک و تعداد اینترفیس‌های وای‌فای را بررسی می‌کند، ابزارهای پایه‌ی جاافتاده را نصب می‌کند و در صورت شکست هر مرحله متوقف می‌شود. گزارش اجرا در `/var/log/wifite4-setup.log` ذخیره می‌شود.

اجرای مرحله‌به‌مرحله (اگر ترتیب دستی می‌خواهی):

```bash
sudo bash install/01-install-packages.sh
sudo bash install/02-build-hostapd-mana.sh
sudo bash install/03-download-wordlists.sh
sudo bash install/04-install-autopwn-ng.sh
```

## چک‌لیست ترتیب اجرای اسکریپت‌ها

<|start|> فایل | توضیح |
|------|--------|
| [`install-all.sh`](install-all.sh) | نصب سریع: بسته‌ها + hostapd-mana + autopwn-ng + chmod +x (بدون وردلیست‌ها) |
| [`setup.sh`](setup.sh) | نصب کامل: همه مراحل + بررسی پیش‌نیازها + وردلیست‌ها |
| [`uninstall.sh`](uninstall.sh) | حذف کامل: binaries + directories + rules |

### روش ۱: نصب خودکار (توصیه‌شده)

```bash
# ۱. بررسی پیش‌نیازها + نصب همه‌چیز به ترتیب
sudo bash setup.sh

# ۲. (اختیاری) فقط بررسی بدون تغییر
bash setup.sh --dry-run

# ۳. (اختیاری) بدون دانلود وردلیست‌ها
sudo bash setup.sh --no-wordlists
```

### روش ۲: اجرای مرحله‌به‌مرحله (دستی)

```bash
# مرحله ۱ — بسته‌های پایه (aircrack-ng, hashcat, hcxtools, ...)
sudo bash install/01-install-packages.sh

# مرحله ۲ — ساخت و نصب hostapd-mana
sudo bash install/02-build-hostapd-mana.sh

# مرحله ۳ — دانلود وردلیست‌ها و ساخت kwp
sudo bash install/03-download-wordlists.sh

# مرحله ۴ — نصب autopwn-ng در /usr/local/bin
sudo bash install/04-install-autopwn-ng.sh
```

### روش ۳: اجرای autopwn-ng

```bash
# پس از نصب کامل:
sudo autopwn-ng --help                  # راهنما
sudo autopwn-ng -i wlan1 -I wlan2       # اجرای کامل
sudo autopwn-ng --dry-run               # شبیه‌سازی بدون ابزار
sudo autopwn-ng --simulate              # همان --dry-run
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
3. **کرک** — لایه‌لایه با hashcat: دیکشنری مشتق از SSID، `rockyou`، ruleها، ماسک عددی/موبایل ایرانی، هیبرید، keyboard walk، و MSCHAPv2 برای Enterprise
4. **WPS** — Pixie Dust با `reaver`
5. **Evil Twin** — `hostapd-mana` (یا `wifiphisher`) و جمع‌آوری اعتبارنامه
6. **Post-exploit** — ساخت اسکریپت اتصال به شبکه کرک‌شده + MITM با `bettercap`

## نکات شناخته‌شده

- `-h/--help` با `sed -n '2,8p'` سرصفحه‌ی فایل را چاپ می‌کند، پس با تغییر هدر اسکریپت راهنما هم تغییر می‌کند.
- در انتخاب پروفایل، `CAPTURE=${CAPTURE:-240}` مقدار پیش‌فرض بالای فایل (`120`) را بازنویسی نمی‌کند؛ برای تغییر واقعی زمان برداشت از `-t` استفاده کن.
- استخراج رمز WPS با `grep -oP` انجام می‌شود و به `grep` با پشتیبانی PCRE نیاز دارد.
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

Phases (simulation only - no tools will run)
  [0] Setup: check root, prerequisites, wireless interfaces
  [1] Capture: hcxdumptool + mdk4 reassociation (echo only)
  [2] Extract: hcxpcapngtool + hcxhashtool (echo only)
  [3] Crack: hashcat layers 1-8 (dicts + masks + rules; echo only)
  [4] WPS: reaver -K Pixie Dust (if AP has WPS; echo only)
  [5] Evil Twin: hostapd-mana or wifiphisher (echo only)

✓ Simulation complete. No changes were made.
```

### ویژگی‌ها

- **بدون تغییر روی سیستم**: هیچ ابزار وای‌فای اجرا نمی‌شود، اینترفیس‌ها تغییر حالت نمی‌دهند و فایلی ساخته/تغییر نمی‌شود.
- **نمایش برنامهٔ اجرا**: پروفایل انتخاب‌شده، زمان برداشت و فازهای برنامه‌ریزی‌شده (همه به‌صورت `echo only`) چاپ می‌شوند.
- **مناسب برای تست**: امکان بررسی جریان اجرا و آرگومان‌ها بدون نیاز به دانگل وای‌فای یا دسترسی سخت‌افزاری.

### تفاوت `--dry-run` و `--simulate`

از نظر رفتار تفاوتی ندارند؛ هر دو پرچم `DRY_RUN=1` را تنظیم می‌کنند و پس از چاپ خلاصهٔ شبیه‌سازی خارج می‌شوند. `--dry-run` نام رایج در ابزارهاست و `--simulate` همان مفهوم را با تأکید بر شبیه‌سازی بیان می‌کند.
```

---
