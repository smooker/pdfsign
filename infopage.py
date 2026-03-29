#!/usr/bin/env python3
"""
infopage.py — Add info page with document metadata + signer info

Usage: python3 infopage.py input.pdf [output.pdf]

Adds a final page with:
- Original document metadata (pdfinfo)
- Signer certificate info
- SHA-256 hash of original file
- Timestamp
"""

import sys
import os
import hashlib
import datetime
import subprocess
from io import BytesIO
from fpdf import FPDF
from PyPDF2 import PdfReader, PdfWriter


def ascii_safe(text):
    """Replace non-latin1 chars with ?"""
    return text.encode('latin-1', errors='replace').decode('latin-1')

# Configure these for your certificate
SIGNER_NAME = os.environ.get("PDFSIGN_NAME", "YOUR NAME HERE")
SIGNER_EGN = os.environ.get("PDFSIGN_EGN", "PNOBG-0000000000")
SIGNER_EMAIL = os.environ.get("PDFSIGN_EMAIL", "user@example.com")
ISSUER = os.environ.get("PDFSIGN_ISSUER", "B-Trust Operational Qualified CA")
ISSUER_ORG = os.environ.get("PDFSIGN_ISSUER_ORG", "BORICA AD")
CERT_SN_DEC = os.environ.get("PDFSIGN_CERT_SN_DEC", "0")
CERT_SN_HEX = os.environ.get("PDFSIGN_CERT_SN_HEX", "00")
CERT_VALID = "2024-08-29 - 2027-08-29"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()


def get_pdfinfo(path):
    try:
        out = subprocess.check_output(['pdfinfo', path], stderr=subprocess.DEVNULL)
        return out.decode('utf-8', errors='replace').strip()
    except Exception:
        return "(pdfinfo not available)"


def create_info_page(input_path, w_mm, h_mm):
    pdf = FPDF(unit='mm', format=(w_mm, h_mm))
    pdf.set_auto_page_break(False)
    pdf.add_page()

    now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    file_hash = sha256_file(input_path)
    pdfinfo = get_pdfinfo(input_path)

    # Title
    pdf.set_font('Helvetica', 'B', 14)
    pdf.set_xy(20, 15)
    pdf.cell(w_mm - 40, 8, 'Electronic Signature - Document Info', align='C')

    # Divider
    pdf.set_draw_color(0, 0, 0)
    pdf.line(20, 26, w_mm - 20, 26)

    y = 32

    # Signer section
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_xy(20, y)
    pdf.cell(0, 6, 'Signer')
    y += 8

    pdf.set_font('Courier', '', 8)
    signer_lines = [
        f"Name:    {SIGNER_NAME}",
        f"ID:      {SIGNER_EGN}",
        f"Email:   {SIGNER_EMAIL}",
    ]
    for line in signer_lines:
        pdf.set_xy(25, y)
        pdf.cell(0, 5, line)
        y += 5

    y += 4

    # Certificate section
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_xy(20, y)
    pdf.cell(0, 6, 'Certificate')
    y += 8

    pdf.set_font('Courier', '', 8)
    cert_lines = [
        f"Issuer:  {ISSUER}",
        f"Org:     {ISSUER_ORG}",
        f"SN dec:  {CERT_SN_DEC}",
        f"SN hex:  {CERT_SN_HEX}",
        f"Valid:   {CERT_VALID}",
        f"Type:    Qualified Electronic Signature (QES)",
        f"Algo:    SHA-256 / RSA",
    ]
    for line in cert_lines:
        pdf.set_xy(25, y)
        pdf.cell(0, 5, line)
        y += 5

    y += 4

    # Document section
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_xy(20, y)
    pdf.cell(0, 6, 'Document')
    y += 8

    pdf.set_font('Courier', '', 8)
    pdf.set_xy(25, y)
    pdf.cell(0, 5, f"SHA-256: {file_hash}")
    y += 5
    pdf.set_xy(25, y)
    pdf.cell(0, 5, f"Signed:  {now}")
    y += 5
    pdf.set_xy(25, y)
    pdf.cell(0, 5, ascii_safe(f"File:    {input_path}"))
    y += 5

    pdf.set_xy(25, y)
    pdf.cell(0, 5, f"CWD:     {os.getcwd()}")
    y += 5
    pdf.set_xy(25, y)
    pdf.cell(0, 5, f"Host:    {os.uname().nodename}")
    y += 8

    # pdfinfo section
    pdf.set_font('Helvetica', 'B', 10)
    pdf.set_xy(20, y)
    pdf.cell(0, 6, 'Original PDF Metadata (pdfinfo)')
    y += 8

    pdf.set_font('Courier', '', 7)
    for line in pdfinfo.split('\n'):
        if y > h_mm - 20:
            break
        pdf.set_xy(25, y)
        pdf.cell(0, 4, ascii_safe(line[:100]))
        y += 4

    # Footer
    pdf.set_font('Helvetica', 'I', 6)
    pdf.set_xy(20, h_mm - 12)
    pdf.cell(w_mm - 40, 4,
             'This page was generated automatically by pdfsign and is part of the signed document.',
             align='C')

    return pdf.output()


def add_info_page(input_path, output_path):
    reader = PdfReader(input_path)
    writer = PdfWriter()

    # Copy all original pages
    for page in reader.pages:
        writer.add_page(page)

    # Get page size from first page
    box = reader.pages[0].mediabox
    w_mm = float(box.width) * 0.3528
    h_mm = float(box.height) * 0.3528

    # Create and append info page
    info_bytes = create_info_page(input_path, w_mm, h_mm)
    info_reader = PdfReader(BytesIO(info_bytes))
    writer.add_page(info_reader.pages[0])

    with open(output_path, 'wb') as f:
        writer.write(f)

    print(f"Info page added: {output_path} ({len(reader.pages)+1} pages)")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.pdf> [output.pdf]")
        sys.exit(1)

    inp = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else inp.replace('.pdf', '_info.pdf')
    add_info_page(inp, out)
