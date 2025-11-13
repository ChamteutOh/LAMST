#!/bin/bash

# === LOAD MODULES ===
module load samtools
module load nanofilt
module load nextflow
module load singularity

# === PATH CONFIGURATION ===
BASE_DIR="/blue/chamteutoh/Milton/water/16s"
DEMUX_DIR="${BASE_DIR}/demux"
FASTQ_DIR="${BASE_DIR}/fastq_outputs"
FILTERED_DIR="${BASE_DIR}/filtered_fastqs"
RESULTS_DIR="${BASE_DIR}/wf16s_results"
TMP_DIR="${BASE_DIR}/tmp"
NXF_SINGULARITY_CACHEDIR="${BASE_DIR}/singularity_cache"

mkdir -p "$FASTQ_DIR" "$FILTERED_DIR" "$RESULTS_DIR" "$TMP_DIR" "$NXF_SINGULARITY_CACHEDIR"

# Export custom paths
export NXF_SINGULARITY_CACHEDIR
export TMPDIR="$TMP_DIR"

# === PROCESS EACH BAM FILE ONE BY ONE ===
for bamfile in "${DEMUX_DIR}"/*_barcode*.bam; do
    barcode=$(basename "$bamfile" | grep -o "barcode[0-9]\+")
    output_dir="${RESULTS_DIR}/${barcode}"

    # === SKIP IF OUTPUT FOLDER EXISTS ===
    if [[ -d "$output_dir" ]]; then
        echo "⏭️  Skipping $barcode because output folder already exists."
        continue
    fi

    echo "🔄 Processing $barcode..."

    # Step 1: Convert BAM to FASTQ
    fastq_file="${FASTQ_DIR}/${barcode}.fastq"
    samtools fastq "$bamfile" > "$fastq_file"

    # Step 2: Filter FASTQ with safe temp write
    filtered_fastq="${FILTERED_DIR}/Filtered_${barcode}.fastq"
    temp_filtered_fastq="${filtered_fastq}.tmp"
    if cat "$fastq_file" | NanoFilt -q 20 -l 100 > "$temp_filtered_fastq"; then
        mv "$temp_filtered_fastq" "$filtered_fastq"
    else
        echo "❌ NanoFilt failed for $barcode — skipping."
        rm -f "$temp_filtered_fastq"
        continue
    fi

    # Step 3: Create output folder (do NOT copy FASTQ)
    mkdir -p "$output_dir"

    # Step 4: Run Nextflow using filtered FASTQ directly
    pushd "$output_dir" > /dev/null
    nextflow run epi2me-labs/wf-16s \
        --fastq "$filtered_fastq" \
        --classifier kraken2 \
        --taxonomic_rank S \
        -profile singularity \
        -work-dir "$output_dir/work"
    popd > /dev/null

    echo "✅ Completed $barcode"
done

echo "🎉 All samples processed. Results in: $RESULTS_DIR"
