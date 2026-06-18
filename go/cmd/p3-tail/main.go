// Command p3-tail outputs the last N lines from a tab-delimited file.
//
// Usage:
//
//	p3-tail [options] [file]
//
// Examples:
//
//	p3-tail < data.txt
//	p3-tail -n 20 data.txt
//	p3-tail --nohead -n 5 data.txt
package main

import (
	"fmt"
	"io"
	"os"

	"github.com/BV-BRC/bvbrc/pkg/cli"
	"github.com/spf13/cobra"
)

var (
	lines  int
	noHead bool
)

var rootCmd = &cobra.Command{
	Use:   "p3-tail [file]",
	Short: "Output the last N lines from a tab-delimited file",
	Long: `This command outputs the header line plus the last N data lines
from a tab-delimited file. The header line is not counted in the line limit.

Examples:

  # Output header + last 10 lines (default)
  p3-tail < data.txt

  # Output header + last 20 lines
  p3-tail -n 20 data.txt

  # No header mode - output last 5 lines
  p3-tail --nohead -n 5 data.txt`,
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

	// Read and store headers if present
	headers, err := reader.Headers()
	if err != nil {
		return fmt.Errorf("reading headers: %w", err)
	}

	// Use circular buffer to store last N lines
	buffer := make([][]string, 0, lines)

	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading row: %w", err)
		}

		// Add to buffer
		if len(buffer) < lines {
			buffer = append(buffer, row)
		} else {
			// Shift buffer and add new row at end
			copy(buffer, buffer[1:])
			buffer[len(buffer)-1] = row
		}
	}

	// Output results
	writer := cli.NewTabWriter(os.Stdout)
	defer writer.Flush()

	if headers != nil {
		if err := writer.WriteHeaders(headers); err != nil {
			return fmt.Errorf("writing headers: %w", err)
		}
	}

	for _, row := range buffer {
		if err := writer.WriteRow(row...); err != nil {
			return fmt.Errorf("writing row: %w", err)
		}
	}

	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
