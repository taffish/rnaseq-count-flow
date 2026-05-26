rnaseq-count-flow 0.1.0-r1

Purpose:
  Count RNA-seq reads from coordinate-sorted BAM files with featureCounts,
  then create a gene-level count matrix, featureCounts summaries, MultiQC,
  logs, commands, versions, methods, and a manifest under one output directory.

Flow family role:
  This is a TAFFISH RNA-seq subflow. It can be run directly from compatible
  BAM inputs, and its gene_counts.tsv matrix is intended for the optional
  alignment/count branch of future rnaseq-standard-flow orchestration.

Usage:
  taf-rnaseq-count-flow \
    --bams align-out/04_reports/bam_files.tsv \
    --annotation ref-out/03_results/annotation/genes.gtf \
    --outdir count-out \
    [options]

Required inputs:
  --bams PATH
      BAM sample table with sample_id and bam columns. Optional bai,
      condition, batch, and strandedness columns are accepted. Relative BAM
      and BAI paths are resolved from the BAM table directory.

  --annotation PATH
      Gene annotation for featureCounts. The original file is copied under
      00_inputs, and a local featureCounts annotation copy is prepared under
      02_intermediate. Missing target attributes can be filled from transcript
      metadata when possible.

Required output:
  --outdir PATH, -o PATH
      Output directory. The flow refuses to run if PATH already exists unless
      --force is used.

Common options:
  --threads N, -t N
      featureCounts threads. Default: 1.

  --strand MODE
      featureCounts strand mode. Accepted values: 0, 1, 2.
      0 means unstranded, 1 means stranded, 2 means reversely stranded.
      Default: 0.

  --feature-type NAME
      Feature type passed to featureCounts -t. Default: exon.

  --attribute NAME
      Annotation attribute passed to featureCounts -g. Default: gene_id.

  --min-mapq N
      featureCounts MAPQ threshold when N is greater than zero. Default: 0.

  --paired
      Enable featureCounts paired-end mode with -p and --countReadPairs.
      Default: off.

  --min-assigned-reads N
      Fail if total assigned reads are below N. Default: 0.

  --force
      Replace the standard rnaseq-count-flow outputs inside an existing
      output directory.

Output tree:
  <outdir>/00_inputs/bam_files.tsv
  <outdir>/00_inputs/genes.gtf
  <outdir>/00_inputs/input_files.tsv
  <outdir>/01_logs/flow.log
  <outdir>/01_logs/steps/01_validate_inputs.log
  <outdir>/01_logs/steps/02_featurecounts.log
  <outdir>/01_logs/steps/03_summarize_counts.log
  <outdir>/01_logs/steps/04_multiqc.log
  <outdir>/02_intermediate/featurecounts_annotation.gtf
  <outdir>/02_intermediate/featurecounts_annotation_stats.tsv
  <outdir>/02_intermediate/featurecounts_tmp/
  <outdir>/03_results/featurecounts/featureCounts.txt
  <outdir>/03_results/featurecounts/featureCounts.txt.summary
  <outdir>/03_results/matrices/gene_counts.tsv
  <outdir>/03_results/assignment_summary.tsv
  <outdir>/04_reports/count_summary.tsv
  <outdir>/04_reports/multiqc_report.html
  <outdir>/04_reports/commands.sh
  <outdir>/04_reports/versions.tsv
  <outdir>/04_reports/methods.txt
  <outdir>/04_reports/flow_summary.tsv
  <outdir>/run.manifest.json

Downstream:
  rnaseq-de-flow can use:
    --counts count-out/03_results/matrices/gene_counts.tsv

  rnaseq-report-flow can collect:
    --count-out count-out

Dependencies:
  taf-subread 2.1.1-r2
  taf-samtools 1.23.1-r1
  taf-multiqc 1.35-r2

Boundaries:
  r1 does not align reads, build indexes, run RSeQC or Qualimap, run DESeq2,
  perform enrichment, or infer biological design. It expects sorted BAM input
  and records the chosen featureCounts parameters for downstream review.
  It may normalize a local annotation copy for featureCounts, but it does not
  modify the input annotation.

Wrapper options:
  -h, --help       Show this help.
  -v, --version    Show package and command version.
  --compile        Print generated shell code instead of running it.
