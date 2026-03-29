# pdfsign — Security Audit

Last updated: 2026-03-29

## Network operations

**NONE.** The entire pipeline is offline. No sockets are opened.

Only `go.sh` runs `pip install` on missing deps — supply chain risk on untrusted networks.

## PIN handling

| File | Line | Operation | Risk |
|------|------|-----------|------|
| pdfsign.py | 24 | `getpass.getpass("PIN: ")` | OK — not displayed |
| pdfsign.py | 25 | `token.open(user_pin=pin)` | PIN in PKCS#11 session |
| pdfsign.py | 39 | `session.close()` | PIN stays in memory until GC |
| go.sh | cert read | `read -s CARD_PIN` | OK — not echoed |
| go.sh | cert read | `--pin "$CARD_PIN"` | PIN on command line — visible in /proc |

PIN is **not** logged, **not** saved to disk, **not** sent over network.
Python strings are immutable — PIN cannot be zeroed. Low risk for CLI tool.

**go.sh PIN exposure:** When public cert read fails, go.sh passes PIN via `--pin` to `pkcs11-tool`. This is visible in `/proc/PID/cmdline` to same-user processes. Low risk on single-user workstation. Alternative: use `PKCS11_PIN` env var or pipe.

## File I/O

| File | Line | Operation |
|------|------|-----------|
| pdfsign.py | 29 | `open(input, 'rb')` — reads PDF |
| pdfsign.py | 36 | `open(output, 'wb')` — writes signed PDF |
| stamp.py | 56 | `PdfReader(input)` — reads PDF |
| stamp.py | 76 | `open(output, 'wb')` — writes stamped PDF |
| stamp.py | 21-23 | Reads env vars `PDFSIGN_NAME`, `PDFSIGN_ISSUER`, `PDFSIGN_CERT_SN` |
| infopage.py | 41 | `open(path, 'rb')` — SHA-256 hash |
| infopage.py | 49 | `subprocess: pdfinfo` — external command |
| infopage.py | 166 | `PdfReader(input)` — reads PDF |
| infopage.py | 183 | `open(output, 'wb')` — writes PDF |
| go.sh | cleanup | `rm -f` intermediate files |

## go.sh — certificate reading

go.sh reads certificates from the smart card to populate stamp.py env vars:
- Lists all cert objects via `pkcs11-tool --list-objects --type cert`
- Reads each cert DER via `pkcs11-tool --read-object --type cert --id XX`
- Parses CN, Issuer O, Serial via `openssl x509`
- Exports as `PDFSIGN_NAME`, `PDFSIGN_ISSUER`, `PDFSIGN_CERT_SN`
- If multiple certs found: interactive selection prompt
- If public read fails: prompts for PIN and retries with `--login`

Certificate data (public) is exported to env vars visible to child processes only.

## Info disclosure in output PDF

infopage.py embeds in the signed PDF:
- `input_path` — full file path
- `os.getcwd()` — current directory
- `os.uname().nodename` — hostname

Low risk, but leaks filesystem layout when sending to third parties.

## Shell injection

**check.sh:12** — `$INPUT` is interpolated directly in Python string:
```python
with open('$INPUT','rb') as f:
```
Filename with `'` can execute arbitrary code. Should use `sys.argv` instead.

## Hardcoded paths

| File | Line | Path |
|------|------|------|
| pdfsign.py | 11 | `/usr/lib64/pkcs11/onepin-opensc-pkcs11.so` |
| go.sh | 15 | `/usr/lib64/opensc-pkcs11.so` |

## Certificates / Keys

No private keys or certificates are saved to disk.
PKCS#11 session accesses the smart card — private key never leaves the card.
Public certificate data is read for stamp display only.

## Summary

| Severity | Issue |
|----------|-------|
| MEDIUM | check.sh:12 — shell injection via filename |
| LOW | go.sh — PIN on command line (visible in /proc) |
| LOW | infopage.py — hostname/path in output PDF |
| LOW | pdfsign.py:24 — PIN in memory until GC |
| LOW | go.sh — pip install without pinned versions |

**No external network connections. No PIN/key leaks to disk or network.**
