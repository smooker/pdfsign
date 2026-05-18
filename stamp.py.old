#!/usr/bin/env python3
"""
stamp.py — Add visual e-signature banner to PDF (top black bar, white text)

Usage: python3 stamp.py input.pdf [output.pdf]

Adds a 5mm black bar at the top of every page with white proportional text:
"e-sign (pdfsign) by NAME | ISSUER | SN: hex | datetime"

Pipeline: input.pdf → stamp.py → stamped.pdf → pdfsign.py → signed.pdf
"""

import sys
import os
import datetime
from io import BytesIO
from fpdf import FPDF
from PyPDF2 import PdfReader, PdfWriter

# Configure these for your certificate (or set env vars)
SIGNER_NAME = os.environ.get("PDFSIGN_NAME", "YOUR NAME HERE")
ISSUER = os.environ.get("PDFSIGN_ISSUER", "B-Trust QES/BORICA AD")
CERT_SN = os.environ.get("PDFSIGN_CERT_SN", "0000000000000000")
BAR_HEIGHT_MM = 5.0


def create_banner_pdf(width_mm, height_mm):
    """Create a single-page PDF with black bar at top, white text."""
    pdf = FPDF(unit='mm', format=(width_mm, height_mm))
    pdf.set_auto_page_break(False)
    pdf.add_page()

    # Black bar at top
    pdf.set_fill_color(0, 0, 0)
    pdf.rect(0, 0, width_mm, BAR_HEIGHT_MM, 'F')

    # White text — proportional font (Times)
    pdf.set_text_color(255, 255, 255)
    pdf.set_font('Helvetica', 'B', 6)

    today = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    text = (
        f"e-sign (pdfsign) by {SIGNER_NAME}"
        f"  |  {ISSUER}"
        f"  |  SN: {CERT_SN}"
        f"  |  {today}"
    )

    pdf.set_xy(2, 0.3)
    pdf.cell(width_mm - 4, BAR_HEIGHT_MM - 0.5, text, align='L')

    return pdf.output()


def stamp_pdf(input_path, output_path):
    reader = PdfReader(input_path)
    writer = PdfWriter()

    for page in reader.pages:
        # Get page size (PDF points → mm)
        box = page.mediabox
        w_pt = float(box.width)
        h_pt = float(box.height)
        w_mm = w_pt * 0.3528
        h_mm = h_pt * 0.3528

        # Create banner overlay for this page size
        banner_bytes = create_banner_pdf(w_mm, h_mm)
        banner_reader = PdfReader(BytesIO(banner_bytes))
        banner_page = banner_reader.pages[0]

        # Merge banner on top of page content
        page.merge_page(banner_page)
        writer.add_page(page)

    with open(output_path, 'wb') as f:
        writer.write(f)

    print(f"Stamped: {output_path} ({len(reader.pages)} pages)")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.pdf> [output.pdf]")
        sys.exit(1)

    inp = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else inp.replace('.pdf', '_stamped.pdf')
    stamp_pdf(inp, out)
