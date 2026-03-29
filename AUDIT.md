# pdfsign — Security Audit

Date: 2026-03-29

## Network operations

**NONE.** Целият pipeline е офлайн. Никъде не се отваря socket.

Единствено `go.sh:19` прави `pip install` при липсващи deps — supply chain risk при untrusted мрежа.

## PIN handling

| File | Line | Operation | Risk |
|------|------|-----------|------|
| pdfsign.py | 24 | `getpass.getpass("PIN: ")` | OK — не се показва |
| pdfsign.py | 25 | `token.open(user_pin=pin)` | PIN в PKCS#11 session |
| pdfsign.py | 39 | `session.close()` | PIN остава в паметта до GC |

PIN **не** се логва, **не** се записва, **не** се предава по мрежа.
Python strings са immutable — PIN не може да се занули. Нисък риск за CLI tool.

## File I/O

| File | Line | Operation |
|------|------|-----------|
| pdfsign.py | 29 | `open(input, 'rb')` — чете PDF |
| pdfsign.py | 36 | `open(output, 'wb')` — пише signed PDF |
| stamp.py | 56 | `PdfReader(input)` — чете PDF |
| stamp.py | 76 | `open(output, 'wb')` — пише stamped PDF |
| infopage.py | 41 | `open(path, 'rb')` — SHA-256 hash |
| infopage.py | 49 | `subprocess: pdfinfo` — external command |
| infopage.py | 166 | `PdfReader(input)` — чете PDF |
| infopage.py | 183 | `open(output, 'wb')` — пише PDF |
| go.sh | 32 | `rm -f` intermediate files |

## Info disclosure в PDF

infopage.py вгражда в подписания PDF:
- Line 131: `input_path` — пълен път на файла
- Line 135: `os.getcwd()` — текуща директория
- Line 138: `os.uname().nodename` — hostname

Нисък риск, но изтича filesystem layout при изпращане на трети лица.

## Shell injection

**check.sh:12** — `$INPUT` се интерполира директно в Python string:
```python
with open('$INPUT','rb') as f:
```
Filename с `'` може да изпълни произволен код. Да се замени с `sys.argv`.

## Hardcoded paths

| File | Line | Path |
|------|------|------|
| pdfsign.py | 11 | `/usr/lib64/pkcs11/onepin-opensc-pkcs11.so` |

## Certificates / Keys

Никъде не се записват private keys или сертификати.
PKCS#11 session достъпва smart card-а — private key никога не напуска картата.

## Summary

| Severity | Issue |
|----------|-------|
| MEDIUM | check.sh:12 — shell injection via filename |
| LOW | infopage.py — hostname/path в output PDF |
| LOW | pdfsign.py:24 — PIN в паметта до GC |
| LOW | go.sh:19 — pip install без pinned versions |

**No external network connections. No PIN/key leaks.**
