#!/usr/bin/env bash
set -euo pipefail

export PATH="$CONDA_PREFIX/bin:$PATH"

echo "🧬 Starting phylogeny..."

# ============================================================
# Locate config file (same directory as this script / GUI)
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/last_run_info.txt"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "❌ ERROR: last_run_info.txt not found in $SCRIPT_DIR"
  echo "Run the main pipeline from the GUI first."
  exit 1
fi

echo "📄 Loading run configuration from: $CONFIG_FILE"

# Load variables from config
source "$CONFIG_FILE"

# Validate required variables
: "${GUPPY_RESULTS_DIR:?Missing GUPPY_RESULTS_DIR in config}"
: "${RESULTS_DIR:?Missing RESULTS_DIR in config}"

CONSENSUS_DIR="${GUPPY_RESULTS_DIR}/consensus_passed"

echo "📂 Guppyplex results dir: $GUPPY_RESULTS_DIR"
echo "📂 Results dir: $RESULTS_DIR"
echo "📂 Consensus dir: $CONSENSUS_DIR"

# ============================================================
# Determine run folder (parent of results/ and guppyplex_results/)
# ============================================================
RUN_DIR="$(dirname "$RESULTS_DIR")"

# tree_augur is now inside the run folder
TREE_DIR="${RUN_DIR}/tree_augur"

echo "📂 Run folder: $RUN_DIR"
echo "📂 tree_augur dir: $TREE_DIR"

# ============================================================
# Static tree resources (inside run_folder/tree_augur/)
# ============================================================
EXISTING_ALIGNMENT="${TREE_DIR}/example.fasta"
METADATA="${TREE_DIR}/metadata.tsv"
COLORS="${TREE_DIR}/colors.tsv"
CONFIG_JSON="${TREE_DIR}/auspice_config.json"

# ============================================================
# Output files (still written to results/)
# ============================================================
mkdir -p "$RESULTS_DIR"

MERGED_FASTA="$RESULTS_DIR/all_sequences.fasta"
ALIGNMENT="$RESULTS_DIR/aligned.fasta"
TREE="$RESULTS_DIR/tree.nwk"
REFINED_TREE="$RESULTS_DIR/refined.nwk"
REFINED_NODE_DATA="$RESULTS_DIR/refined.json"
TRAITS="$RESULTS_DIR/traits.json"
AUSPICE_JSON="$RESULTS_DIR/auspice.json"

# ============================================================
# Step 0. Input checks
# ============================================================
if [[ ! -d "$CONSENSUS_DIR" ]]; then
  echo "❌ ERROR: Consensus directory not found: $CONSENSUS_DIR"
  exit 1
fi

if [[ ! -d "$TREE_DIR" ]]; then
  echo "❌ ERROR: tree_augur directory not found: $TREE_DIR"
  exit 1
fi

if [[ ! -f "$EXISTING_ALIGNMENT" ]]; then
  echo "❌ ERROR: Existing alignment not found: $EXISTING_ALIGNMENT"
  exit 1
fi

if [[ ! -f "$METADATA" ]]; then
  echo "❌ ERROR: Metadata file not found: $METADATA"
  exit 1
fi

if [[ ! -f "$COLORS" ]]; then
  echo "❌ ERROR: Colors file not found: $COLORS"
  exit 1
fi

echo "[0/9] Collecting FASTA sequences from: $CONSENSUS_DIR"

# ============================================================
# Step 1. Merge FASTAs with renamed headers
# ============================================================
echo "[1/9] Renaming FASTA headers to match filenames..."
> "$MERGED_FASTA"

found_any=false
declare -a SAMPLE_NAMES=()

for fasta in "$CONSENSUS_DIR"/*.fasta; do
  [[ -e "$fasta" ]] || continue
  found_any=true

  sample_name=$(basename "$fasta" .fasta)
  SAMPLE_NAMES+=("$sample_name")

  awk -v name="$sample_name" '/^>/{print ">"name; next} {print}' "$fasta" >> "$MERGED_FASTA"
done

if [[ "$found_any" = false ]]; then
  echo "❌ ERROR: No FASTA files found in $CONSENSUS_DIR"
  exit 1
fi

echo "[1/9] Merged FASTA written to: $MERGED_FASTA"

# ============================================================
# Step 2. Ensure metadata has all samples
# ============================================================
echo "[2/9] Checking metadata.tsv for missing sample IDs..."

header_line=$(head -n 1 "$METADATA")
existing_ids=($(tail -n +2 "$METADATA" | cut -f1))

for sample in "${SAMPLE_NAMES[@]}"; do
  if ! printf '%s\n' "${existing_ids[@]}" | grep -qx "$sample"; then
    echo -e "${sample}\tunknown" >> "$METADATA"
    echo "  ➕ Added missing sample: $sample → unknown"
  fi
done

echo "[2/9] Metadata check complete."

# ============================================================
# Step 3. Align sequences
# ============================================================
augur align \
  --sequences "$MERGED_FASTA" \
  --existing-alignment "$EXISTING_ALIGNMENT" \
  --output "$ALIGNMENT" \
  --fill-gaps

echo "[3/9] Alignment completed: $ALIGNMENT"

# ============================================================
# Step 4. Build tree
# ============================================================
augur tree \
  --alignment "$ALIGNMENT" \
  --output "$TREE"

echo "[4/9] Tree built: $TREE"

# ============================================================
# Step 5. Refine tree
# ============================================================
augur refine \
  --tree "$TREE" \
  --alignment "$ALIGNMENT" \
  --metadata "$METADATA" \
  --root mid_point \
  --output-tree "$REFINED_TREE" \
  --output-node-data "$REFINED_NODE_DATA"

echo "[5/9] Refined tree created: $REFINED_TREE"

# ============================================================
# Step 6. Infer traits
# ============================================================
augur traits \
  --tree "$REFINED_TREE" \
  --metadata "$METADATA" \
  --columns group \
  --output-node-data "$TRAITS"

echo "[6/9] Traits inferred: $TRAITS"

# ============================================================
# Step 7. Export Auspice JSON
# ============================================================
augur export v2 \
  --tree "$REFINED_TREE" \
  --metadata "$METADATA" \
  --node-data "$REFINED_NODE_DATA" \
  --node-data "$TRAITS" \
  --auspice-config "$CONFIG_JSON" \
  --colors "$COLORS" \
  --output "$AUSPICE_JSON"

echo "[7/9] Export complete: $AUSPICE_JSON"

# ============================================================
# Step 8. Launch Auspice
# ============================================================
echo "[8/9] Launching Auspice viewer..."
echo "🌐 Open http://127.0.0.1:4000 in your browser"

HOST=127.0.0.1 auspice view --datasetDir "$RESULTS_DIR"

echo "[9/9] Phylogeny pipeline completed successfully!"
