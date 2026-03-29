#!/usr/bin/env python3
"""PDF signing with B-Trust smart card via PKCS#11 — invisible crypto signature"""

import sys
import getpass
import pkcs11
from pyhanko.sign.pkcs11 import PKCS11Signer
from pyhanko.sign import signers
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter

PKCS11_LIB = "/usr/lib64/pkcs11/onepin-opensc-pkcs11.so"

def sign_pdf(input_path, output_path, slot=0):
    lib = pkcs11.lib(PKCS11_LIB)
    slots = lib.get_slots(token_present=True)

    if not slots:
        print("No smart card found!")
        sys.exit(1)

    token = slots[slot].get_token()
    print(f"Token: {token.label} (slot {slot})")

    pin = getpass.getpass("PIN: ")
    session = token.open(user_pin=pin)

    signer = PKCS11Signer(session)

    with open(input_path, 'rb') as inf:
        w = IncrementalPdfFileWriter(inf)
        out = signers.sign_pdf(
            w,
            signers.PdfSignatureMetadata(field_name='Signature1'),
            signer=signer,
        )
        with open(output_path, 'wb') as outf:
            outf.write(out.getbuffer())

    session.close()
    print(f"Signed: {output_path}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.pdf> [output.pdf]")
        sys.exit(1)

    inp = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else inp.replace('.pdf', '_signed.pdf')
    sign_pdf(inp, out)
