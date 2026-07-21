// Command p3-submit-comparative-systems submits a comparative systems job.
//
// Usage:
//
//	p3-submit-comparative-systems [options] output-path output-name
//
// This command compares subsystems, pathways, and protein families across genomes.
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
	workspacePrefix string
	dryRun          bool

	genomes      string
	genomeGroups []string
)

var rootCmd = &cobra.Command{
	Use:   "p3-submit-comparative-systems [options] output-path output-name",
	Short: "Submit a comparative systems job to BV-BRC",
	Long: `Compare subsystems, pathways, and protein families across genomes.

Examples:

  # Compare specific genomes
  p3-submit-comparative-systems --genomes 83332.12,511145.12 \
    /username@patricbrc.org/home/comparison MyComparison

  # Compare genomes from a genome group
  p3-submit-comparative-systems --genome-group /username@patricbrc.org/home/MyGenomes \
    /username@patricbrc.org/home/comparison MyComparison`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	rootCmd.Flags().StringVar(&genomes, "genomes", "", "comma-delimited genome IDs or file")
	rootCmd.Flags().StringArrayVar(&genomeGroups, "genome-group", nil, "genome group workspace path")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate input
	if genomes == "" && len(genomeGroups) == 0 {
		return fmt.Errorf("must specify either --genomes or --genome-group")
	}

	// Get auth token
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to submit jobs")
	}

	app := appservice.New(appservice.WithToken(token))

	outputPath = strings.TrimPrefix(outputPath, "ws:")
	outputPath = expandWorkspacePath(outputPath)
	outputPath = strings.TrimSuffix(outputPath, "/")

	params := map[string]interface{}{
		"output_path": outputPath,
		"output_file": outputName,
	}

	// Parse genome IDs
	if genomes != "" {
		genomeList, err := parseGenomeIDs(genomes)
		if err != nil {
			return fmt.Errorf("parsing genome IDs: %w", err)
		}
		params["genome_ids"] = genomeList
	}

	// Process genome groups
	if len(genomeGroups) > 0 {
		var groups []string
		for _, group := range genomeGroups {
			group = strings.TrimPrefix(group, "ws:")
			group = expandWorkspacePath(group)
			groups = append(groups, group)
		}
		params["genome_groups"] = groups
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	task, err := app.StartApp2("ComparativeSystems", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting comparative systems: %w", err)
	}

	fmt.Printf("Submitted comparative systems with id %s\n", task.GetID())
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
	info, err := os.Stat(input)
	if err == nil && !info.IsDir() {
		return readGenomeFile(input)
	}
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
		if isFirst {
			isFirst = false
			lower := strings.ToLower(line)
			if strings.Contains(lower, "genome") || strings.Contains(lower, "id") {
				continue
			}
		}
		parts := strings.Split(line, "\t")
		id := strings.TrimSpace(parts[0])
		id = strings.Trim(id, `"'`)
		if id != "" {
			ids = append(ids, id)
		}
	}
	return ids, scanner.Err()
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
