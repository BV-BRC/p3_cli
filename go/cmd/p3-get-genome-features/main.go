// Command p3-get-genome-features retrieves features for genome IDs from stdin.
//
// This command reads genome IDs from the standard input and retrieves the
// corresponding features from the BV-BRC database.
//
// Usage:
//
//	p3-get-genome-features [options] < genome_ids.txt
//
// Examples:
//
//	# Get all features for genomes in a file
//	p3-get-genome-features < genome_ids.txt
//
//	# Get only CDS features
//	p3-get-genome-features --eq feature_type,CDS < genome_ids.txt
//
//	# Get specific fields
//	p3-get-genome-features -a patric_id -a product -a aa_length < genome_ids.txt
package main

import (
	"context"
	"fmt"
	"io"
	"os"

	"github.com/BV-BRC/bvbrc/pkg/api"
	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/BV-BRC/bvbrc/pkg/cli"
	"github.com/spf13/cobra"
)

var (
	dataOpts  cli.DataOptions
	colOpts   cli.ColOptions
	ioOpts    cli.IOOptions
	selective bool
)

var rootCmd = &cobra.Command{
	Use:   "p3-get-genome-features",
	Short: "Return features for genome IDs from stdin",
	Long: `This script reads genome IDs from the standard input and returns
the features belonging to those genomes from the BV-BRC database.

The input should be tab-delimited with genome IDs in the specified column
(default: last column). The output includes the genome ID plus the
requested feature data fields.

Examples:

  # Get all features for genomes in a file
  p3-get-genome-features < genome_ids.txt

  # Get only CDS features
  p3-get-genome-features --eq feature_type,CDS < genome_ids.txt

  # Get specific fields
  p3-get-genome-features -a patric_id -a product -a aa_length < genome_ids.txt`,
	RunE: run,
}

func init() {
	cli.AddDataFlags(rootCmd, &dataOpts)
	cli.AddColFlags(rootCmd, &colOpts, 100)
	cli.AddIOFlags(rootCmd, &ioOpts)
	rootCmd.Flags().BoolVar(&selective, "selective", false,
		"use batch query (more efficient for small feature counts per genome)")
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
	if dataOpts.Debug {
		clientOpts = append(clientOpts, api.WithDebug(true))
	}
	client := api.NewClient(clientOpts...)

	// Handle --fields option
	if dataOpts.Fields {
		fields, err := client.GetSchema(ctx, "feature")
		if err != nil {
			return fmt.Errorf("getting schema: %w", err)
		}
		for _, f := range fields {
			if f.MultiValued {
				fmt.Printf("%s (multi)\n", f.Name)
			} else {
				fmt.Println(f.Name)
			}
		}
		return nil
	}

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

	// Create tab reader/writer
	reader := cli.NewTabReader(inFile, !colOpts.NoHead)
	writer := cli.NewTabWriter(outFile)
	defer writer.Flush()

	// Read headers and find key column
	inputHeaders, err := reader.Headers()
	if err != nil {
		return fmt.Errorf("reading headers: %w", err)
	}

	keyCol, err := reader.FindColumn(colOpts.Col)
	if err != nil {
		return fmt.Errorf("finding key column: %w", err)
	}

	// Get default fields for feature object
	defaultFields := api.GetDefaultFields("feature")
	fields := dataOpts.GetSelectFields(defaultFields)

	// Ensure genome_id is in the select list for output association
	hasGenomeID := false
	for _, f := range fields {
		if f == "genome_id" {
			hasGenomeID = true
			break
		}
	}
	selectFields := fields
	if !hasGenomeID {
		selectFields = append([]string{"genome_id"}, fields...)
	}

	// Write output headers
	var outputHeaders []string
	if inputHeaders != nil {
		outputHeaders = append(outputHeaders, inputHeaders...)
	} else {
		outputHeaders = append(outputHeaders, "genome.genome_id")
	}
	for _, f := range fields {
		outputHeaders = append(outputHeaders, "feature."+f)
	}
	if err := writer.WriteHeaders(outputHeaders); err != nil {
		return fmt.Errorf("writing headers: %w", err)
	}

	// Get delimiter for multi-valued fields
	delim := ioOpts.GetDelimiter()

	// Process in batches
	for {
		keys, rows, err := reader.ReadBatch(colOpts.BatchSize, keyCol)
		if err != nil && err != io.EOF {
			return fmt.Errorf("reading batch: %w", err)
		}
		if len(keys) == 0 {
			break
		}

		// Build a map of genome_id -> input row for later association
		rowMap := make(map[string][]string)
		for i, key := range keys {
			rowMap[key] = rows[i]
		}

		if selective {
			// Batch query - more efficient for small feature counts per genome
			query, err := dataOpts.BuildQueryWithFields(selectFields)
			if err != nil {
				return fmt.Errorf("building query: %w", err)
			}
			query.In("genome_id", keys...)

			results, err := client.Query(ctx, "feature", query)
			if err != nil {
				return fmt.Errorf("querying features: %w", err)
			}

			// Output results
			for _, result := range results {
				genomeID, _ := result["genome_id"].(string)
				inputRow := rowMap[genomeID]
				if inputRow == nil {
					// No matching input row, use genome_id only
					inputRow = []string{genomeID}
				}

				var outRow []string
				outRow = append(outRow, inputRow...)
				for _, f := range fields {
					outRow = append(outRow, cli.FormatValue(result[f], delim))
				}

				if err := writer.WriteRow(outRow...); err != nil {
					return fmt.Errorf("writing row: %w", err)
				}
			}
		} else {
			// Standard query - one query per genome (better for large feature counts)
			for _, key := range keys {
				query, err := dataOpts.BuildQueryWithFields(selectFields)
				if err != nil {
					return fmt.Errorf("building query: %w", err)
				}
				query.Eq("genome_id", key)

				inputRow := rowMap[key]

				err = client.QueryCallback(ctx, "feature", query, func(records []map[string]any, info *api.ChunkInfo) bool {
					for _, record := range records {
						var outRow []string
						outRow = append(outRow, inputRow...)
						for _, f := range fields {
							outRow = append(outRow, cli.FormatValue(record[f], delim))
						}

						if err := writer.WriteRow(outRow...); err != nil {
							fmt.Fprintf(os.Stderr, "Error writing row: %v\n", err)
							return false
						}
					}
					return true
				})
				if err != nil {
					return fmt.Errorf("querying features for genome %s: %w", key, err)
				}
			}
		}
	}

	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
