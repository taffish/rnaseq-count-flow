# rnaseq-count-flow

`taf-rnaseq-count-flow` is the counting branch step for the TAFFISH RNA-seq
flow set. It reads a BAM sample table, validates coordinate-sorted BAM files
with SAMtools, runs featureCounts from Subread against a user-supplied gene
annotation, converts featureCounts output into a stable gene-level count
matrix, runs MultiQC, and writes logs, commands, versions, methods, summaries,
and a manifest under one explicit output directory.

Package identity:

- name: `rnaseq-count-flow`
- command: `taf-rnaseq-count-flow`
- kind: `flow`
- version: `0.1.0-r1`
- license: Apache-2.0

## RNA-seq Flow Position

This app is a reusable subflow in the TAFFISH bulk RNA-seq flow family. It can
be run directly from compatible coordinate-sorted BAM files and gene annotation,
and it is also intended to serve the optional alignment/count branch of the
future `rnaseq-standard-flow` umbrella. The umbrella should reuse this flow's
gene-count matrix contract rather than duplicate its featureCounts logic.

## Scope

r1 supports:

- BAM sample tables from `rnaseq-alignment-flow` or compatible upstream tools
- featureCounts gene-level counting with configurable strandness, feature type,
  attribute, MAPQ threshold, and paired-end mode
- SAMtools `quickcheck` validation before counting
- local featureCounts annotation preparation, including filling missing target
  attributes from transcript metadata when the target feature row lacks them
- featureCounts raw table and assignment summary preservation
- downstream `gene_counts.tsv` matrix with `gene_id` as the first column
- MultiQC report generation
- fixed output tree under `<outdir>/`
- input snapshots, step logs, `commands.sh`, `versions.tsv`, `methods.txt`,
  `count_summary.tsv`, `flow_summary.tsv`, and `run.manifest.json`

r1 deliberately does not align reads, build indexes, run RSeQC/Qualimap, run
DESeq2, perform enrichment, or infer biological design. Those are upstream or
downstream flow responsibilities.

## Dependencies

The flow depends on exact TAFFISH tool versions:

| Dependency | Version | Role |
| --- | --- | --- |
| `taf-subread` | `2.1.1-r2` | featureCounts read assignment |
| `taf-samtools` | `1.23.1-r1` | BAM integrity checks |
| `taf-multiqc` | `1.35-r2` | report aggregation |

The script also uses ordinary shell utilities such as `awk`, `sed`, `sort`,
`mkdir`, `cp`, `rm`, `date`, and `wc` for validation and bookkeeping. It does
not call host-installed Subread, SAMtools, or MultiQC.

## Usage

Count BAMs produced by `rnaseq-alignment-flow`:

```sh
taf-rnaseq-count-flow \
  --bams align-out/04_reports/bam_files.tsv \
  --annotation ref-out/03_results/annotation/genes.gtf \
  --outdir count-out \
  --threads 4 \
  --strand 0
```

Use paired-end featureCounts mode:

```sh
taf-rnaseq-count-flow \
  --bams bam_files.tsv \
  --annotation genes.gtf \
  --outdir count-out \
  --threads 8 \
  --strand 2 \
  --paired
```

The `--annotation` argument should usually be the standardized GTF produced by
`rnaseq-index-flow`:

```sh
--annotation ref-out/03_results/annotation/genes.gtf
```

## Parameters

Required:

- `--bams PATH`: BAM sample table.
- `--annotation PATH`: gene annotation readable by featureCounts. The original
  file is copied to `00_inputs/genes.gtf`; a local featureCounts-specific copy
  is prepared under `02_intermediate/` so target feature rows that lack
  `gene_id` can be completed from transcript metadata when possible.
- `--outdir PATH`, `-o PATH`: output directory. Existing directories are
  refused unless `--force` is used.

Common:

- `--threads N`, `-t N`: featureCounts threads. Default: `1`.
- `--strand 0|1|2`: featureCounts strand mode. `0` is unstranded, `1` is
  stranded, and `2` is reversely stranded. Default: `0`.
- `--feature-type NAME`: feature type passed to featureCounts `-t`.
  Default: `exon`.
- `--attribute NAME`: annotation attribute passed to featureCounts `-g`.
  Default: `gene_id`.
- `--min-mapq N`: featureCounts MAPQ threshold via `-Q` when greater than zero.
  Default: `0`.
- `--paired`: enable featureCounts paired-end mode using `-p --countReadPairs`.
  Default: off.
- `--min-assigned-reads N`: fail when total assigned reads are below this value.
  Default: `0`.
- `--force`: replace the standard rnaseq-count-flow outputs in an existing
  output directory.

## BAM Table

Minimum:

```text
sample_id	bam
S1	align-out/03_results/bam/S1.sorted.bam
S2	align-out/03_results/bam/S2.sorted.bam
```

With indexes and metadata:

```text
sample_id	bam	bai	condition	strandedness
S1	bam/S1.sorted.bam	bam/S1.sorted.bam.bai	control	unstranded
S2	bam/S2.sorted.bam	bam/S2.sorted.bam.bai	treated	unstranded
```

Rules:

- `sample_id` must be unique and contain only letters, digits, dot, underscore,
  or dash.
- `bam` is required and must point to a readable BAM file.
- Relative BAM and BAI paths are resolved relative to the BAM table location.
- `bai` is optional. If omitted, the flow accepts an existing `$bam.bai`.
- BAM files are validated with `samtools quickcheck` and are not modified.
- `condition`, `batch`, and `strandedness` columns are accepted for continuity
  with upstream metadata, but counting parameters are controlled explicitly by
  flow arguments.

## Outputs

All flow-created outputs are written under `<outdir>/`:

```text
<outdir>/
  00_inputs/
    bam_files.tsv
    genes.gtf
    input_files.tsv
  01_logs/
    flow.log
    steps/
      01_validate_inputs.log
      02_featurecounts.log
      03_summarize_counts.log
      04_multiqc.log
  02_intermediate/
    featurecounts_annotation.gtf
    featurecounts_annotation_stats.tsv
    featurecounts_tmp/
  03_results/
    featurecounts/
      featureCounts.txt
      featureCounts.txt.summary
    matrices/
      gene_counts.tsv
    assignment_summary.tsv
  04_reports/
    count_summary.tsv
    multiqc_report.html
    commands.sh
    versions.tsv
    methods.txt
    flow_summary.tsv
  run.manifest.json
```

Important files:

- `03_results/matrices/gene_counts.tsv`: downstream count matrix with
  `gene_id` and one column per sample.
- `02_intermediate/featurecounts_annotation.gtf`: local annotation copy used by
  featureCounts.
- `02_intermediate/featurecounts_annotation_stats.tsv`: count of target feature
  rows and any filled missing attributes.
- `03_results/featurecounts/featureCounts.txt`: raw featureCounts table.
- `03_results/featurecounts/featureCounts.txt.summary`: raw featureCounts
  assignment summary.
- `03_results/assignment_summary.tsv`: long-form status, sample, count table.
- `04_reports/count_summary.tsv`: sample count, gene count, assigned reads, and
  counting parameters.
- `04_reports/multiqc_report.html`: aggregated counting report.
- `04_reports/commands.sh`: exact dependency commands used.
- `run.manifest.json`: inputs, parameters, dependency versions, summary counts,
  and output paths.

## Downstream Connection

The DE flow can consume the matrix directly:

```sh
taf-rnaseq-de-flow \
  --counts count-out/03_results/matrices/gene_counts.tsv \
  --metadata metadata.tsv \
  --design '~ condition' \
  --contrast condition:treated:control \
  --outdir de-out
```

`rnaseq-report-flow` can collect this output directory with
`--count-out count-out`.

## Resource Notes

featureCounts runtime scales with BAM size, sample count, annotation size, and
thread count. The flow stores featureCounts temporary files under
`<outdir>/02_intermediate/featurecounts_tmp/` and does not write beside input
BAM files. For paired-end libraries, pass `--paired`; otherwise featureCounts
counts alignments as single reads.

Strandness is a biological library-preparation property, not an arbitrary
tuning knob. Use `--strand 0` for unstranded libraries, `--strand 1` for
forward-stranded libraries, and `--strand 2` for reverse-stranded libraries.
When unsure, confirm from the library protocol or from an RNA-seq QC step before
interpreting differential expression results.

## Boundaries

This flow converts existing aligned BAMs into gene-level counts. It does not
judge whether the alignment is biologically good enough, and it does not choose
DESeq2 design or contrasts. Use `rnaseq-alignment-flow` before this step,
`rnaseq-alignment-qc-flow` for deeper BAM/RNA-seq QC, and `rnaseq-de-flow` for
statistical testing.

Smoke builds two tiny BAM files from SAM fixtures and checks featureCounts,
MultiQC, provenance, existing-output refusal, `--force`, and output-directory
cleanliness. Formal testing chains central yeast reference and FASTQ data
through `rnaseq-index-flow`, `rnaseq-alignment-flow`, and this count flow. The
central data tree can be prepared with
`repos/apps/bio/flows/rna-seq/test-data/yeast/rnaseq-yeast-get-data`; downstream
formal tests read it via `TAFFISH_RNASEQ_TESTDATA` or the default local
`test-data/yeast/data/03_results` path.
