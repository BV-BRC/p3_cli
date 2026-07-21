// Command p3-count counts distinct values in a column.
//
// Usage:
//
//	p3-count [options] [file]
//
// Examples:
//
//	p3-count < data.txt
//	p3-count -c 2 data.txt
//	p3-count --col genome_id data.txt
package main

import (
	"fmt"
	"io"
	"os"

	"github.com/BV-BRC/bvbrc/pkg/cli"
	"github.com/spf13/cobra"
)

var (
	colOpts cli.ColOptions
)

var rootCmd = &cobra.Command{
	Use:   "p3-count [file]",
	Short: "Count distinct values in a column",
	Long: `This command counts the number of distinct values in a specified column
of a tab-delimited file.

Examples:

  # Count distinct values in last column
  p3-count < data.txt

  # Count distinct values in column 2
  p3-count -c 2 data.txt

  # Count distinct values in named column
  p3-count --col genome_id data.txt`,
	Args: cobra.MaximumNArgs(1),
	RunE: run,
}

func init() {
	cli.AddColFlags(rootCmd, &colOpts, 0)
}

func run(cmd *cobra.Command, args []string) error {
	// Open input
	var inFile *os.File
	var err error
	if len(args) > 0 && args[0] != "-" {
		inFile, err = os.Open(args[0])
		if err != nil {
			return fmt.Errorf("opening input: %w", err)
		}
		defer inFile.Close()
	} else {
		inFile = os.Stdin
	}

	reader := cli.NewTabReader(inFile, !colOpts.NoHead)

	// Read headers and find key column
	_, err = reader.Headers()
	if err != nil {
		return fmt.Errorf("reading headers: %w", err)
	}

	keyCol, err := reader.FindColumn(colOpts.Col)
	if err != nil {
		return fmt.Errorf("finding column: %w", err)
	}

	// Count distinct values
	seen := make(map[string]bool)

	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading row: %w", err)
		}

		// Get key value
		var key string
		if keyCol < 0 {
			// Last column
			if len(row) > 0 {
				key = row[len(row)-1]
			}
		} else if keyCol < len(row) {
			key = row[keyCol]
		}

		seen[key] = true
	}

	// Output result
	if !colOpts.NoHead {
		fmt.Println("count")
	}
	fmt.Println(len(seen))

	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
