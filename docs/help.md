rnaseq-count-flow 0.2.0-r1

Purpose:
  Count RNA-seq reads from coordinate-sorted BAM files with featureCounts,
  then create a gene-level count matrix, featureCounts summaries, MultiQC,
  logs, commands, versions, methods, and a manifest under one output directory.

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

Key outputs:
  <outdir>/03_results/matrices/gene_counts.tsv
      Gene-level count matrix for DE workflows.

  <outdir>/03_results/featurecounts/featureCounts.txt
      Raw featureCounts table.

  <outdir>/03_results/featurecounts/featureCounts.txt.summary
      Raw featureCounts assignment summary.

  <outdir>/03_results/assignment_summary.tsv
      Long-form assignment summary.

  <outdir>/04_reports/count_summary.tsv
      Compact counting summary.

  <outdir>/04_reports/
      multiqc_report.html, commands.sh, versions.tsv, methods.txt,
      flow_summary.tsv, and provenance.

Upstream/downstream:
  Upstream:
    rnaseq-alignment-flow provides bam_files.tsv.
    rnaseq-index-flow provides annotation/genes.gtf.

  Downstream:
    rnaseq-de-flow can use gene_counts.tsv.
    rnaseq-report-flow can collect the count output directory.

Advanced step passthrough:
  Optional expert slots for native tool parameters. They default to empty
  and are not needed for normal use.

  @samtools-quickcheck-step: ... @: samtools quickcheck for input BAM.
  @featurecounts-step: ... @: featureCounts read counting.
  @multiqc-step: ... @: MultiQC report generation.

Boundaries:
  r1 does not align reads, build indexes, run RSeQC or Qualimap, run DESeq2,
  perform enrichment, or infer biological design. It expects sorted BAM input
  and records the chosen featureCounts parameters for downstream review.
  It may normalize a local annotation copy for featureCounts, but it does not
  modify the input annotation.

Detailed documentation:
  https://github.com/taffish/rnaseq-count-flow

Wrapper options:
  -h, --help       Show this help.
  -v, --version    Show package and command version.
  --compile        Print generated shell code instead of running it.
