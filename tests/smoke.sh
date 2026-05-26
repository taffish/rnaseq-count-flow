#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
project_dir=$(CDPATH= cd "$script_dir/.." && pwd)
bio_apps_dir=$(CDPATH= cd "$project_dir/../../../.." && pwd)
index_flow_dir=$(CDPATH= cd "$project_dir/../rnaseq-index-flow" && pwd)
alignment_flow_dir=$(CDPATH= cd "$project_dir/../rnaseq-alignment-flow" && pwd)

for target_dir in \
    "$bio_apps_dir/tools/agat/target" \
    "$bio_apps_dir/tools/gffread/target" \
    "$bio_apps_dir/tools/hisat2/target" \
    "$bio_apps_dir/tools/kallisto/target" \
    "$bio_apps_dir/tools/fastp/target" \
    "$bio_apps_dir/tools/salmon/target" \
    "$bio_apps_dir/tools/subread/target" \
    "$bio_apps_dir/tools/samtools/target" \
    "$bio_apps_dir/tools/multiqc/target" \
    "$index_flow_dir/target" \
    "$alignment_flow_dir/target"
do
    if [ -d "$target_dir" ]; then
        PATH="$target_dir:$PATH"
    fi
done
export PATH

if ! command -v taf >/dev/null 2>&1; then
    echo "smoke: taf command not found in PATH." >&2
    exit 127
fi

if ! command -v taffish >/dev/null 2>&1; then
    echo "smoke: taffish command not found in PATH." >&2
    exit 127
fi

for dep in \
    taf-agat-v1.7.0-r1 \
    taf-gffread-v0.12.9-r1 \
    taf-hisat2-v2.2.2-r2 \
    taf-kallisto-v0.52.0-r1 \
    taf-fastp-v1.3.3-r3 \
    taf-salmon-v1.11.4-r1 \
    taf-subread-v2.1.1-r2 \
    taf-samtools-v1.23.1-r1 \
    taf-multiqc-v1.35-r2
do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "smoke: dependency wrapper not found in PATH: $dep" >&2
        exit 127
    fi
done

TAFFISH_CONTAINER_BACKEND=${TAFFISH_CONTAINER_BACKEND:-podman}
export TAFFISH_CONTAINER_BACKEND
TAF_HISTORY_MODE=${TAF_HISTORY_MODE:-off}
export TAF_HISTORY_MODE

tmpdir=$(mktemp -d "$project_dir/.taf-smoke.XXXXXX")
cleanup() {
    cd "$project_dir" 2>/dev/null || :
    rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM HUP

cd "$project_dir"

echo "[SMOKE] taf check"
taf check

echo "[SMOKE] taf build"
taf build

flow_cmd="$project_dir/target/taf-rnaseq-count-flow-v0.1.0-r1"
if [ ! -x "$flow_cmd" ]; then
    echo "smoke: built flow command is missing or not executable: $flow_cmd" >&2
    exit 1
fi

echo "[SMOKE] help and version"
"$flow_cmd" --help >/dev/null
"$flow_cmd" --version >/dev/null

run_dir="$tmpdir/run"
mkdir -p "$run_dir"

cat > "$run_dir/annotation.gtf" <<'EOF'
chrTiny	smoke	gene	1	180	.	+	.	gene_id "geneTiny";
chrTiny	smoke	transcript	1	180	.	+	.	gene_id "geneTiny"; transcript_id "txTiny";
chrTiny	smoke	exon	1	180	.	+	.	gene_id "geneTiny"; transcript_id "txTiny"; exon_number "1";
EOF

echo "[SMOKE] build upstream rnaseq-index-flow"
(
    cd "$index_flow_dir"
    taf check
    taf build
)
index_flow_cmd="$index_flow_dir/target/taf-rnaseq-index-flow-v0.1.0-r1"
if [ ! -x "$index_flow_cmd" ]; then
    echo "smoke: built index flow command is missing or not executable: $index_flow_cmd" >&2
    exit 1
fi

echo "[SMOKE] build upstream rnaseq-alignment-flow"
(
    cd "$alignment_flow_dir"
    taf check
    taf build
)
alignment_flow_cmd="$alignment_flow_dir/target/taf-rnaseq-alignment-flow-v0.1.0-r1"
if [ ! -x "$alignment_flow_cmd" ]; then
    echo "smoke: built alignment flow command is missing or not executable: $alignment_flow_cmd" >&2
    exit 1
fi

echo "[SMOKE] setup HISAT2 index via rnaseq-index-flow target"
(
    cd "$run_dir"
    "$index_flow_cmd" \
        --genome "$alignment_flow_dir/testdata/genome.fa" \
        --annotation "$run_dir/annotation.gtf" \
        --outdir ref-out \
        --threads 1 \
        --indexer salmon \
        --genome-indexer hisat2 \
        --kmer 15
)
test -s "$run_dir/ref-out/03_results/hisat2_index/genome.1.ht2"

echo "[SMOKE] setup BAMs via rnaseq-alignment-flow target"
(
    cd "$run_dir"
    "$alignment_flow_cmd" \
        --samples "$alignment_flow_dir/testdata/samples.tsv" \
        --index "$run_dir/ref-out/03_results/hisat2_index/genome" \
        --outdir align-out \
        --threads 1
)
test -s "$run_dir/align-out/04_reports/bam_files.tsv"
awk -F '\t' 'NR == 1 || $1 == "tiny_se"' "$run_dir/align-out/04_reports/bam_files.tsv" > "$run_dir/count_bam_files.tsv"
test -s "$run_dir/count_bam_files.tsv"

echo "[SMOKE] rnaseq-count-flow tiny fixture"
(
    cd "$run_dir"
    "$flow_cmd" \
        --bams "$run_dir/count_bam_files.tsv" \
        --annotation "$run_dir/annotation.gtf" \
        --outdir count-out \
        --threads 1 \
        --strand 0 \
        --min-assigned-reads 1
)
cd "$project_dir"

out="$run_dir/count-out"

echo "[SMOKE] output checks"
test -s "$out/00_inputs/bam_files.tsv"
test -s "$out/00_inputs/genes.gtf"
test -s "$out/00_inputs/input_files.tsv"
test -s "$out/01_logs/flow.log"
test -s "$out/01_logs/steps/01_validate_inputs.log"
test -s "$out/01_logs/steps/02_featurecounts.log"
test -s "$out/01_logs/steps/03_summarize_counts.log"
test -s "$out/01_logs/steps/04_multiqc.log"
test -s "$out/02_intermediate/featurecounts_annotation.gtf"
test -s "$out/02_intermediate/featurecounts_annotation_stats.tsv"
test -s "$out/03_results/featurecounts/featureCounts.txt"
test -s "$out/03_results/featurecounts/featureCounts.txt.summary"
test -s "$out/03_results/matrices/gene_counts.tsv"
test -s "$out/03_results/assignment_summary.tsv"
test -s "$out/04_reports/count_summary.tsv"
test -s "$out/04_reports/multiqc_report.html"
test -s "$out/04_reports/commands.sh"
test -s "$out/04_reports/versions.tsv"
test -s "$out/04_reports/methods.txt"
test -s "$out/04_reports/flow_summary.tsv"
test -s "$out/run.manifest.json"

grep -F 'gene_id	tiny_se' "$out/03_results/matrices/gene_counts.tsv" >/dev/null
grep -F 'geneTiny' "$out/03_results/matrices/gene_counts.tsv" >/dev/null
awk -F '\t' '$1 == "geneTiny" { found = 1; if ($2 < 1) exit 2 } END { exit !found }' "$out/03_results/matrices/gene_counts.tsv"
awk -F '\t' '$1 == "Assigned" { total += $3 } END { exit !(total >= 1) }' "$out/03_results/assignment_summary.tsv"
grep -F 'taf-subread-v2.1.1-r2' "$out/04_reports/commands.sh" >/dev/null
grep -F 'taf-multiqc-v1.35-r2' "$out/04_reports/commands.sh" >/dev/null
grep -F 'taf-subread	2.1.1-r2' "$out/04_reports/versions.tsv" >/dev/null
grep -F 'sample_count	1' "$out/04_reports/flow_summary.tsv" >/dev/null
awk -F '\t' '$1 == "assigned_reads" && $2 >= 1 { found = 1 } END { exit !found }' "$out/04_reports/flow_summary.tsv"
grep -F 'filled_missing_attribute	0' "$out/04_reports/flow_summary.tsv" >/dev/null
grep -F '"flow": "rnaseq-count-flow"' "$out/run.manifest.json" >/dev/null
if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$out/run.manifest.json" >/dev/null
fi

echo "[SMOKE] existing outdir is refused"
if (
    cd "$run_dir"
    "$flow_cmd" \
        --bams "$run_dir/count_bam_files.tsv" \
        --annotation "$run_dir/annotation.gtf" \
        --outdir count-out
) >/dev/null 2>&1; then
    echo "smoke: existing outdir was not refused." >&2
    exit 1
fi

echo "[SMOKE] --force rerun with MAPQ filter"
(
    cd "$run_dir"
    "$flow_cmd" \
        --bams "$run_dir/count_bam_files.tsv" \
        --annotation "$run_dir/annotation.gtf" \
        --outdir count-out \
        --threads 1 \
        --strand 0 \
        --min-mapq 10 \
        --min-assigned-reads 1 \
        --force
)
test -s "$out/03_results/matrices/gene_counts.tsv"
grep -F 'min_mapq	10' "$out/04_reports/flow_summary.tsv" >/dev/null

stray=$(find "$run_dir" -mindepth 1 -maxdepth 1 ! -name ref-out ! -name align-out ! -name annotation.gtf ! -name count_bam_files.tsv ! -name count-out -print)
if [ -n "$stray" ]; then
    echo "smoke: flow wrote unexpected files outside outdir:" >&2
    printf '%s\n' "$stray" >&2
    exit 1
fi

echo "[SMOKE] ok"
