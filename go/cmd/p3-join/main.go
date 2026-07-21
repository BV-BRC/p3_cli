// Command p3-join joins two tab-delimited files on a key column.
//
// Usage:
//
//	p3-join [options] file1 [file2]
//
// Examples:
//
//	p3-join file1.txt file2.txt
//	p3-join -1 genome_id -2 genome_id file1.txt file2.txt
//	p3-join --left file1.txt file2.txt
package main

import (
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/cli"
	"github.com/spf13/cobra"
)

var (
	key1     string
	key2     string
	onlyCols string
	noHead   bool
	nonBlank bool
	leftJoin bool
)

var rootCmd = &cobra.Command{
	Use:   "p3-join [options] file1 [file2]",
	Short: "Join two tab-delimited files on a key column",
	Long: `This command joins two tab-delimited files based on a common key column.
The output contains all columns from file1, followed by columns from file2
(excluding the key column from file2).

If file2 is not specified, stdin is used.
Use "-" for file1 to read from stdin (then file2 must be specified).

Examples:

  # Join on last column (default)
  p3-join file1.txt file2.txt

  # Join on specific columns
  p3-join -1 genome_id -2 genome_id file1.txt file2.txt

  # Left join (keep all file1 rows even without match)
  p3-join --left file1.txt file2.txt

  # Include only specific columns from file2
  p3-join --only name,description file1.txt file2.txt`,
	Args: cobra.RangeArgs(1, 2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&key1, "key1", "1", "0", "key column in file1 (0=last, or name)")
	rootCmd.Flags().StringVar(&key1, "k1", "0", "")
	_ = rootCmd.Flags().MarkHidden("k1")
	rootCmd.Flags().StringVarP(&key2, "key2", "2", "", "key column in file2 (default: same as key1)")
	rootCmd.Flags().StringVar(&key2, "k2", "", "")
	_ = rootCmd.Flags().MarkHidden("k2")
	rootCmd.Flags().StringVar(&onlyCols, "only", "", "comma-separated columns to include from file2")
	rootCmd.Flags().BoolVar(&noHead, "nohead", false, "files have no header rows")
	rootCmd.Flags().BoolVar(&nonBlank, "nonblank", false, "skip rows with empty key values")
	rootCmd.Flags().BoolVar(&leftJoin, "left", false, "include all file1 rows even without matches")
}

func run(cmd *cobra.Command, args []string) error {
	// Determine file arguments
	var file1Path, file2Path string
	if len(args) == 1 {
		file1Path = args[0]
		file2Path = "-" // stdin
	} else {
		file1Path = args[0]
		file2Path = args[1]
	}

	// Default key2 to key1
	if key2 == "" {
		key2 = key1
	}

	// Phase 1: Read file2 into memory
	file2Data, file2Headers, file2ColIndices, err := readFile2(file2Path)
	if err != nil {
		return err
	}

	// Phase 2: Read file1 and perform joins
	var file1 *os.File
	if file1Path == "-" {
		file1 = os.Stdin
	} else {
		file1, err = os.Open(file1Path)
		if err != nil {
			return fmt.Errorf("opening file1: %w", err)
		}
		defer file1.Close()
	}

	reader1 := cli.NewTabReader(file1, !noHead)

	// Read file1 headers
	headers1, err := reader1.Headers()
	if err != nil {
		return fmt.Errorf("reading file1 headers: %w", err)
	}

	// Find key column in file1
	keyCol1, err := findColumn(key1, headers1)
	if err != nil {
		return fmt.Errorf("file1 key column: %w", err)
	}

	writer := cli.NewTabWriter(os.Stdout)
	defer writer.Flush()

	// Write output headers
	if headers1 != nil && file2Headers != nil {
		var outHeaders []string
		outHeaders = append(outHeaders, headers1...)
		for _, idx := range file2ColIndices {
			if idx < len(file2Headers) {
				outHeaders = append(outHeaders, file2Headers[idx])
			}
		}
		if err := writer.WriteHeaders(outHeaders); err != nil {
			return fmt.Errorf("writing headers: %w", err)
		}
	}

	// Process file1 rows
	for {
		row1, err := reader1.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading file1 row: %w", err)
		}

		// Get key value
		var keyVal string
		if keyCol1 < 0 {
			if len(row1) > 0 {
				keyVal = row1[len(row1)-1]
			}
		} else if keyCol1 < len(row1) {
			keyVal = row1[keyCol1]
		}

		// Skip blank keys if requested
		if nonBlank && strings.TrimSpace(keyVal) == "" {
			continue
		}

		// Look up matches in file2
		matches := file2Data[keyVal]

		if len(matches) == 0 {
			if leftJoin {
				// Output file1 row with empty file2 columns
				outRow := make([]string, len(row1)+len(file2ColIndices))
				copy(outRow, row1)
				if err := writer.WriteRow(outRow...); err != nil {
					return fmt.Errorf("writing row: %w", err)
				}
			}
			continue
		}

		// Output a row for each match
		for _, match := range matches {
			var outRow []string
			outRow = append(outRow, row1...)
			outRow = append(outRow, match...)
			if err := writer.WriteRow(outRow...); err != nil {
				return fmt.Errorf("writing row: %w", err)
			}
		}
	}

	return nil
}

// readFile2 reads file2 into a map keyed by the key column.
// Returns the map, headers, and the column indices to include in output.
func readFile2(path string) (map[string][][]string, []string, []int, error) {
	var file2 *os.File
	var err error
	if path == "-" {
		file2 = os.Stdin
	} else {
		file2, err = os.Open(path)
		if err != nil {
			return nil, nil, nil, fmt.Errorf("opening file2: %w", err)
		}
		defer file2.Close()
	}

	reader := cli.NewTabReader(file2, !noHead)

	// Read headers
	headers, err := reader.Headers()
	if err != nil {
		return nil, nil, nil, fmt.Errorf("reading file2 headers: %w", err)
	}

	// Find key column
	keyCol, err := findColumn(key2, headers)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("file2 key column: %w", err)
	}

	// Determine which columns to include (excluding key column)
	var includeIndices []int
	if onlyCols != "" {
		// Parse --only option
		for _, spec := range strings.Split(onlyCols, ",") {
			spec = strings.TrimSpace(spec)
			idx, err := findColumn(spec, headers)
			if err != nil {
				return nil, nil, nil, fmt.Errorf("--only column: %w", err)
			}
			if idx != keyCol && idx >= 0 {
				includeIndices = append(includeIndices, idx)
			}
		}
	} else {
		// Include all columns except key
		numCols := len(headers)
		if numCols == 0 {
			numCols = 100 // Guess for headerless files
		}
		for i := 0; i < numCols; i++ {
			if i != keyCol && (keyCol >= 0 || i != numCols-1) {
				includeIndices = append(includeIndices, i)
			}
		}
	}

	// Read all rows into map
	data := make(map[string][][]string)

	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, nil, nil, fmt.Errorf("reading file2 row: %w", err)
		}

		// Get key value
		var keyVal string
		if keyCol < 0 {
			if len(row) > 0 {
				keyVal = row[len(row)-1]
			}
		} else if keyCol < len(row) {
			keyVal = row[keyCol]
		}

		// Skip blank keys if requested
		if nonBlank && strings.TrimSpace(keyVal) == "" {
			continue
		}

		// Extract included columns
		var includedRow []string
		for _, idx := range includeIndices {
			if idx < len(row) {
				includedRow = append(includedRow, row[idx])
			} else {
				includedRow = append(includedRow, "")
			}
		}

		data[keyVal] = append(data[keyVal], includedRow)
	}

	// Update includeIndices based on actual file structure
	if onlyCols == "" && len(headers) > 0 {
		includeIndices = nil
		for i := 0; i < len(headers); i++ {
			if i != keyCol && (keyCol >= 0 || i != len(headers)-1) {
				includeIndices = append(includeIndices, i)
			}
		}
	}

	return data, headers, includeIndices, nil
}

func findColumn(spec string, headers []string) (int, error) {
	// Handle "0" as last column
	if spec == "0" || spec == "" {
		return -1, nil // -1 means last column
	}

	// Try to parse as number (1-based)
	if idx, err := strconv.Atoi(spec); err == nil {
		if idx < 0 {
			return 0, fmt.Errorf("column index must be >= 0, got %d", idx)
		}
		if idx == 0 {
			return -1, nil // Last column
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

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
