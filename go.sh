#!/bin/bash
# Usage: ./go.sh input.pdf
# Pipeline: input.pdf → stamp → info page → sign → output
INPUT="$1"
if [ -z "$INPUT" ]; then
    echo "Usage: $0 <input.pdf>"
    exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMPED="${INPUT%.pdf}_stamped.pdf"
INFOED="${INPUT%.pdf}_info.pdf"
SIGNED="${INPUT%.pdf}_signed.pdf"

source ~/venv/pdfsign/bin/activate

# Check deps
python3 -c "import fpdf, PyPDF2, pyhanko, pkcs11" 2>/dev/null || {
    echo "Installing dependencies..."
    pip install -q fpdf2 PyPDF2 pyhanko[pkcs11]
}

echo "=== Step 1: Visual stamp ==="
python3 "$SCRIPT_DIR/stamp.py" "$INPUT" "$STAMPED" || exit 1

echo "=== Step 2: Info page ==="
python3 "$SCRIPT_DIR/infopage.py" "$STAMPED" "$INFOED" || { rm -f "$STAMPED"; exit 1; }

echo "=== Step 3: Crypto sign ==="
python3 "$SCRIPT_DIR/pdfsign.py" "$INFOED" "$SIGNED" || { rm -f "$STAMPED" "$INFOED"; exit 1; }

# Cleanup intermediate
rm -f "$STAMPED" "$INFOED"

deactivate
echo "=== Done: $SIGNED ==="
