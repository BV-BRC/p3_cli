// Command p3-get-genome-data retrieves genome data for genome IDs from stdin.
//
// This command reads genome IDs from the standard input and retrieves the
// corresponding genome data from the BV-BRC database.
//
// Usage:
//
//	p3-get-genome-data [options] < genome_ids.txt
//
// Examples:
//
//	# Get genome data for IDs in a file
//	p3-get-genome-data < genome_ids.txt
//
//	# Get specific fields
//	p3-get-genome-data -a genome_name -a genome_length < genome_ids.txt
//
//	# Use a specific column from input
//	p3-get-genome-data --col 2 < input.txt
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
	dataOpts cli.DataOptions
	colOpts  cli.ColOptions
	ioOpts   cli.IOOptions
)

var rootCmd = &cobra.Command{
	Use:   "p3-get-genome-data",
	Short: "Return genome data for genome IDs from stdin",
	Long: `This script reads genome IDs from the standard input and returns
corresponding genome data from the BV-BRC database.

The input should be tab-delimited with genome IDs in the specified column
(default: last column). The output includes the original input columns
plus the requested genome data fields.

Examples:

  # Get genome data for IDs in a file
  p3-get-genome-data < genome_ids.txt

  # Get specific fields
  p3-get-genome-data -a genome_name -a genome_length < genome_ids.txt

  # Use a specific column from input
  p3-get-genome-data --col 2 < input.txt`,
	RunE: run,
}

func init() {
	cli.AddDataFlags(rootCmd, &dataOpts)
	cli.AddColFlags(rootCmd, &colOpts, 100)
	cli.AddIOFlags(rootCmd, &ioOpts)
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
		fields, err := client.GetSchema(ctx, "genome")
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

	// Get default fields for genome object
	defaultFields := api.GetDefaultFields("genome")
	fields := dataOpts.GetSelectFields(defaultFields)

	// Ensure genome_id is in the select list for result association
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
	}
	for _, f := range fields {
		outputHeaders = append(outputHeaders, "genome."+f)
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

		// Build query with IN filter for the batch of keys
		query, err := dataOpts.BuildQueryWithFields(selectFields)
		if err != nil {
			return fmt.Errorf("building query: %w", err)
		}
		query.In("genome_id", keys...)

		// Execute query
		results, err := client.Query(ctx, "genome", query)
		if err != nil {
			return fmt.Errorf("querying genomes: %w", err)
		}

		// Build lookup map from results
		resultMap := make(map[string]map[string]any)
		for _, r := range results {
			if id, ok := r["genome_id"].(string); ok {
				resultMap[id] = r
			}
		}

		// Output results in input order
		for i, key := range keys {
			var outRow []string
			outRow = append(outRow, rows[i]...)

			if result, ok := resultMap[key]; ok {
				for _, f := range fields {
					outRow = append(outRow, cli.FormatValue(result[f], delim))
				}
			} else {
				// No result found - add empty fields
				for range fields {
					outRow = append(outRow, "")
				}
			}

			if err := writer.WriteRow(outRow...); err != nil {
				return fmt.Errorf("writing row: %w", err)
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
