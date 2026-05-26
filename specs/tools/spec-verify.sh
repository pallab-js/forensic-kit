#!/usr/bin/env bash
# spec-verify.sh — Local spec-kit substitute
# Usage: ./specs/tools/spec-verify.sh specs/phase-N.yaml --dir Sources/
# Checks:
#   1. YAML is valid (yamllint)
#   2. All REQ-XXX IDs in the spec have matching // SPEC: REQ-XXX tags in source
# Exit: 0 = ALL PASS, 1 = FAIL

set -euo pipefail

SPEC_FILE="${1:-}"
SOURCE_DIR="${3:-Sources/}"
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [[ -z "$SPEC_FILE" ]]; then
    echo -e "${RED}[ERROR] Usage: $0 <spec-file.yaml> --dir <source-dir>${NC}"
    exit 1
fi

if [[ ! -f "$SPEC_FILE" ]]; then
    echo -e "${RED}[FAIL] Spec file not found: $SPEC_FILE${NC}"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " spec-verify.sh — ForensicKit Spec Validator"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Spec : $SPEC_FILE"
echo " Src  : $SOURCE_DIR"
echo ""

# ── Step 1: YAML lint ──────────────────────────────────────────────────────────
echo "[1/2] YAML lint..."
if command -v yamllint &>/dev/null; then
    if yamllint -d "{extends: default, rules: {line-length: {max: 120}}}" "$SPEC_FILE" 2>&1; then
        echo -e "${GREEN}  ✓ YAML valid${NC}"
    else
        echo -e "${RED}  ✗ YAML lint failed${NC}"
        FAIL=1
    fi
else
    echo -e "${YELLOW}  ⚠ yamllint not found — skipping YAML lint (run: brew install yamllint)${NC}"
fi

echo ""

# ── Step 2: Traceability check ─────────────────────────────────────────────────
echo "[2/2] Traceability check (// SPEC: REQ-XXX tags in source)..."

# Extract all REQ-IDs from the spec file
REQ_IDS=$(grep -oE 'id:\s+REQ-[0-9]+' "$SPEC_FILE" | grep -oE 'REQ-[0-9]+' || true)

if [[ -z "$REQ_IDS" ]]; then
    echo -e "${YELLOW}  ⚠ No REQ-IDs found in spec — nothing to trace${NC}"
else
    while IFS= read -r req_id; do
        # Search for // SPEC: REQ-XXX in Swift source files
        if grep -r "// SPEC:.*${req_id}" "$SOURCE_DIR" --include="*.swift" -q 2>/dev/null; then
            echo -e "${GREEN}  ✓ ${req_id} — traced in source${NC}"
        else
            echo -e "${RED}  ✗ ${req_id} — NOT traced in source (missing // SPEC: ${req_id})${NC}"
            FAIL=1
        fi
    done <<< "$REQ_IDS"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN} ✅ ALL PASS${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
else
    echo -e "${RED} ❌ SPEC VERIFICATION FAILED${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi
