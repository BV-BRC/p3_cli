// Command p3-sort sorts a tab-delimited file.
//
// Usage:
//
//	p3-sort [options] [col1[/type] col2[/type] ...] [file]
//
// Examples:
//
//	p3-sort < data.txt
//	p3-sort genome_id < data.txt
//	p3-sort 1 2/n < data.txt
//	p3-sort --unique name < data.txt
package main

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/cli"
	"github.com/spf13/cobra"
)

var (
	noHead   bool
	count    bool
	unique   bool
	dups     bool
	nonBlank bool
	verbose  bool
)

// sortSpec describes how to sort a column
type sortSpec struct {
	colIndex   int
	numeric    bool
	descending bool
	pegOrder   bool
}

var rootCmd = &cobra.Command{
	Use:   "p3-sort [options] [col1[/type] ...] [file]",
	Short: "Sort a tab-delimited file",
	Long: `This command sorts a tab-delimited file by one or more columns.
Sort types can be specified as suffixes:

  /n  - numeric sort
  /nr - numeric reverse
  /r  - string reverse
  /p  - PEG order (for feature IDs like fig|123.4.peg.5)
  /pr - PEG order reverse

Examples:

  # Sort by first column (default, string ascending)
  p3-sort < data.txt

  # Sort by genome_id column
  p3-sort genome_id < data.txt

  # Sort by column 1 (string) then column 2 (numeric)
  p3-sort 1 2/n < data.txt

  # Sort numerically descending
  p3-sort genome_length/nr < data.txt

  # Output only unique rows
  p3-sort --unique name < data.txt

  # Count occurrences of each key
  p3-sort --count name < data.txt`,
	RunE: run,
}

func init() {
	rootCmd.Flags().BoolVar(&noHead, "nohead", false, "input file has no header row")
	rootCmd.Flags().BoolVarP(&count, "count", "K", false, "output key fields with count")
	rootCmd.Flags().BoolVarP(&unique, "unique", "u", false, "output only one line per unique key")
	rootCmd.Flags().BoolVarP(&dups, "dups", "D", false, "output only records with duplicate keys")
	rootCmd.Flags().BoolVarP(&nonBlank, "nonblank", "V", false, "discard records with empty key fields")
	rootCmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "show progress messages")
}

func run(cmd *cobra.Command, args []string) error {
	// Separate column specs from file argument
	var colSpecs []string
	var inputFile string

	for i, arg := range args {
		if i == len(args)-1 && (arg == "-" || fileExists(arg)) {
			inputFile = arg
		} else {
			colSpecs = append(colSpecs, arg)
		}
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

	// Parse sort specifications
	var specs []sortSpec
	if len(colSpecs) == 0 {
		// Default: sort by first column
		specs = []sortSpec{{colIndex: 0}}
	} else {
		for _, spec := range colSpecs {
			s, err := parseSortSpec(spec, headers)
			if err != nil {
				return err
			}
			specs = append(specs, s)
		}
	}

	if verbose {
		fmt.Fprintf(os.Stderr, "Reading input...\n")
	}

	// Read all rows into memory
	type record struct {
		row []string
		key string
	}
	var records []record

	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading row: %w", err)
		}

		// Build composite key
		var keyParts []string
		for _, s := range specs {
			var val string
			if s.colIndex < len(row) {
				val = row[s.colIndex]
			}
			keyParts = append(keyParts, val)
		}
		key := strings.Join(keyParts, "\t")

		// Skip blank keys if requested
		if nonBlank {
			allBlank := true
			for _, p := range keyParts {
				if strings.TrimSpace(p) != "" {
					allBlank = false
					break
				}
			}
			if allBlank {
				continue
			}
		}

		records = append(records, record{row: row, key: key})
	}

	if verbose {
		fmt.Fprintf(os.Stderr, "Sorting %d records...\n", len(records))
	}

	// Sort records
	sort.SliceStable(records, func(i, j int) bool {
		return compareKeys(records[i].row, records[j].row, specs) < 0
	})

	if verbose {
		fmt.Fprintf(os.Stderr, "Writing output...\n")
	}

	writer := cli.NewTabWriter(os.Stdout)
	defer writer.Flush()

	// Count mode
	if count {
		// Build key column headers
		var keyHeaders []string
		if headers != nil {
			for _, s := range specs {
				if s.colIndex < len(headers) {
					keyHeaders = append(keyHeaders, headers[s.colIndex])
				} else {
					keyHeaders = append(keyHeaders, "")
				}
			}
			keyHeaders = append(keyHeaders, "count")
			if err := writer.WriteHeaders(keyHeaders); err != nil {
				return fmt.Errorf("writing headers: %w", err)
			}
		}

		// Group and count
		var lastKey string
		var lastKeyParts []string
		var keyCount int

		for _, rec := range records {
			if rec.key != lastKey {
				if keyCount > 0 {
					outRow := append(lastKeyParts, strconv.Itoa(keyCount))
					if err := writer.WriteRow(outRow...); err != nil {
						return fmt.Errorf("writing row: %w", err)
					}
				}
				lastKey = rec.key
				lastKeyParts = nil
				for _, s := range specs {
					if s.colIndex < len(rec.row) {
						lastKeyParts = append(lastKeyParts, rec.row[s.colIndex])
					} else {
						lastKeyParts = append(lastKeyParts, "")
					}
				}
				keyCount = 1
			} else {
				keyCount++
			}
		}
		if keyCount > 0 {
			outRow := append(lastKeyParts, strconv.Itoa(keyCount))
			if err := writer.WriteRow(outRow...); err != nil {
				return fmt.Errorf("writing row: %w", err)
			}
		}
		return nil
	}

	// Output headers
	if headers != nil {
		if err := writer.WriteHeaders(headers); err != nil {
			return fmt.Errorf("writing headers: %w", err)
		}
	}

	// Unique or dups mode: group records
	if unique || dups {
		var lastKey string
		var group []record

		flushGroup := func() error {
			if len(group) == 0 {
				return nil
			}
			if unique {
				// Output first record only
				if err := writer.WriteRow(group[0].row...); err != nil {
					return err
				}
			} else if dups && len(group) > 1 {
				// Output all records in group
				for _, rec := range group {
					if err := writer.WriteRow(rec.row...); err != nil {
						return err
					}
				}
			}
			return nil
		}

		for _, rec := range records {
			if rec.key != lastKey {
				if err := flushGroup(); err != nil {
					return fmt.Errorf("writing row: %w", err)
				}
				lastKey = rec.key
				group = nil
			}
			group = append(group, rec)
		}
		if err := flushGroup(); err != nil {
			return fmt.Errorf("writing row: %w", err)
		}
		return nil
	}

	// Normal mode: output all records
	for _, rec := range records {
		if err := writer.WriteRow(rec.row...); err != nil {
			return fmt.Errorf("writing row: %w", err)
		}
	}

	return nil
}

func parseSortSpec(spec string, headers []string) (sortSpec, error) {
	var s sortSpec

	// Check for type suffix
	parts := strings.SplitN(spec, "/", 2)
	colSpec := parts[0]

	if len(parts) > 1 {
		switch strings.ToLower(parts[1]) {
		case "n":
			s.numeric = true
		case "nr":
			s.numeric = true
			s.descending = true
		case "r":
			s.descending = true
		case "p":
			s.pegOrder = true
		case "pr":
			s.pegOrder = true
			s.descending = true
		default:
			return s, fmt.Errorf("unknown sort type: %s", parts[1])
		}
	}

	// Resolve column
	if idx, err := strconv.Atoi(colSpec); err == nil {
		if idx < 1 {
			return s, fmt.Errorf("column index must be >= 1, got %d", idx)
		}
		s.colIndex = idx - 1
	} else {
		// Search headers
		found := false
		for i, h := range headers {
			if h == colSpec {
				s.colIndex = i
				found = true
				break
			}
		}
		if !found {
			return s, fmt.Errorf("column %q not found in headers", colSpec)
		}
	}

	return s, nil
}

func compareKeys(a, b []string, specs []sortSpec) int {
	for _, s := range specs {
		var va, vb string
		if s.colIndex < len(a) {
			va = a[s.colIndex]
		}
		if s.colIndex < len(b) {
			vb = b[s.colIndex]
		}

		var cmp int
		if s.numeric {
			cmp = compareNumeric(va, vb)
		} else if s.pegOrder {
			cmp = comparePEG(va, vb)
		} else {
			cmp = strings.Compare(va, vb)
		}

		if s.descending {
			cmp = -cmp
		}

		if cmp != 0 {
			return cmp
		}
	}
	return 0
}

func compareNumeric(a, b string) int {
	na, errA := strconv.ParseFloat(a, 64)
	nb, errB := strconv.ParseFloat(b, 64)

	// Handle non-numeric values
	if errA != nil && errB != nil {
		return strings.Compare(a, b)
	}
	if errA != nil {
		return 1 // Non-numeric sorts after numeric
	}
	if errB != nil {
		return -1
	}

	if na < nb {
		return -1
	}
	if na > nb {
		return 1
	}
	return 0
}

// comparePEG compares FIG feature IDs like "fig|83332.12.peg.1"
func comparePEG(a, b string) int {
	partsA := parsePEG(a)
	partsB := parsePEG(b)

	// Compare genome ID (as string to preserve dots)
	if cmp := strings.Compare(partsA.genome, partsB.genome); cmp != 0 {
		return cmp
	}

	// Compare feature type
	if cmp := strings.Compare(partsA.ftype, partsB.ftype); cmp != 0 {
		return cmp
	}

	// Compare feature number
	if partsA.num < partsB.num {
		return -1
	}
	if partsA.num > partsB.num {
		return 1
	}
	return 0
}

type pegParts struct {
	genome string
	ftype  string
	num    int
}

func parsePEG(s string) pegParts {
	var p pegParts

	// Strip "fig|" prefix if present
	s = strings.TrimPrefix(s, "fig|")

	// Split on "."
	parts := strings.Split(s, ".")
	if len(parts) >= 2 {
		p.genome = parts[0] + "." + parts[1]
	}
	if len(parts) >= 3 {
		p.ftype = parts[2]
	}
	if len(parts) >= 4 {
		p.num, _ = strconv.Atoi(parts[3])
	}

	return p
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
