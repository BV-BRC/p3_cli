// Command p3-head outputs the first N lines from a tab-delimited file.
//
// Usage:
//
//	p3-head [options] [file]
//
// Examples:
//
//	p3-head < data.txt
//	p3-head -n 20 data.txt
//	p3-head --nohead -n 5 data.txt
package main

import (
	"fmt"
	"os"

	"github.com/BV-BRC/bvbrc/pkg/cli"
	"github.com/spf13/cobra"
)

var (
	lines  int
	noHead bool
)

var rootCmd = &cobra.Command{
	Use:   "p3-head [file]",
	Short: "Output the first N lines from a tab-delimited file",
	Long: `This command outputs the header line plus the first N data lines
from a tab-delimited file. The header line is not counted in the line limit.

Examples:

  # Output header + first 10 lines (default)
  p3-head < data.txt

  # Output header + first 20 lines
  p3-head -n 20 data.txt

  # No header mode - output first 5 lines
  p3-head --nohead -n 5 data.txt`,
	Args: cobra.MaximumNArgs(1),
	RunE: run,
}

func init() {
	rootCmd.Flags().IntVarP(&lines, "lines", "n", 10, "number of data lines to output")
	rootCmd.Flags().BoolVar(&noHead, "nohead", false, "input file has no header row")
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

	reader := cli.NewTabReader(inFile, !noHead)

	// Read and output headers if present
	headers, err := reader.Headers()
	if err != nil {
		return fmt.Errorf("reading headers: %w", err)
	}

	writer := cli.NewTabWriter(os.Stdout)
	defer writer.Flush()

	if headers != nil {
		if err := writer.WriteHeaders(headers); err != nil {
			return fmt.Errorf("writing headers: %w", err)
		}
	}

	// Output first N lines
	count := 0
	for count < lines {
		row, err := reader.Read()
		if err != nil {
			break // EOF or error
		}
		if err := writer.WriteRow(row...); err != nil {
			return fmt.Errorf("writing row: %w", err)
		}
		count++
	}

	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
