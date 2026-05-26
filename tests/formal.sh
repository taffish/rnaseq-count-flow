#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
project_dir=$(CDPATH= cd "$script_dir/.." && pwd)
bio_apps_dir=$(CDPATH= cd "$project_dir/../../../.." && pwd)
rnaseq_root=$(CDPATH= cd "$project_dir/../.." && pwd)
index_flow_dir="$rnaseq_root/subflows/rnaseq-index-flow"
alignment_flow_dir="$rnaseq_root/subflows/rnaseq-alignment-flow"
default_data_root=$(CDPATH= cd "$rnaseq_root/test-data/yeast/data/03_results" 2>/dev/null && pwd || printf '%s\n' "$rnaseq_root/test-data/yeast/data/03_results")
data_root=${TAFFISH_RNASEQ_TESTDATA:-$default_data_root}

for target_dir in \
    "$bio_apps_dir/tools/subread/target" \
    "$bio_apps_dir/tools/samtools/target" \
    "$bio_apps_dir/tools/multiqc/target" \
    "$bio_apps_dir/tools/hisat2/target" \
    "$bio_apps_dir/tools/fastp/target" \
    "$bio_apps_dir/tools/agat/target" \
    "$bio_apps_dir/tools/gffread/target" \
    "$bio_apps_dir/tools/salmon/target" \
    "$bio_apps_dir/tools/kallisto/target" \
    "$index_flow_dir/target" \
    "$alignment_flow_dir/target"
do
    if [ -d "$target_dir" ]; then
        PATH="$target_dir:$PATH"
    fi
done
export PATH

TAFFISH_CONTAINER_BACKEND=${TAFFISH_CONTAINER_BACKEND:-podman}
export TAFFISH_CONTAINER_BACKEND
TAF_HISTORY_MODE=${TAF_HISTORY_MODE:-off}
export TAF_HISTORY_MODE

skip_formal() {
    echo "formal: skipped: $*" >&2
    exit 0
}

require_file() {
    if [ ! -s "$1" ]; then
        echo "formal: expected file is missing or empty: $1" >&2
        exit 1
    fi
}

require_contains() {
    file=$1
    pattern=$2
    label=$3
    if ! grep -F "$pattern" "$file" >/dev/null; then
        echo "formal: missing $label in $file: $pattern" >&2
        exit 1
    fi
}

require_nonnegative_metric() {
    file=$1
    metric=$2
    value=$(awk -F '\t' -v key="$metric" '
        $1 == key {
            print $2
            found = 1
            exit
        }
        END {
            if (!found) exit 2
        }
    ' "$file") || {
        echo "formal: missing metric in $file: $metric" >&2
        exit 1
    }
    if ! awk -v value="$value" 'BEGIN { exit !(value ~ /^[0-9]+$/) }'; then
        echo "formal: metric is not a non-negative integer in $file: $metric=$value" >&2
        exit 1
    fi
}

if [ ! -d "$data_root" ]; then
    skip_formal "RNA-seq formal data root not found: $data_root"
fi

fastq_pkg="$data_root/yeast-snf2-fastq-mini-v1"
samples="$fastq_pkg/samples.tsv"
reference_pkg="$data_root/yeast-reference-sgd-r64.4.1-v1"
genome="$reference_pkg/reference/genome/yeast_s288c_reference_genome_R64-4-1.fa"
annotation="$reference_pkg/reference/annotation/yeast_s288c_gene_annotation_R64-4-1.gff3"

[ -s "$samples" ] || skip_formal "missing yeast FASTQ sample table: $samples"
[ -s "$genome" ] || skip_formal "missing yeast reference genome FASTA: $genome"
[ -s "$annotation" ] || skip_formal "missing yeast reference GFF3 annotation: $annotation"

if ! command -v taf >/dev/null 2>&1; then
    echo "formal: taf command not found in PATH." >&2
    exit 127
fi

for dep in \
    taf-subread-v2.1.1-r2 \
    taf-samtools-v1.23.1-r1 \
    taf-multiqc-v1.35-r2 \
    taf-hisat2-v2.2.2-r2 \
    taf-fastp-v1.3.3-r3 \
    taf-agat-v1.7.0-r1 \
    taf-gffread-v0.12.9-r1 \
    taf-salmon-v1.11.4-r1 \
    taf-kallisto-v0.52.0-r1
do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "formal: dependency wrapper not found in PATH: $dep" >&2
        exit 127
    fi
done

tmpdir=$(mktemp -d "$project_dir/.taf-formal.XXXXXX")
cleanup() {
    cd "$project_dir" 2>/dev/null || :
    rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM HUP

echo "[FORMAL] build rnaseq-index-flow"
(
    cd "$index_flow_dir"
    taf check
    taf build
)

index_flow_cmd="$index_flow_dir/target/taf-rnaseq-index-flow-v0.1.0-r1"
[ -x "$index_flow_cmd" ] || {
    echo "formal: built index flow command is missing or not executable: $index_flow_cmd" >&2
    exit 1
}

echo "[FORMAL] build rnaseq-alignment-flow"
(
    cd "$alignment_flow_dir"
    taf check
    taf build
)

alignment_flow_cmd="$alignment_flow_dir/target/taf-rnaseq-alignment-flow-v0.1.0-r1"
[ -x "$alignment_flow_cmd" ] || {
    echo "formal: built alignment flow command is missing or not executable: $alignment_flow_cmd" >&2
    exit 1
}

cd "$project_dir"

echo "[FORMAL] taf check"
taf check

echo "[FORMAL] taf build"
taf build

flow_cmd="$project_dir/target/taf-rnaseq-count-flow-v0.1.0-r1"
if [ ! -x "$flow_cmd" ]; then
    echo "formal: built count flow command is missing or not executable: $flow_cmd" >&2
    exit 1
fi

run_dir="$tmpdir/run"
mkdir -p "$run_dir/reads"

formal_samples="$run_dir/samples.tsv"
printf 'sample_id\tread1\tcondition\tlibrary_layout\n' > "$formal_samples"
{
    printf 'sample_id\tread1\tcondition\tlibrary_layout\n'
    awk -F '\t' -v root="$fastq_pkg" -v OFS='\t' '
        NR == 1 {
            for (i = 1; i <= NF; i++) col[$i] = i
            next
        }
        $1 == "WT_01" || $1 == "SNF2KO_01" {
            print $1, root "/" $(col["read1"]), $(col["condition"]), "single-end"
        }
    ' "$samples"
} > "$run_dir/source_subset.tsv"

line_no=0
while IFS="$(printf '\t')" read -r sid read1 condition layout || [ -n "$sid" ]; do
    line_no=$((line_no + 1))
    [ "$line_no" -eq 1 ] && continue
    [ -s "$read1" ] || {
        echo "formal: missing source FASTQ for $sid: $read1" >&2
        exit 1
    }
    subset="$run_dir/reads/$sid.subset.fq.gz"
    gzip -cd "$read1" | awk 'NR <= 80000 { print }' | gzip -c > "$subset"
    printf '%s\t%s\t%s\t%s\n' "$sid" "$subset" "$condition" "$layout" >> "$formal_samples"
done < "$run_dir/source_subset.tsv"

sample_rows=$(awk 'NR > 1 { c++ } END { print c + 0 }' "$formal_samples")
[ "$sample_rows" -eq 2 ] || skip_formal "expected two formal FASTQ samples, got $sample_rows"

echo "[FORMAL] rnaseq-index-flow yeast reference with HISAT2 index"
(
    cd "$run_dir"
    "$index_flow_cmd" \
        --genome "$genome" \
        --annotation "$annotation" \
        --outdir ref-out \
        --threads 2 \
        --indexer salmon \
        --genome-indexer hisat2
)

test -s "$run_dir/ref-out/03_results/annotation/genes.gtf"
test -s "$run_dir/ref-out/03_results/hisat2_index/genome.1.ht2"

echo "[FORMAL] rnaseq-alignment-flow yeast FASTQ subset"
(
    cd "$run_dir"
    "$alignment_flow_cmd" \
        --samples "$formal_samples" \
        --index "$run_dir/ref-out/03_results/hisat2_index/genome" \
        --outdir align-out \
        --threads 2
)

test -s "$run_dir/align-out/04_reports/bam_files.tsv"
test -s "$run_dir/align-out/03_results/bam/WT_01.sorted.bam"
test -s "$run_dir/align-out/03_results/bam/SNF2KO_01.sorted.bam"

echo "[FORMAL] rnaseq-count-flow yeast BAM subset"
(
    cd "$run_dir"
    "$flow_cmd" \
        --bams "$run_dir/align-out/04_reports/bam_files.tsv" \
        --annotation "$run_dir/ref-out/03_results/annotation/genes.gtf" \
        --outdir count-out \
        --threads 2 \
        --strand 0 \
        --min-assigned-reads 1
)

out="$run_dir/count-out"
echo "[FORMAL] output checks"
require_file "$out/02_intermediate/featurecounts_annotation.gtf"
require_file "$out/02_intermediate/featurecounts_annotation_stats.tsv"
require_file "$out/03_results/featurecounts/featureCounts.txt"
require_file "$out/03_results/featurecounts/featureCounts.txt.summary"
require_file "$out/03_results/matrices/gene_counts.tsv"
require_file "$out/03_results/assignment_summary.tsv"
require_file "$out/04_reports/count_summary.tsv"
require_file "$out/04_reports/multiqc_report.html"
require_file "$out/04_reports/commands.sh"
require_file "$out/04_reports/versions.tsv"
require_file "$out/04_reports/methods.txt"
require_file "$out/04_reports/flow_summary.tsv"
require_file "$out/run.manifest.json"

awk -F '\t' 'NR == 1 {
    for (i = 1; i <= NF; i++) {
        if ($i == "WT_01") wt = 1
        if ($i == "SNF2KO_01") ko = 1
    }
    exit !(wt && ko)
}' "$out/03_results/matrices/gene_counts.tsv" || {
    echo "formal: gene count matrix header does not include WT_01 and SNF2KO_01" >&2
    sed -n '1p' "$out/03_results/matrices/gene_counts.tsv" >&2
    exit 1
}
require_contains "$out/03_results/assignment_summary.tsv" 'Assigned	WT_01' "WT_01 assigned-read row"
require_contains "$out/04_reports/flow_summary.tsv" 'sample_count	2' "sample count"
require_nonnegative_metric "$out/04_reports/flow_summary.tsv" "filled_missing_attribute"
require_nonnegative_metric "$out/02_intermediate/featurecounts_annotation_stats.tsv" "filled_missing_attribute"
require_contains "$out/04_reports/commands.sh" 'taf-subread-v2.1.1-r2' "Subread dependency command"
require_contains "$out/run.manifest.json" '"flow": "rnaseq-count-flow"' "flow manifest identity"

assigned=$(awk -F '\t' '$1 == "assigned_reads" { print $2 }' "$out/04_reports/flow_summary.tsv")
[ "$assigned" -gt 0 ] || {
    echo "formal: expected assigned reads for yeast featureCounts formal test" >&2
    exit 1
}

if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$out/run.manifest.json" >/dev/null
fi

echo "[FORMAL] ok"
