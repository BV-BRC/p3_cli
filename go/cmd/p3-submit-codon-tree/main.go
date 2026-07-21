// Command p3-submit-codon-tree submits a phylogenetic tree job.
//
// Usage:
//
//	p3-submit-codon-tree [options] output-path output-name
//
// This command submits a codon tree analysis to BV-BRC.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/appservice"
	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/spf13/cobra"
)

var (
	workspacePrefix   string
	dryRun            bool

	genomeIDs         string
	numberOfGenes     int
	maxGenomesMissing int
	maxAllowedDups    int
)

var rootCmd = &cobra.Command{
	Use:   "p3-submit-codon-tree [options] output-path output-name",
	Short: "Submit a phylogenetic tree job to BV-BRC",
	Long: `Submit a codon tree analysis to BV-BRC.

This builds a phylogenetic tree from a set of genomes using marker genes.

Examples:

  # Build tree from genome IDs
  p3-submit-codon-tree --genome-ids 83332.12,511145.12,224308.43 \n    /username@patricbrc.org/home/trees MyTree

  # Build tree from a file of genome IDs
  p3-submit-codon-tree --genome-ids genomes.txt \n    /username@patricbrc.org/home/trees MyTree

  # Specify number of genes
  p3-submit-codon-tree --genome-ids 83332.12,511145.12 --number-of-genes 200 \n    /username@patricbrc.org/home/trees MyTree`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	rootCmd.Flags().StringVar(&genomeIDs, "genome-ids", "", "comma-separated genome IDs or file containing IDs")
	rootCmd.Flags().IntVar(&numberOfGenes, "number-of-genes", 100, "number of marker genes to use")
	rootCmd.Flags().IntVar(&maxGenomesMissing, "max-genomes-missing", 0, "maximum genomes missing from a PGFam (0-10)")
	rootCmd.Flags().IntVar(&maxAllowedDups, "max-allowed-dups", 0, "maximum genomes with duplicate proteins (0-10)")

	rootCmd.MarkFlagRequired("genome-ids")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate parameters
	if numberOfGenes < 10 {
		return fmt.Errorf("number of genes must be at least 10")
	}
	if maxGenomesMissing < 0 || maxGenomesMissing > 10 {
		return fmt.Errorf("max-genomes-missing must be between 0 and 10")
	}
	if maxAllowedDups < 0 || maxAllowedDups > 10 {
		return fmt.Errorf("max-allowed-dups must be between 0 and 10")
	}

	// Parse genome IDs
	genomeList, err := parseGenomeIDs(genomeIDs)
	if err != nil {
		return fmt.Errorf("error processing genome-ids: %w", err)
	}
	if len(genomeList) < 3 {
		return fmt.Errorf("at least 3 genomes are required for tree building")
	}

	// Get auth token
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to submit jobs")
	}

	// Create client
	app := appservice.New(appservice.WithToken(token))

	// Clean output path
	outputPath = strings.TrimPrefix(outputPath, "ws:")
	outputPath = expandWorkspacePath(outputPath)
	outputPath = strings.TrimSuffix(outputPath, "/")

	// Build parameters
	params := map[string]interface{}{
		"genome_ids":          genomeList,
		"number_of_genes":     numberOfGenes,
		"bootstraps":          100,
		"max_genomes_missing": maxGenomesMissing,
		"max_allowed_dups":    maxAllowedDups,
		"output_path":         outputPath,
		"output_file":         outputName,
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	// Submit the job
	task, err := app.StartApp2("CodonTree", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting codon tree: %w", err)
	}

	fmt.Printf("Submitted codon tree with id %s\n", task.GetID())
	return nil
}

func expandWorkspacePath(path string) string {
	if strings.HasPrefix(path, "/") {
		return path
	}
	if workspacePrefix == "" {
		return path
	}
	return strings.TrimSuffix(workspacePrefix, "/") + "/" + path
}

func parseGenomeIDs(input string) ([]string, error) {
	// Check if input is a file
	info, err := os.Stat(input)
	if err == nil && !info.IsDir() {
		// Read genome IDs from file
		return readGenomeFile(input)
	}

	// Treat as comma-separated list
	parts := strings.Split(input, ",")
	var ids []string
	for _, p := range parts {
		id := strings.TrimSpace(p)
		id = strings.Trim(id, `"'`)
		if id != "" {
			ids = append(ids, id)
		}
	}
	return ids, nil
}

func readGenomeFile(filename string) ([]string, error) {
	file, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var ids []string
	scanner := bufio.NewScanner(file)
	isFirst := true
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		// Skip header if present
		if isFirst {
			isFirst = false
			lower := strings.ToLower(line)
			if strings.Contains(lower, "genome") || strings.Contains(lower, "id") {
				continue
			}
		}

		// Take first column if tab-separated
		parts := strings.Split(line, "\t")
		id := strings.TrimSpace(parts[0])
		id = strings.Trim(id, `"'`)
		if id != "" {
			ids = append(ids, id)
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return ids, nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
