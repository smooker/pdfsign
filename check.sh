#!/bin/bash
# Verify PDF signature
INPUT="$1"
if [ -z "$INPUT" ]; then
    echo "Usage: $0 <signed.pdf>"
    exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source ~/venv/pdfsign/bin/activate
python3 -c "
from pyhanko.pdf_utils.reader import PdfFileReader
with open('$INPUT','rb') as f:
    r = PdfFileReader(f)
    sigs = list(r.embedded_signatures)
    if not sigs:
        print('No signatures found!')
    for s in sigs:
        print(f'Field:  {s.field_name}')
        print(f'Signer: {s.signer_cert.subject.human_friendly}')
        print(f'Issuer: {s.signer_cert.issuer.human_friendly}')
        sn = s.signer_cert.serial_number
        print(f'Serial: 0x{sn:X} ({sn})')
        print(f'Valid:  {s.signer_cert.not_valid_before} — {s.signer_cert.not_valid_after}')
print()
print('EU Validator: https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/validation')
"
