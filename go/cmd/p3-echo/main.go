// Command p3-echo writes data to standard output in tab-delimited format.
//
// Usage:
//
//	p3-echo [options] value1 value2 ... valueN
//
// This command creates a tab-delimited output file containing the values on the command line.
// If a single header (--title option) is specified, then the output file is single-column.
// Otherwise, there is one column per header.
//
// Examples:
//
//	# Single column output
//	p3-echo --title=genome_id 83333.1 100226.1
//
//	# Multi-column output
//	p3-echo --title=genome_id --title=name 83333.1 "Escherichia coli" 100226.1 "Streptomyces coelicolor"
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
)

var (
	titles  []string
	noHead  int
	dataFile string
)

var rootCmd = &cobra.Command{
	Use:   "p3-echo [options] value1 value2 ... valueN",
	Short: "Write data to standard output",
	Long: `Create a tab-delimited output file containing the values on the command line.

If a single header (--title option) is specified, then the output file is single-column.
Otherwise, there is one column per header.

Examples:

  # Single column output
  p3-echo --title=genome_id 83333.1 100226.1
  # Output:
  # genome_id
  # 83333.1
  # 100226.1

  # Multi-column output
  p3-echo --title=genome_id --title=name 83333.1 "Escherichia coli"
  # Output:
  # genome_id    name
  # 83333.1      Escherichia coli`,
	RunE: run,
}

func init() {
	rootCmd.Flags().StringArrayVarP(&titles, "title", "t", []string{"id"}, "header value(s) to use in first output record")
	rootCmd.Flags().IntVar(&noHead, "nohead", 0, "suppress header and use specified number of columns")
	rootCmd.Flags().StringVar(&dataFile, "data", "", "input data file to append to output")
}

func run(cmd *cobra.Command, args []string) error {
	// Determine number of columns
	var cols int
	if noHead > 0 {
		cols = noHead
	} else {
		cols = len(titles)
		// Print header
		fmt.Println(strings.Join(titles, "\t"))
	}

	// Output values in rows
	var line []string
	for _, value := range args {
		line = append(line, value)
		if len(line) >= cols {
			fmt.Println(strings.Join(line, "\t"))
			line = nil
		}
	}

	// Output any remaining partial line
	if len(line) > 0 {
		// Pad with empty strings if needed
		for len(line) < cols {
			line = append(line, "")
		}
		fmt.Println(strings.Join(line, "\t"))
	}

	// Append data from file if specified
	if dataFile != "" {
		file, err := os.Open(dataFile)
		if err != nil {
			return fmt.Errorf("opening data file: %w", err)
		}
		defer file.Close()

		scanner := bufio.NewScanner(file)
		for scanner.Scan() {
			fmt.Println(scanner.Text())
		}
		if err := scanner.Err(); err != nil {
			return fmt.Errorf("reading data file: %w", err)
		}
	}

	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
