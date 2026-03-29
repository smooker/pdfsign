#!/bin/bash
# Usage: ./go.sh input.pdf
# Pipeline: input.pdf → stamp → info page → sign → output
die() { echo "ERROR: $1" >&2; exit 1; }

INPUT="$1"
[ -z "$INPUT" ] && die "Usage: $0 <input.pdf>"
[ -f "$INPUT" ] || die "File not found: $INPUT"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMPED="${INPUT%.pdf}_stamped.pdf"
INFOED="${INPUT%.pdf}_info.pdf"
SIGNED="${INPUT%.pdf}_signed.pdf"
PKCS11_MODULE="/usr/lib64/opensc-pkcs11.so"

# --- Check: pcscd ---
pgrep -x pcscd >/dev/null 2>&1 || die "pcscd is not running! Start it: pcscd"

# --- Check: smart card ---
SLOT_INFO=$(pkcs11-tool --module "$PKCS11_MODULE" -L 2>&1)
if ! echo "$SLOT_INFO" | grep -q "token label"; then
    echo "$SLOT_INFO"
    die "No smart card detected! Insert card into reader."
fi
TOKEN=$(echo "$SLOT_INFO" | grep "token label" | head -1 | sed 's/.*token label.*: *//')
echo "Card: $TOKEN"

# --- List certificates on card ---
echo "Reading certificates from card..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

OBJ_LIST=$(pkcs11-tool --module "$PKCS11_MODULE" --list-objects --type cert 2>&1)
OBJ_RC=$?
if [ $OBJ_RC -ne 0 ]; then
    echo "Public read failed (rc=$OBJ_RC), trying with login..."
    echo -n "PIN: "
    read -s CARD_PIN
    echo
    export PKCS11_PIN="$CARD_PIN"
    OBJ_LIST=$(pkcs11-tool --module "$PKCS11_MODULE" --list-objects --type cert --login 2>&1)
    OBJ_RC=$?
    [ $OBJ_RC -ne 0 ] && { echo "$OBJ_LIST"; die "Cannot list objects on card (rc=$OBJ_RC)"; }
    LOGIN_FLAGS="--login"
else
    LOGIN_FLAGS=""
fi

# Parse cert IDs
CERT_IDS=()
while IFS= read -r line; do
    if echo "$line" | grep -q "ID:"; then
        ID=$(echo "$line" | sed 's/.*ID:[[:space:]]*//')
        CERT_IDS+=("$ID")
    fi
done <<< "$OBJ_LIST"

NUM_CERTS=${#CERT_IDS[@]}
if [ "$NUM_CERTS" -eq 0 ]; then
    echo "--- Card objects dump ---"
    echo "$OBJ_LIST"
    die "No certificates found on card"
fi

echo "Found $NUM_CERTS certificate(s):"
for i in $(seq 0 $((NUM_CERTS - 1))); do
    CERT_FILE="$TMPDIR/cert_${i}.der"
    pkcs11-tool --module "$PKCS11_MODULE" --read-object --type cert --id "${CERT_IDS[$i]}" $LOGIN_FLAGS -o "$CERT_FILE" 2>/dev/null
    if [ ! -s "$CERT_FILE" ]; then
        echo "  [$((i+1))] ID=${CERT_IDS[$i]}  (cannot read)"
        continue
    fi
    CN=$(openssl x509 -inform DER -in "$CERT_FILE" -noout -subject -nameopt utf8 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' | head -1)
    ISSUER_O=$(openssl x509 -inform DER -in "$CERT_FILE" -noout -issuer -nameopt utf8 2>/dev/null | grep -oP 'O\s*=\s*\K[^,/]+' | head -1)
    SERIAL=$(openssl x509 -inform DER -in "$CERT_FILE" -noout -serial 2>/dev/null | sed 's/serial=//')
    VALID=$(openssl x509 -inform DER -in "$CERT_FILE" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    echo "  [$((i+1))] ID=${CERT_IDS[$i]}  CN=$CN  Issuer=$ISSUER_O  SN=$SERIAL  Valid until: $VALID"
done

# Select cert
if [ "$NUM_CERTS" -eq 1 ]; then
    SEL=0
    echo "Using certificate [1]"
else
    echo -n "Select certificate [1-$NUM_CERTS]: "
    read SEL_INPUT
    SEL=$((SEL_INPUT - 1))
    [ "$SEL" -lt 0 ] || [ "$SEL" -ge "$NUM_CERTS" ] && die "Invalid selection"
fi

# Read selected cert to PEM
CHOSEN_ID="${CERT_IDS[$SEL]}"
CERT_DER_FILE="$TMPDIR/cert_${SEL}.der"
if [ ! -s "$CERT_DER_FILE" ]; then
    pkcs11-tool --module "$PKCS11_MODULE" --read-object --type cert --id "$CHOSEN_ID" $LOGIN_FLAGS -o "$CERT_DER_FILE" 2>/dev/null
fi
[ ! -s "$CERT_DER_FILE" ] && die "Failed to read certificate ID=$CHOSEN_ID"

CERT_PEM=$(openssl x509 -inform DER -in "$CERT_DER_FILE" -outform PEM 2>/dev/null)
[ -z "$CERT_PEM" ] && die "Failed to parse certificate ID=$CHOSEN_ID"

export PDFSIGN_NAME=$(openssl x509 -inform DER -in "$CERT_DER_FILE" -noout -subject -nameopt utf8 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' | head -1)
export PDFSIGN_ISSUER=$(openssl x509 -inform DER -in "$CERT_DER_FILE" -noout -issuer -nameopt utf8 2>/dev/null | grep -oP 'O\s*=\s*\K[^,/]+' | head -1)
export PDFSIGN_CERT_SN=$(openssl x509 -inform DER -in "$CERT_DER_FILE" -noout -serial 2>/dev/null | sed 's/serial=//')

echo "Signing as: $PDFSIGN_NAME"
echo "Issuer:     $PDFSIGN_ISSUER"
echo "Serial:     $PDFSIGN_CERT_SN"
echo ""

# --- Check: port conflict? ---
if lsof -i :38383 >/dev/null 2>&1; then
    echo "WARNING: Port 38383 is busy (prb-signer?)"
fi

source ~/venv/pdfsign/bin/activate

# Check deps
python3 -c "import fpdf, PyPDF2, pyhanko, pkcs11" 2>/dev/null || {
    echo "Installing dependencies..."
    pip install -q fpdf2 PyPDF2 pyhanko[pkcs11] || die "Failed to install dependencies"
}

echo "=== Step 1: Visual stamp ==="
python3 "$SCRIPT_DIR/stamp.py" "$INPUT" "$STAMPED"
[ -f "$STAMPED" ] || die "stamp.py failed to create $STAMPED"
echo "OK: $STAMPED"

echo "=== Step 2: Info page ==="
python3 "$SCRIPT_DIR/infopage.py" "$STAMPED" "$INFOED"
[ -f "$INFOED" ] || die "infopage.py failed to create $INFOED"
echo "OK: $INFOED"

echo "=== Step 3: Crypto sign ==="
python3 "$SCRIPT_DIR/pdfsign.py" "$INFOED" "$SIGNED"
[ -f "$SIGNED" ] || die "pdfsign.py failed to create $SIGNED"
echo "OK: $SIGNED"

# Cleanup intermediate
rm -f "$STAMPED" "$INFOED"

deactivate
echo "=== Done: $SIGNED ==="
