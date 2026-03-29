# pdfsign — PDF signing with B-Trust e-signature

CLI подписване на PDF с B-Trust smart card (Gemalto) под Linux.
Визуален банер + info page + криптографски подпис.

## Процедура за e-подписване на документ

### 1. Подготовка на документа
- Създай/редактирай документа (LibreOffice, scan, etc.)
- Експортирай като PDF
- Прегледай внимателно — след подписване НЕ може да се променя!

### 2. Свържи smart card четеца
```bash
rc-service pcscd start         # ако не е стартиран
p11-kit list-modules           # провери дали вижда картата
```

### 3. Подпиши
```bash
cd ~/work/pdfsign
./go.sh /path/to/document.pdf
# Step 1: stamp — черна лента горе на всяка страница
# Step 2: info page — последна страница с metadata
# Step 3: crypto sign — иска PIN от smart card
```

### 4. Провери (ЗАДЪЛЖИТЕЛНО!)
```bash
./check.sh /path/to/document_signed.pdf
```
Очакван изход:
```
Field:  Signature1
Signer: ... YOUR NAME ...
Issuer: ... B-Trust Operational Qualified CA ...
Valid:  2024-08-29 ... - 2027-08-29 ...
```

Допълнително:
```bash
/usr/bin/pdfsig /path/to/document_signed.pdf
# Signature Validation: Signature is Valid.
# Certificate Validation: Certificate is Trusted.
```

### 5. Готово
- Подписаният PDF е правно валиден (QES = саморъчен подпис по закон)
- Изпрати по email, принтирай
- EU валидация: https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/validation

## Setup
```bash
python3 -m venv ~/venv/pdfsign
source ~/venv/pdfsign/bin/activate
pip install pyhanko[pkcs11] fpdf2 PyPDF2 img2pdf
```

## Pipeline
```
input.pdf
    |
    v
stamp.py — черна лента (5mm) горе на всяка страница
    |       Helvetica Bold 6pt, бял текст:
    |       "e-sign (pdfsign) by NAME | ISSUER | SN: hex | datetime"
    v
infopage.py — добавя последна страница с:
    |       - Signer (name, ID, email)
    |       - Certificate (issuer, SN dec/hex, validity, algo)
    |       - Document (SHA-256 hash, timestamp, filepath, CWD, hostname)
    |       - Original PDF metadata (pdfinfo output)
    v
pdfsign.py — невидим криптографски подпис (SHA-256 + PKCS#11 + B-Trust QES)
    |       Подписва ЦЕЛИЯ документ включително stamp и info page
    v
check.sh — верификация на подписа (ВИНАГИ преди изпращане!)
    |
    v
output_signed.pdf — готов за изпращане/публикуване
```

## Подписване на сканиран саморъчно подписан документ
Когато имаш хартиен документ с мокър подпис:
```
1. Подпиши на хартия с химикалка
2. Сканирай → scan.pdf
3. ./go.sh scan.pdf → scan_signed.pdf (e-подпис върху сканирания)
4. ./check.sh scan_signed.pdf
```
Резултат: документ с ДВА подписа — саморъчен (в скана) + електронен (QES).
Двойна защита: визуално доказателство + криптографска гаранция.

## Сканиране на хартиен документ
```bash
# Провери скенер
scanimage -L

# Сканирай (600 DPI, цветно)
scanimage -d "genesys:libusb:001:124" --resolution 600 --mode Color --format=png -o scan.png

# Конвертирай в JPG (по-малък файл)
convert scan.png -quality 85 scan.jpg

# PNG/JPG → PDF (A4)
img2pdf --pagesize A4 scan.jpg -o scan.pdf

# Ако е обърнат:
convert scan.png -rotate 180 -quality 85 scan_rotated.jpg
img2pdf --pagesize A4 scan_rotated.jpg -o scan.pdf

# Подпиши
./go.sh scan.pdf
./check.sh scan_signed.pdf
```

## Smart Card
- **Token**: YOUR NAME
- **Chip**: Gemalto
- **Serial**: (your card serial)
- **PKCS#11**: `/usr/lib64/pkcs11/onepin-opensc-pkcs11.so` (OpenSC)
- **pcscd**: `rc-service pcscd start`

## Certificate
- **Issuer**: B-Trust Operational Qualified CA (BORICA AD)
- **SN dec**: (your cert serial)
- **SN hex**: (your cert serial hex)
- **Valid**: (your cert validity)
- **Type**: Qualified Electronic Signature (QES)
- **Algo**: SHA-256 / RSA

## Files
| File | Description |
|------|-------------|
| `go.sh` | Full pipeline — deps check + stamp + info + sign |
| `stamp.py` | Visual banner on every page (black bar, white text) |
| `infopage.py` | Info page with metadata, cert info, SHA-256 hash |
| `pdfsign.py` | Invisible crypto signing via PKCS#11 + pyhanko |
| `check.sh` | Verify signature — ЗАДЪЛЖИТЕЛЕН преди изпращане! |

## Защо stamp → sign (не обратното)

Adobe Reader показва визуализация на подписа чрез JS/annotations **след** подписването:
- Документът се променя визуално след подписа
- Хешът не покрива тази промяна
- Получателят вижда нещо **различно** от подписаното
- JavaScript в PDF = attack vector

Нашият подход: stamp е **вътре** в подписания документ. Подписът покрива целия
документ включително визуалния stamp и info page-а. Без JS, без annotations,
без рендериране — чиста математика.

`pdfsig` казва `Signature is Valid` и `Total document signed`. Край.

## Ограничения
- Кирилица в info page filename/pdfinfo се показва като `?` (core PDF fonts = Latin-1 only)

## TODO
- [ ] Unicode font (DejaVuSans) за кирилица в info page
- [ ] Анализ на документа — маркиране на проблеми в червено (последна страница)
- [ ] Конфигурируем signer (за други сертификати)
- [ ] Batch signing (множество PDF-и)
- [ ] Публикуване на подписани документи
- [ ] Anti-copy protection: микротекст/watermark зад SN — деформира се при копиране/scan

## SECURITY AUDIT

**See [AUDIT.md](AUDIT.md) for full security analysis.**

## Dependencies
- `pcscd` + OpenSC (`emerge sys-apps/pcsc-lite app-crypt/opensc`)
- `app-text/poppler` (USE=nss) — pdfsig верификация
- `media-gfx/sane-backends` (genesys backend) — скенер
- `media-gfx/imagemagick` — convert за rotate/resize
- Python venv `~/venv/pdfsign/`: `pyhanko[pkcs11]`, `fpdf2`, `PyPDF2`, `img2pdf`
- Smart card reader + B-Trust card
- Scanner: Canon CanoScan LiDE 100 (GL847, genesys backend)
