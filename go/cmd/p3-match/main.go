// Command p3-match filters rows based on pattern matching.
//
// Usage:
//
//	p3-match [options] pattern [file]
//
// Examples:
//
//	p3-match Streptomyces < data.txt
//	p3-match -c 2 "DNA polymerase" data.txt
//	p3-match -v incomplete data.txt
package main

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/cli"
	"github.com/spf13/cobra"
)

var (
	colOpts  cli.ColOptions
	reverse  bool
	discards string
	nonBlank bool
	exact    bool
)

var rootCmd = &cobra.Command{
	Use:   "p3-match [options] pattern [file]",
	Short: "Filter rows based on pattern matching",
	Long: `This command filters rows from a tab-delimited file based on whether
a specified column matches a pattern.

By default, matching is case-insensitive and matches substrings.
Use --exact for exact case-sensitive matching.

Examples:

  # Match rows where last column contains "Streptomyces"
  p3-match Streptomyces < data.txt

  # Match rows where column 2 contains "DNA polymerase"
  p3-match -c 2 "DNA polymerase" data.txt

  # Output rows that do NOT match
  p3-match -v incomplete data.txt

  # Match any non-blank value
  p3-match --nonblank < data.txt

  # Write non-matching rows to a file
  p3-match --discards=rejected.txt pattern data.txt`,
	RunE: run,
}

func init() {
	cli.AddColFlags(rootCmd, &colOpts, 0)
	rootCmd.Flags().BoolVarP(&reverse, "reverse", "v", false, "output non-matching rows instead")
	rootCmd.Flags().BoolVar(&reverse, "invert", false, "output non-matching rows instead")
	_ = rootCmd.Flags().MarkHidden("invert")
	rootCmd.Flags().StringVar(&discards, "discards", "", "file to write non-matching rows")
	rootCmd.Flags().BoolVar(&nonBlank, "nonblank", false, "match any non-blank value")
	rootCmd.Flags().BoolVar(&exact, "exact", false, "require exact match (case-sensitive)")
}

func run(cmd *cobra.Command, args []string) error {
	// Parse arguments
	var pattern string
	var inputFile string

	if nonBlank {
		// No pattern needed
		if len(args) > 0 {
			if args[0] == "-" || fileExists(args[0]) {
				inputFile = args[0]
			} else {
				// Could be a pattern or file
				if len(args) > 1 {
					pattern = args[0]
					inputFile = args[1]
				} else if fileExists(args[0]) {
					inputFile = args[0]
				} else {
					pattern = args[0]
				}
			}
		}
	} else {
		// Pattern is required
		if len(args) < 1 {
			return fmt.Errorf("pattern argument required")
		}
		pattern = args[0]
		if len(args) > 1 {
			inputFile = args[1]
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

	// Open discards file if specified
	var discardWriter *cli.TabWriter
	if discards != "" {
		discardFile, err := os.Create(discards)
		if err != nil {
			return fmt.Errorf("opening discards file: %w", err)
		}
		defer discardFile.Close()
		discardWriter = cli.NewTabWriter(discardFile)
		defer discardWriter.Flush()
	}

	reader := cli.NewTabReader(inFile, !colOpts.NoHead)

	// Read headers and find key column
	headers, err := reader.Headers()
	if err != nil {
		return fmt.Errorf("reading headers: %w", err)
	}

	keyCol, err := reader.FindColumn(colOpts.Col)
	if err != nil {
		return fmt.Errorf("finding column: %w", err)
	}

	writer := cli.NewTabWriter(os.Stdout)
	defer writer.Flush()

	// Output headers
	if headers != nil {
		if err := writer.WriteHeaders(headers); err != nil {
			return fmt.Errorf("writing headers: %w", err)
		}
		if discardWriter != nil {
			if err := discardWriter.WriteHeaders(headers); err != nil {
				return fmt.Errorf("writing discard headers: %w", err)
			}
		}
	}

	// Compile pattern for matching
	var matcher func(string) bool
	if nonBlank {
		matcher = func(s string) bool {
			return strings.TrimSpace(s) != ""
		}
	} else if exact {
		matcher = func(s string) bool {
			return s == pattern
		}
	} else {
		// Case-insensitive substring match
		lowerPattern := strings.ToLower(pattern)
		// Check if pattern looks numeric
		if _, err := strconv.ParseFloat(pattern, 64); err == nil {
			// Numeric - exact match
			matcher = func(s string) bool {
				return s == pattern
			}
		} else {
			// Try to compile as regex, fall back to substring
			re, err := regexp.Compile("(?i)" + regexp.QuoteMeta(pattern))
			if err != nil {
				matcher = func(s string) bool {
					return strings.Contains(strings.ToLower(s), lowerPattern)
				}
			} else {
				matcher = func(s string) bool {
					return re.MatchString(s)
				}
			}
		}
	}

	// Process rows
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
			if len(row) > 0 {
				key = row[len(row)-1]
			}
		} else if keyCol < len(row) {
			key = row[keyCol]
		}

		// Check match
		matches := matcher(key)

		// XOR with reverse flag
		outputToMain := matches != reverse

		if outputToMain {
			if err := writer.WriteRow(row...); err != nil {
				return fmt.Errorf("writing row: %w", err)
			}
		} else if discardWriter != nil {
			if err := discardWriter.WriteRow(row...); err != nil {
				return fmt.Errorf("writing discard row: %w", err)
			}
		}
	}

	return nil
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
