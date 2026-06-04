// Command p3-get-feature-sequence retrieves sequences for feature IDs from stdin.
//
// This command reads feature IDs from the standard input and retrieves the
// corresponding sequences from the BV-BRC database in FASTA format.
//
// Usage:
//
//	p3-get-feature-sequence [options] < feature_ids.txt
//
// Examples:
//
//	# Get protein sequences (default)
//	p3-get-feature-sequence < feature_ids.txt
//
//	# Get DNA sequences
//	p3-get-feature-sequence --dna < feature_ids.txt
//
//	# Use a specific column from input
//	p3-get-feature-sequence --col 2 < input.txt
package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/api"
	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/BV-BRC/bvbrc/pkg/cli"
	"github.com/spf13/cobra"
)

var (
	colOpts cli.ColOptions
	ioOpts  cli.IOOptions
	dnaMode bool
	debug   bool
)

var rootCmd = &cobra.Command{
	Use:   "p3-get-feature-sequence",
	Short: "Return sequences for feature IDs from stdin in FASTA format",
	Long: `This script reads feature IDs from the standard input and returns
the corresponding sequences from the BV-BRC database in FASTA format.

By default, protein (amino acid) sequences are returned. Use --dna to
get nucleotide sequences instead.

The input should be tab-delimited with feature IDs (patric_id) in the
specified column (default: last column).

Examples:

  # Get protein sequences (default)
  p3-get-feature-sequence < feature_ids.txt

  # Get DNA sequences
  p3-get-feature-sequence --dna < feature_ids.txt

  # Use a specific column from input
  p3-get-feature-sequence --col 2 < input.txt`,
	RunE: run,
}

func init() {
	cli.AddColFlags(rootCmd, &colOpts, 100)
	cli.AddIOFlags(rootCmd, &ioOpts)
	rootCmd.Flags().BoolVar(&dnaMode, "dna", false, "retrieve DNA sequences instead of protein")
	rootCmd.Flags().BoolVar(&dnaMode, "protein", false, "retrieve protein sequences (default)")
	_ = rootCmd.Flags().MarkHidden("protein") // protein is default, just here for compatibility
	rootCmd.Flags().BoolVar(&debug, "debug", false, "enable debug output")
}

func run(cmd *cobra.Command, args []string) error {
	ctx := context.Background()

	// Get optional authentication token
	token, _ := auth.GetToken()

	// Create API client
	clientOpts := []api.ClientOption{}
	if token != nil {
		clientOpts = append(clientOpts, api.WithToken(token))
	}
	if debug {
		clientOpts = append(clientOpts, api.WithDebug(true))
	}
	client := api.NewClient(clientOpts...)

	// Open input
	inFile, err := cli.OpenInput(ioOpts.Input)
	if err != nil {
		return fmt.Errorf("opening input: %w", err)
	}
	defer inFile.Close()

	// Open output
	outFile, err := cli.OpenOutput(ioOpts.Output)
	if err != nil {
		return fmt.Errorf("opening output: %w", err)
	}
	defer outFile.Close()

	// Create tab reader
	reader := cli.NewTabReader(inFile, !colOpts.NoHead)

	// Read headers and find key column
	_, err = reader.Headers()
	if err != nil {
		return fmt.Errorf("reading headers: %w", err)
	}

	keyCol, err := reader.FindColumn(colOpts.Col)
	if err != nil {
		return fmt.Errorf("finding key column: %w", err)
	}

	// Determine which sequence MD5 field to use
	md5Field := "aa_sequence_md5"
	if dnaMode {
		md5Field = "na_sequence_md5"
	}

	// Fields to retrieve from feature table
	featureFields := []string{"patric_id", "product", md5Field}

	// Process in batches
	for {
		keys, _, err := reader.ReadBatch(colOpts.BatchSize, keyCol)
		if err != nil && err != io.EOF {
			return fmt.Errorf("reading batch: %w", err)
		}
		if len(keys) == 0 {
			break
		}

		// Step 1: Get feature info including sequence MD5
		query := api.NewQuery().Select(featureFields...).In("patric_id", keys...)
		features, err := client.Query(ctx, "feature", query)
		if err != nil {
			return fmt.Errorf("querying features: %w", err)
		}

		// Build map of patric_id -> feature info and collect MD5s
		featureMap := make(map[string]map[string]any)
		var md5s []string
		md5ToFeature := make(map[string][]string) // md5 -> list of patric_ids

		for _, f := range features {
			id, _ := f["patric_id"].(string)
			if id == "" {
				continue
			}
			featureMap[id] = f

			md5, _ := f[md5Field].(string)
			if md5 != "" {
				md5ToFeature[md5] = append(md5ToFeature[md5], id)
				md5s = append(md5s, md5)
			}
		}

		if len(md5s) == 0 {
			continue
		}

		// Step 2: Get sequences from feature_sequence table
		seqQuery := api.NewQuery().Select("md5", "sequence").In("md5", md5s...)
		sequences, err := client.Query(ctx, "feature_sequence", seqQuery)
		if err != nil {
			return fmt.Errorf("querying sequences: %w", err)
		}

		// Build map of md5 -> sequence
		seqMap := make(map[string]string)
		for _, s := range sequences {
			md5, _ := s["md5"].(string)
			seq, _ := s["sequence"].(string)
			if md5 != "" && seq != "" {
				seqMap[md5] = seq
			}
		}

		// Output results in FASTA format, in input order
		for _, key := range keys {
			feature, ok := featureMap[key]
			if !ok {
				continue // Skip missing features
			}

			md5, _ := feature[md5Field].(string)
			if md5 == "" {
				continue // Skip features without sequence MD5
			}

			seq, ok := seqMap[md5]
			if !ok || seq == "" {
				continue // Skip features without sequences
			}

			// Get product annotation
			product, _ := feature["product"].(string)

			// Write FASTA entry
			fmt.Fprintf(outFile, ">%s %s\n%s\n", key, product, strings.ToUpper(seq))
		}
	}

	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
