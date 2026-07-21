// Command p3-get-feature-data retrieves feature data for feature IDs from stdin.
//
// This command reads feature IDs from the standard input and retrieves the
// corresponding feature data from the BV-BRC database.
//
// Usage:
//
//	p3-get-feature-data [options] < feature_ids.txt
//
// Examples:
//
//	# Get feature data for IDs in a file
//	p3-get-feature-data < feature_ids.txt
//
//	# Get specific fields
//	p3-get-feature-data -a product -a aa_length -a start -a end < feature_ids.txt
//
//	# Use a specific column from input
//	p3-get-feature-data --col 2 < input.txt
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
	Use:   "p3-get-feature-data",
	Short: "Return feature data for feature IDs from stdin",
	Long: `This script reads feature IDs from the standard input and returns
corresponding feature data from the BV-BRC database.

The input should be tab-delimited with feature IDs (patric_id) in the
specified column (default: last column). The output includes the original
input columns plus the requested feature data fields.

Examples:

  # Get feature data for IDs in a file
  p3-get-feature-data < feature_ids.txt

  # Get specific fields
  p3-get-feature-data -a product -a aa_length -a start -a end < feature_ids.txt

  # Use a specific column from input
  p3-get-feature-data --col 2 < input.txt`,
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

	// Ensure patric_id is in the select list for result association
	hasPatricID := false
	for _, f := range fields {
		if f == "patric_id" {
			hasPatricID = true
			break
		}
	}
	selectFields := fields
	if !hasPatricID {
		selectFields = append([]string{"patric_id"}, fields...)
	}

	// Write output headers
	var outputHeaders []string
	if inputHeaders != nil {
		outputHeaders = append(outputHeaders, inputHeaders...)
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

		// Build query with IN filter for the batch of keys
		query, err := dataOpts.BuildQueryWithFields(selectFields)
		if err != nil {
			return fmt.Errorf("building query: %w", err)
		}
		query.In("patric_id", keys...)

		// Execute query
		results, err := client.Query(ctx, "feature", query)
		if err != nil {
			return fmt.Errorf("querying features: %w", err)
		}

		// Build lookup map from results
		resultMap := make(map[string]map[string]any)
		for _, r := range results {
			if id, ok := r["patric_id"].(string); ok {
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
