// Command p3-submit-proteome-comparison submits a proteome comparison job.
//
// Usage:
//
//	p3-submit-proteome-comparison [options] output-path output-name
//
// This command compares proteins against a reference genome using BLASTP.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/appservice"
	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/BV-BRC/bvbrc/pkg/workspace"
	"github.com/spf13/cobra"
)

var (
	workspacePrefix    string
	workspaceUploadDir string
	overwrite          bool
	dryRun             bool

	genomeIDs         string
	proteinFastas     []string
	userFeatureGroups []string
	referenceGenomeID string
	minSeqCov         float64
	maxEVal           float64
	minIdent          float64
	minPositives      float64
)

var rootCmd = &cobra.Command{
	Use:   "p3-submit-proteome-comparison [options] output-path output-name",
	Short: "Submit a proteome comparison job to BV-BRC",
	Long: `Compare proteins against a reference genome using BLASTP.

Examples:

  # Compare genomes against a reference
  p3-submit-proteome-comparison --genome-ids 83332.12,511145.12 \
    --reference-genome-id 83332.12 \
    /username@patricbrc.org/home/comparison MyComparison

  # Compare with protein FASTA files
  p3-submit-proteome-comparison --protein-fasta proteins.faa \
    --reference-genome-id 83332.12 \
    /username@patricbrc.org/home/comparison MyComparison`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	rootCmd.Flags().StringVar(&genomeIDs, "genome-ids", "", "comma-delimited genome IDs or file")
	rootCmd.Flags().StringArrayVar(&proteinFastas, "protein-fasta", nil, "protein FASTA file")
	rootCmd.Flags().StringArrayVar(&userFeatureGroups, "user-feature-group", nil, "feature group workspace path")
	rootCmd.Flags().StringVar(&referenceGenomeID, "reference-genome-id", "", "reference genome ID (required)")
	rootCmd.Flags().Float64Var(&minSeqCov, "min-seq-cov", 0.30, "minimum sequence coverage (0-1)")
	rootCmd.Flags().Float64Var(&maxEVal, "max-e-val", 1e-5, "maximum e-value")
	rootCmd.Flags().Float64Var(&minIdent, "min-ident", 0.1, "minimum identity (0-1)")
	rootCmd.Flags().Float64Var(&minPositives, "min-positives", 0.2, "minimum positives (0-1)")

	rootCmd.MarkFlagRequired("reference-genome-id")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate parameters
	if minSeqCov < 0 || minSeqCov > 1.0 {
		return fmt.Errorf("min-seq-cov must be between 0 and 1")
	}
	if minIdent < 0 || minIdent > 1.0 {
		return fmt.Errorf("min-ident must be between 0 and 1")
	}
	if minPositives < 0 || minPositives > 1.0 {
		return fmt.Errorf("min-positives must be between 0 and 1")
	}

	// Get auth token
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to submit jobs")
	}

	ws := workspace.New(workspace.WithToken(token))
	app := appservice.New(appservice.WithToken(token))

	outputPath = strings.TrimPrefix(outputPath, "ws:")
	outputPath = expandWorkspacePath(outputPath)
	outputPath = strings.TrimSuffix(outputPath, "/")

	if workspaceUploadDir == "" {
		workspaceUploadDir = outputPath
	}

	// Parse genome IDs
	var genomeList []string
	if genomeIDs != "" {
		genomeList, err = parseGenomeIDs(genomeIDs)
		if err != nil {
			return fmt.Errorf("parsing genome IDs: %w", err)
		}
	}

	// Find reference genome index
	referenceGenomeIndex := 1
	found := false
	for i, id := range genomeList {
		if id == referenceGenomeID {
			referenceGenomeIndex = i + 1
			found = true
			break
		}
	}
	if !found {
		// Add reference to front
		genomeList = append([]string{referenceGenomeID}, genomeList...)
		referenceGenomeIndex = 1
	}

	// Process protein FASTA files
	var userGenomes []string
	for _, fasta := range proteinFastas {
		wsPath, err := processFilename(ws, fasta, "feature_protein_fasta", token)
		if err != nil {
			return err
		}
		userGenomes = append(userGenomes, wsPath)
	}

	// Process feature groups
	var groups []string
	for _, group := range userFeatureGroups {
		group = strings.TrimPrefix(group, "ws:")
		group = expandWorkspacePath(group)
		groups = append(groups, group)
	}

	params := map[string]interface{}{
		"genome_ids":             genomeList,
		"user_feature_groups":    groups,
		"user_genomes":           userGenomes,
		"reference_genome_index": referenceGenomeIndex,
		"min_seq_cov":            minSeqCov,
		"min_ident":              minIdent,
		"min_positives":          minPositives,
		"max_e_val":              maxEVal,
		"output_path":            outputPath,
		"output_file":            outputName,
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	task, err := app.StartApp2("GenomeComparison", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting proteome comparison: %w", err)
	}

	fmt.Printf("Submitted proteome comparison with id %s\n", task.GetID())
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

func processFilename(ws *workspace.Client, path, fileType string, token *auth.Token) (string, error) {
	if strings.HasPrefix(path, "ws:") {
		wsPath := expandWorkspacePath(strings.TrimPrefix(path, "ws:"))
		meta, err := ws.Stat(wsPath, false)
		if err != nil || meta.IsFolder() {
			return "", fmt.Errorf("workspace path %s not found", wsPath)
		}
		return wsPath, nil
	}

	info, err := os.Stat(path)
	if err != nil {
		return "", fmt.Errorf("local file %s does not exist", path)
	}
	if info.IsDir() {
		return "", fmt.Errorf("%s is a directory", path)
	}

	if workspaceUploadDir == "" {
		return "", fmt.Errorf("upload requested for %s but no upload path specified", path)
	}

	fileName := filepath.Base(path)
	wsPath := workspaceUploadDir + "/" + fileName

	existing, _ := ws.Stat(wsPath, false)
	if existing != nil && !overwrite {
		return "", fmt.Errorf("target path %s already exists and --overwrite not specified", wsPath)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("reading file: %w", err)
	}

	fmt.Printf("Uploading %s to %s...\n", path, wsPath)
	_, err = ws.Create(workspace.CreateParams{
		Objects: []workspace.CreateObject{{
			Path: wsPath,
			Type: fileType,
			Data: string(data),
		}},
		Overwrite: overwrite,
	})
	if err != nil {
		return "", fmt.Errorf("uploading file: %w", err)
	}
	fmt.Println("done")

	return wsPath, nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
