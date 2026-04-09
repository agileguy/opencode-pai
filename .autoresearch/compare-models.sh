#!/bin/bash
# compare-models.sh — Run the same eval on two models and compare
# Usage: bash .autoresearch/compare-models.sh pai-engineer model1 model2

set -uo pipefail

AGENT="${1:-pai-engineer}"
MODEL1="${2:?Usage: compare-models.sh <agent> <model1> <model2>}"
MODEL2="${3:?Usage: compare-models.sh <agent> <model1> <model2>}"
EVAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/eval"
CONFIG="$(cd "$(dirname "$0")/.." && pwd)/config/opencode.json"

echo "═══ Model Comparison: $MODEL1 vs $MODEL2 ═══"
echo "Agent: $AGENT"
echo ""

# Backup current config
cp "$CONFIG" "${CONFIG}.bak"

run_with_model() {
  local model="$1"
  local label="$2"
  echo "── Running with: $model ──"

  # Swap model in config using sed
  sed -i.tmp "s|\"model\": \"omlx/[^\"]*\"|\"model\": \"omlx/$model\"|g" "$CONFIG"
  rm -f "${CONFIG}.tmp"

  # Run eval
  local score
  score=$(bash "$EVAL_DIR/run-eval.sh" "$AGENT" 2>&1 | tail -1)
  echo "  Score: $score"
  echo "$score"
}

SCORE1=$(run_with_model "$MODEL1" "Model 1")
echo ""
SCORE2=$(run_with_model "$MODEL2" "Model 2")

# Restore original config
mv "${CONFIG}.bak" "$CONFIG"

echo ""
echo "═══ Results ═══"
echo "$MODEL1: $SCORE1"
echo "$MODEL2: $SCORE2"

BETTER=$(awk "BEGIN {print ($SCORE1 > $SCORE2) ? \"$MODEL1\" : \"$MODEL2\"}")
DIFF=$(awk "BEGIN {printf \"%.4f\", $SCORE1 - $SCORE2}")
echo "Winner: $BETTER (diff: $DIFF)"
