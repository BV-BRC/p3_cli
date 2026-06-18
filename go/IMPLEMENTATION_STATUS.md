# BV-BRC CLI Go Port - Implementation Status

**Last Updated:** 2026-02-04

## Overview

This document tracks the progress of porting the BV-BRC Perl CLI to Go.

## Phase 1: Foundation Library - COMPLETE ✓

### Core Packages

| Package | Status | Description |
|---------|--------|-------------|
| `pkg/api/client.go` | ✓ Complete | API client with Query, Count, Stream, QueryCallback, GetByID |
| `pkg/api/query.go` | ✓ Complete | Query builder with filters, select, sort, limit |
| `pkg/api/objects.go` | ✓ Complete | Object type mappings, default fields, ID columns |
| `pkg/auth/token.go` | ✓ Complete | Token resolution chain (env vars, file) |
| `pkg/cli/options.go` | ✓ Complete | Standard CLI flags (DataOptions, ColOptions, IOOptions) |
| `pkg/cli/tabular.go` | ✓ Complete | Tab-delimited I/O (TabReader, TabWriter) |
| `pkg/types/types.go` | ✓ Complete | Common type definitions |

### Key Features Implemented

- Functional options pattern for client configuration
- Automatic pagination with chunked requests
- Retry logic with exponential backoff
- Content-Range header parsing for counts
- URL encoding for special characters (|, &, etc.)
- Object type alias resolution (feature → genome_feature)
- Two-step sequence lookup via MD5 hash

## Phase 2: CLI Commands

### Tier 1: Core Data Query Commands - COMPLETE ✓

| Command | Status | Description |
|---------|--------|-------------|
| `p3-all-genomes` | ✓ Complete | Enumerate all genomes with filters |
| `p3-all-features` | ✓ Complete | Enumerate all features with filters |
| `p3-get-genome-data` | ✓ Complete | Look up genome data by genome IDs from stdin |
| `p3-get-feature-data` | ✓ Complete | Look up feature data by feature IDs from stdin |
| `p3-get-genome-features` | ✓ Complete | Get features for genome IDs from stdin |
| `p3-get-feature-sequence` | ✓ Complete | Get sequences in FASTA format |

### Tier 2: Data Manipulation Commands - COMPLETE ✓

| Command | Status | Description |
|---------|--------|-------------|
| `p3-head` | ✓ Complete | Output first N lines |
| `p3-tail` | ✓ Complete | Output last N lines |
| `p3-count` | ✓ Complete | Count distinct values in a column |
| `p3-extract` | ✓ Complete | Select/exclude columns |
| `p3-match` | ✓ Complete | Filter rows by pattern matching |
| `p3-sort` | ✓ Complete | Sort by columns (numeric, string, PEG order) |
| `p3-join` | ✓ Complete | Join two files on a key column |

### Tier 3: Workspace Commands - COMPLETE ✓

| Command | Status | Description |
|---------|--------|-------------|
| `p3-ls` | ✓ Complete | List workspace files/directories |
| `p3-cp` | ✓ Complete | Copy files between local and workspace |
| `p3-mkdir` | ✓ Complete | Create directory in workspace |
| `p3-rm` | ✓ Complete | Remove files/directories from workspace |
| `p3-cat` | ✓ Complete | Display workspace file contents |

**Implementation Notes:**
- Created `pkg/workspace/client.go` with JSON-RPC client for Workspace service
- Supports ls, get, create, delete, copy operations
- Handles both inline data and Shock-stored files
- `p3-ls` supports long format, sorting, column output
- `p3-cp` supports local↔workspace and workspace↔workspace copies
- `p3-rm` supports recursive directory deletion

### Tier 4: Job Submission Commands - COMPLETE ✓

| Command | Status | Description |
|---------|--------|-------------|
| `p3-job-status` | ✓ Complete | Check job status, get stdout/stderr |
| `p3-submit-genome-annotation` | ✓ Complete | Submit genome annotation job |
| `p3-submit-genome-assembly` | ✓ Complete | Submit genome assembly job |
| `p3-submit-BLAST` | ✓ Complete | Submit BLAST search job |
| `p3-submit-MSA` | ✓ Complete | Submit multiple sequence alignment job |
| `p3-submit-codon-tree` | ✓ Complete | Submit phylogenetic codon tree job |
| `p3-submit-gene-tree` | ✓ Complete | Submit gene phylogeny tree job |
| `p3-submit-rnaseq` | ✓ Complete | Submit RNA-Seq processing job |
| `p3-submit-taxonomic-classification` | ✓ Complete | Submit taxonomic classification job |
| `p3-submit-fastqutils` | ✓ Complete | Submit FASTQ utilities job |
| `p3-submit-CGA` | ✓ Complete | Submit Comprehensive Genome Analysis job |
| `p3-submit-variation-analysis` | ✓ Complete | Submit variation analysis job |
| `p3-submit-proteome-comparison` | ✓ Complete | Submit proteome comparison job |
| `p3-submit-metagenome-binning` | ✓ Complete | Submit metagenome binning job |
| `p3-submit-metagenomic-read-mapping` | ✓ Complete | Submit metagenomic read mapping job |
| `p3-submit-viral-assembly` | ✓ Complete | Submit viral assembly job |
| `p3-submit-sars2-assembly` | ✓ Complete | Submit SARS-CoV-2 assembly job |
| `p3-submit-SubspeciesClassification` | ✓ Complete | Submit subspecies classification job |
| `p3-submit-comparative-systems` | ✓ Complete | Submit comparative systems job |
| `p3-submit-wastewater-analysis` | ✓ Complete | Submit wastewater analysis job |

**Implementation Notes:**
- Created `pkg/appservice/client.go` with JSON-RPC client for AppService
- Supports start_app, start_app2, query_tasks, query_task_details, enumerate_tasks
- All 19 submit commands implemented covering the full range of BV-BRC analysis services
- Each command supports workspace paths (`ws:` prefix), local file uploads, and dry-run mode
- Consistent error handling and parameter validation across all commands

### Tier 5: Specialized Analysis Commands - NOT STARTED

Complex logic, implement last.

### Authentication Commands (from p3_auth) - COMPLETE ✓

| Command | Status | Description |
|---------|--------|-------------|
| `p3-login` | ✓ Complete | Login to BV-BRC, save token to ~/.patric_token |
| `p3-logout` | ✓ Complete | Remove token file |
| `p3-whoami` | ✓ Complete | Display current logged-in user |

**Implementation Notes:**
- `p3-login` supports:
  - Password input with masked echo (using golang.org/x/term)
  - HTTP POST to BV-BRC authentication endpoint
  - Token validation and saving to `~/.patric_token` with mode 0600
  - `--rast` flag for RAST login
  - `--status` and `--logout` flags for convenience
  - Up to 3 login attempts before failing
- `p3-logout` deletes the token file if present
- `p3-whoami` reads and parses the token to extract username, distinguishing BV-BRC vs RAST users

## Build Information

### Build Command

```bash
cd /home/olson/P3/dev-ubuntu/modules/p3_cli/go
/home/olson/P3/go-1.25.6/go/bin/go build -buildvcs=false -ldflags="-s -w" -o bin/ ./cmd/...
```

### Binary Sizes (stripped)

- Each command: ~8MB
- Total for 6 Tier 1 commands: ~48MB

### Test Command

```bash
/home/olson/P3/go-1.25.6/go/bin/go test ./...
```

All tests pass.

## Usage Examples

```bash
# Get genomes from a specific genus
p3-all-genomes --eq genus,Streptomyces --limit 10 -a genome_id -a genome_name

# Count features for a genome
p3-all-features --eq genome_id,83332.12 --count

# Get genome data for IDs from stdin
printf "genome_id\n83332.12\n" | p3-get-genome-data -a genome_name -a contigs

# Get feature data
printf "patric_id\nfig|83332.12.peg.1\n" | p3-get-feature-data -a product -a aa_length

# Get protein sequences in FASTA format
printf "patric_id\nfig|83332.12.peg.1\nfig|83332.12.peg.2\n" | p3-get-feature-sequence

# Get DNA sequences
printf "patric_id\nfig|83332.12.peg.1\n" | p3-get-feature-sequence --dna
```

## Known Issues

1. **StringArrayVar vs StringSliceVar**: Filter flags use StringArrayVar to prevent comma splitting in values like `--eq field,value`.

2. **Sequence fields**: The `aa_sequence` and `na_sequence` fields are not directly on the feature record. They require a two-step lookup via MD5 hash to the `feature_sequence` table.

## Next Steps

1. Implement Tier 5 specialized analysis commands if needed
2. Add integration tests comparing Perl and Go output
3. Performance testing and optimization
