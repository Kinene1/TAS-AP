#!/bin/bash

set -euo pipefail

# Tonny Kinene (Tonny.Kinene@dpird.wa.gov.au)

#-----------------------------------------------------------------------
# DPIRD DIagnostics and Laboratory Services
# Sustainability and Biosecurity 
# Department of primary Industires and Regional Development
# 31 Cedric Street, Stirling WA 6021
# ----------------------------------------------------------------------

# Copyright (c) 2026 Tonny Kinene
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#------------------------------------------------------------------------


# --------------------------------------------------
# Resolve script directory (for GUI / PyInstaller runs)
# --------------------------------------------------
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
cd "$SCRIPT_DIR"

echo "Running pipeline from: $SCRIPT_DIR"

# Absolute path to covarplot
COVARPLOT="$SCRIPT_DIR/covarplot.py"

if [[ ! -f "$COVARPLOT" ]]; then
    echo "covarplot.py not found in $SCRIPT_DIR"
    exit 1
fi


export PATH="$CONDA_PREFIX/bin:$PATH"
shopt -s nullglob

REPORT_DATE=$(date '+%Y-%m-%d')

# ------------------------------
# Input directories and metadata
# ------------------------------
BASE_DIR="${BASE_DIR:-fastq_pass}"                     # Input FASTQ base dir
OUTPUT_DIR="${GUPPY_RESULTS_DIR:-guppyplex_results}"  # Guppyplex results dir from GUI
METADATA_FILE="${METADATA_FILE:-sample_metadata.tsv}"

MIN_LENGTH="${MIN_LENGTH:-250}"
MAX_LENGTH="${MAX_LENGTH:-1500}"

mkdir -p "$OUTPUT_DIR"

# ------------------------------
# Parallel jobs
# ------------------------------
PARALLEL_JOBS=8

# ------------------------------
# Run / Sample Prefix
# ------------------------------
RUN_AND_SAMPLE_PREFIX="${RUN_AND_SAMPLE_PREFIX:-DefaultPrefix}"
RUN_PREFIX="${RUN_PREFIX:-$RUN_AND_SAMPLE_PREFIX}"

# ------------------------------
# Scheme paths
# ------------------------------
SCHEME_DIR="${SCHEME_DIR:-/media/ddlsbioinf2/disk1/tonny/primer-schemes/Ants}"
BED_FILE="${BED_FILE:-${SCHEME_DIR}/incisa/V2/incisa.scheme.bed}"
REF_FILE="${REF_FILE:-${SCHEME_DIR}/incisa/V2/incisa.reference.fasta}"

SCHEME_NAME=$(basename "$(dirname "$BED_FILE")")
PARENT_SCHEME=$(basename "$(dirname "$(dirname "$BED_FILE")")")

# ------------------------------
# Helper: limit background jobs
# ------------------------------
function wait_for_jobs {
    while (( $(jobs -rp | wc -l) >= PARALLEL_JOBS )); do
        sleep 1
    done
}

# ------------------------------
# Step 1: Guppyplex
# ------------------------------
echo "Running guppyplex in parallel..."
for BARCODE_DIR in "$BASE_DIR"/barcode*/; do
    [ -d "$BARCODE_DIR" ] || continue
    wait_for_jobs

    (
        BARCODE_NAME=$(basename "$BARCODE_DIR")
        PREFIX="${RUN_PREFIX}_${BARCODE_NAME}"
        echo "Processing $BARCODE_NAME..."

        cd "$BARCODE_DIR" || exit 1
        artic guppyplex --min-length "$MIN_LENGTH" --max-length "$MAX_LENGTH" \
            --directory . --prefix "$PREFIX" \
            > "${OUTPUT_DIR}/${BARCODE_NAME}.log" 2>&1

        BARCODE_OUTPUT_DIR="${OUTPUT_DIR}/${BARCODE_NAME}"
        mkdir -p "$BARCODE_OUTPUT_DIR"

        NEW_FASTQ="${BARCODE_OUTPUT_DIR}/${RUN_PREFIX}_${BARCODE_NAME}.fastq"
        cat "${PREFIX}_"*.fastq > "$NEW_FASTQ"
        rm -f "${PREFIX}_"*.fastq
        echo "Created: $NEW_FASTQ"
    ) &
done
wait
echo "Guppyplex done for all barcodes."

# ------------------------------
# Step 2: Artic Minion #--model r1041_e82_400bps_sup_v500 \
# ------------------------------
echo
echo "Running artic minion in parallel..."
for BARCODE_PATH in "$OUTPUT_DIR"/barcode*/; do
    wait_for_jobs

    (
        FASTQ_FILE=$(find "$BARCODE_PATH" -name "${RUN_PREFIX}_*.fastq" | head -n 1)
        [ -f "$FASTQ_FILE" ] || { echo "No FASTQ in $BARCODE_PATH"; exit 0; }

        SAMPLE_NAME=$(basename "$FASTQ_FILE" .fastq)
        echo "Running artic minion for $SAMPLE_NAME..."

        cd "$BARCODE_PATH" || exit 1
        artic minion --normalise 400 --threads 8 \
            --scheme-directory "$SCHEME_DIR" \
            --read-file "$(basename "$FASTQ_FILE")" \
            --bed "$BED_FILE" --ref "$REF_FILE" "$SAMPLE_NAME"

        echo "Finished artic minion: $SAMPLE_NAME"
    ) &
done
wait
echo "ARTIC minion done for all barcodes."

# ------------------------------
# Step 3: Load metadata
# ------------------------------
declare -A SAMPLE_IDS
if [[ -f "$METADATA_FILE" ]]; then
    echo
    echo "Loading metadata from $METADATA_FILE..."
    {
        read -r header
        while IFS=$'\t' read -r barcode sample_id; do
            [[ -z "$barcode" ]] && continue
            barcode="${barcode//[[:space:]]/}"
            sample_id="${sample_id//[[:space:]]/}"
            SAMPLE_IDS["$barcode"]="$sample_id"
        done
    } < "$METADATA_FILE"
else
    echo "Metadata file not found: $METADATA_FILE"
fi

# ------------------------------
# Step 4: Generate HTML report
# ------------------------------
REPORT_FILE="${OUTPUT_DIR}/coverage_summary_report.html"
PDF_REPORT="${OUTPUT_DIR}/coverage_summary_report.pdf"

{
    echo "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Coverage Summary Report</title>"
    echo "<style>
        body { font-family: sans-serif; padding: 20px; }
        h2 { margin-top: 40px; }
        ul { list-style: none; padding: 0; }
        li { margin-bottom: 5px; }
        img { max-width: 100%; height: auto; border: 1px solid #ccc; margin-bottom: 20px; }
        table { border-collapse: collapse; margin-top: 20px; font-size: 10px; table-layout: fixed; width: 100%; word-wrap: break-word; }
        th, td { border: 1px solid #ccc; padding: 6px 8px; text-align: left; }
    </style></head><body><h1>Coverage Summary Report</h1>"
} > "$REPORT_FILE"

for BARCODE_DIR in "$OUTPUT_DIR"/barcode*/; do
    BARCODE_NAME=$(basename "$BARCODE_DIR")
    SAMPLE_ID="${SAMPLE_IDS[$BARCODE_NAME]:-$BARCODE_NAME}"
    PLOT_IMAGE=$(find "$BARCODE_DIR" -type f -name "*CoVarPlot.png" | head -n 1)
    SAMPLE_FASTQ=$(find "$BARCODE_DIR" -name "${RUN_PREFIX}_*.fastq" | head -n 1)
    SAMPLE_NAME=$(basename "$SAMPLE_FASTQ" .fastq)

    DEPTH1="${BARCODE_DIR}/${SAMPLE_NAME}.coverage_mask.txt.${PARENT_SCHEME}_1.depths"
    DEPTH2="${BARCODE_DIR}/${SAMPLE_NAME}.coverage_mask.txt.${PARENT_SCHEME}_2.depths"

    echo "<h2>${BARCODE_NAME}</h2>" >> "$REPORT_FILE"
    echo "<ul><li><strong>Sample ID:</strong> $SAMPLE_ID</li></ul>" >> "$REPORT_FILE"

    if [[ -f "$DEPTH1" && -f "$DEPTH2" ]]; then
        echo "Generating plot for $SAMPLE_NAME..."
        python3 covarplot.py -d1 "$DEPTH1" -d2 "$DEPTH2" -b "$BED_FILE" -l -s "$BARCODE_DIR"
        PLOT_IMAGE=$(find "$BARCODE_DIR" -type f -name "*CoVarPlot.png" | head -n 1)
    fi

    if [ -f "$PLOT_IMAGE" ]; then
        REL_PATH=$(realpath --relative-to="$OUTPUT_DIR" "$PLOT_IMAGE")
        echo "<img src=\"$REL_PATH\" alt=\"Coverage plot for ${BARCODE_NAME}\"><br>" >> "$REPORT_FILE"
    else
        echo "<p style='color:red;'>No plot found</p>" >> "$REPORT_FILE"
    fi
done

# ------------------------------
# Step 5: Collect consensus sequences
# ------------------------------
CONSENSUS_DIR="${OUTPUT_DIR}/consensus_seq"
mkdir -p "$CONSENSUS_DIR"

echo
echo "Collecting consensus FASTA files..."
find "$OUTPUT_DIR" -type f -name "*.consensus.fasta" | while read -r fasta_file; do
    SAMPLE_NAME=$(basename "$fasta_file")
    TARGET="${CONSENSUS_DIR}/${SAMPLE_NAME}"

    if [ -e "$TARGET" ]; then
        BARCODE=$(basename "$(dirname "$fasta_file")")
        TARGET="${CONSENSUS_DIR}/${BARCODE}_${SAMPLE_NAME}"
    fi

    cp "$fasta_file" "$TARGET"
    echo "Copied: $fasta_file -> $TARGET"
done

echo "All consensus FASTA files saved to: $CONSENSUS_DIR"

# ------------------------------
# Step 6: Rename FASTA files using sample IDs
# ------------------------------
echo
echo "Renaming consensus FASTA files with sample IDs..."
for fasta_file in "$CONSENSUS_DIR"/*.fasta; do
    filename=$(basename "$fasta_file")
    barcode_id=$(echo "$filename" | sed -E 's/.*(barcode[0-9]+).*/\1/')
    sample_id="${SAMPLE_IDS[$barcode_id]:-}"

    if [[ -n "$sample_id" ]]; then
        new_name="${sample_id}_${barcode_id}.consensus.fasta"
        new_path="${CONSENSUS_DIR}/${new_name}"
        mv "$fasta_file" "$new_path"
        echo "Renamed to: $new_name"
    else
        echo "No sample ID found for $filename — skipping rename"
    fi
done

# ------------------------------
# Step 7: Genome recovery summary
# ------------------------------
REF_LENGTH=$(awk '/^[^>]/ { total += length } END { print total }' "$REF_FILE")
echo "Reference genome length: $REF_LENGTH bp"

DECISION_TABLE="<h2>Genome Recovery Summary</h2>
<div style='overflow-x:auto;'>
<table style='font-size:10px; width:100%; table-layout:fixed; word-wrap:break-word;'>
<tr><th>Sample</th><th>Sample ID</th><th>Recovery (%)</th><th>Status</th></tr>"

CSV_FILE="${OUTPUT_DIR}/genome_recovery_summary.csv"
echo "Sample,Sample_ID,Recovery_Percent,Status" > "$CSV_FILE"

CONSENSUS_PASSED_DIR="${OUTPUT_DIR}/consensus_passed"
mkdir -p "$CONSENSUS_PASSED_DIR"

for FASTA_FILE in $(ls "$CONSENSUS_DIR"/*.fasta | sed -E 's/.*_barcode([0-9]+)\.consensus\.fasta/\1 &/' | sort -k1,1n | cut -d' ' -f2-); do
    SAMPLE=$(basename "$FASTA_FILE" .fasta)
    BARCODE_ID=$(echo "$SAMPLE" | sed -E 's/.*_(barcode[0-9]+).*/\1/')
    SAMPLE_ID="${SAMPLE_IDS[$BARCODE_ID]:-N/A}"
    NON_N=$(grep -v '^>' "$FASTA_FILE" | tr -d ' \n' | tr '[:lower:]' '[:upper:]' | tr -cd 'ACGT' | wc -c)
    PERCENT=$(awk -v n="$NON_N" -v r="$REF_LENGTH" 'BEGIN { printf "%.1f", (n/r)*100 }')

    if (( $(echo "$PERCENT >= 70" | bc -l) )); then
        STATUS="✅ Passed"
        cp "$FASTA_FILE" "${CONSENSUS_PASSED_DIR}/$(basename "$FASTA_FILE")"
    else
        STATUS="❌ Dropped"
    fi

    DECISION_TABLE+="<tr><td>${SAMPLE}</td><td>${SAMPLE_ID}</td><td>${PERCENT}%</td><td>${STATUS}</td></tr>"
    echo "${SAMPLE},${SAMPLE_ID},${PERCENT},${STATUS}" >> "$CSV_FILE"
done

DECISION_TABLE+="</table></div>"
echo "$DECISION_TABLE" >> "$REPORT_FILE"
echo "Decision table added to HTML report."
echo "CSV summary saved to: $CSV_FILE"
echo "Passed consensus FASTAs copied to: $CONSENSUS_PASSED_DIR"

# ------------------------------
# Footer and PDF
# ------------------------------
{
    echo "<hr>"
    echo "<footer style='font-size: 10px; color: #555;'>"
    echo "<p><em>DPIRD Diagnostic & Laboratory Services (DDLS)</em><br>"
    echo "<em>Authorised by: Dr Tonny Kinene</em><br>"
    echo "<em>Produced: ${REPORT_DATE}</em></p>"
    echo "</footer>"
    echo "</body></html>"
} >> "$REPORT_FILE"

echo "HTML report saved to: $REPORT_FILE"

echo
echo "Generating PDF..."
if command -v weasyprint &> /dev/null; then
    weasyprint "$REPORT_FILE" "${OUTPUT_DIR}/coverage_summary_report.pdf"
    echo "PDF saved to: $PDF_REPORT"
else
    echo "WeasyPrint not found. Install with: pip install weasyprint"
fi

echo
echo "All processing complete!"
