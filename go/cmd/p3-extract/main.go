// Command p3-extract selects columns from a tab-delimited file.
//
// Usage:
//
//	p3-extract [options] col1 col2 ... [file]
//
// Examples:
//
//	p3-extract 1 3 5 < data.txt
//	p3-extract genome_id genome_name < data.txt
//	p3-extract --reverse 2 < data.txt
package main

import (
	"fmt"
	"io"
	"os"
	"strconv"

	"github.com/BV-BRC/bvbrc/pkg/cli"
	"github.com/spf13/cobra"
)

var (
	all     bool
	reverse bool
	noHead  bool
)

var rootCmd = &cobra.Command{
	Use:   "p3-extract [options] col1 col2 ... [file]",
	Short: "Select columns from a tab-delimited file",
	Long: `This command extracts specified columns from a tab-delimited file.
Columns can be specified by 1-based index or by header name.

Examples:

  # Extract columns 1, 3, and 5
  p3-extract 1 3 5 < data.txt

  # Extract columns by name
  p3-extract genome_id genome_name < data.txt

  # Extract all columns EXCEPT column 2
  p3-extract --reverse 2 < data.txt

  # Copy entire file (all columns)
  p3-extract --all < data.txt`,
	RunE: run,
}

func init() {
	rootCmd.Flags().BoolVar(&all, "all", false, "output all columns")
	rootCmd.Flags().BoolVarP(&reverse, "reverse", "v", false, "output all columns NOT in the list")
	rootCmd.Flags().BoolVar(&noHead, "nohead", false, "input file has no header row")
}

func run(cmd *cobra.Command, args []string) error {
	// Separate column specs from file argument
	var colSpecs []string
	var inputFile string

	for i, arg := range args {
		// Check if this might be a file (last arg that exists or is "-")
		if i == len(args)-1 {
			if arg == "-" || fileExists(arg) {
				inputFile = arg
				continue
			}
		}
		colSpecs = append(colSpecs, arg)
	}

	// Validate arguments
	if !all && len(colSpecs) == 0 {
		return fmt.Errorf("no columns specified (use --all to output all columns)")
	}

	// Open input
	var inFile *os.File
	var err error
	if inputFile != "" && inputFile != "-" {
		inFile, err = os.Open(inputFile)
		if err != nil {
			return fmt.Errorf("opening input: %w", err)
		}
		defer inFile.Close()
	} else {
		inFile = os.Stdin
	}

	reader := cli.NewTabReader(inFile, !noHead)

	// Read headers
	headers, err := reader.Headers()
	if err != nil {
		return fmt.Errorf("reading headers: %w", err)
	}

	writer := cli.NewTabWriter(os.Stdout)
	defer writer.Flush()

	// If --all mode, just copy everything
	if all {
		if headers != nil {
			if err := writer.WriteHeaders(headers); err != nil {
				return fmt.Errorf("writing headers: %w", err)
			}
		}
		for {
			row, err := reader.Read()
			if err == io.EOF {
				break
			}
			if err != nil {
				return fmt.Errorf("reading row: %w", err)
			}
			if err := writer.WriteRow(row...); err != nil {
				return fmt.Errorf("writing row: %w", err)
			}
		}
		return nil
	}

	// Resolve column indices
	var colIndices []int
	for _, spec := range colSpecs {
		idx, err := resolveColumn(spec, headers)
		if err != nil {
			return err
		}
		colIndices = append(colIndices, idx)
	}

	// If reverse mode, compute the complement set
	if reverse {
		excludeSet := make(map[int]bool)
		for _, idx := range colIndices {
			excludeSet[idx] = true
		}

		// Determine number of columns from headers or first row
		numCols := len(headers)
		if numCols == 0 {
			// Need to peek at first row
			return fmt.Errorf("--reverse requires headers to determine column count")
		}

		colIndices = nil
		for i := 0; i < numCols; i++ {
			if !excludeSet[i] {
				colIndices = append(colIndices, i)
			}
		}
	}

	// Output headers
	if headers != nil {
		var outHeaders []string
		for _, idx := range colIndices {
			if idx < len(headers) {
				outHeaders = append(outHeaders, headers[idx])
			} else {
				outHeaders = append(outHeaders, "")
			}
		}
		if err := writer.WriteHeaders(outHeaders); err != nil {
			return fmt.Errorf("writing headers: %w", err)
		}
	}

	// Process data rows
	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading row: %w", err)
		}

		var outRow []string
		for _, idx := range colIndices {
			if idx < len(row) {
				outRow = append(outRow, row[idx])
			} else {
				outRow = append(outRow, "")
			}
		}
		if err := writer.WriteRow(outRow...); err != nil {
			return fmt.Errorf("writing row: %w", err)
		}
	}

	return nil
}

// resolveColumn converts a column spec (name or 1-based index) to a 0-based index.
func resolveColumn(spec string, headers []string) (int, error) {
	// Try to parse as number (1-based)
	if idx, err := strconv.Atoi(spec); err == nil {
		if idx < 1 {
			return 0, fmt.Errorf("column index must be >= 1, got %d", idx)
		}
		return idx - 1, nil // Convert to 0-based
	}

	// Search headers for matching name
	for i, h := range headers {
		if h == spec {
			return i, nil
		}
	}

	return 0, fmt.Errorf("column %q not found in headers", spec)
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
