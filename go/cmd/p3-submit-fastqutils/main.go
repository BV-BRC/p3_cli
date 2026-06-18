// Command p3-submit-fastqutils submits a FASTQ utilities job.
//
// Usage:
//
//	p3-submit-fastqutils [options] output-path output-name
//
// This command submits FASTQ files for various processing operations.
package main

import (
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

	// Read library options
	pairedEndLibs []string
	singleEndLibs []string
	srrIDs        []string

	// Processing options
	trim              bool
	pairedFilter      bool
	fastqc            bool
	referenceGenomeID string
)

var rootCmd = &cobra.Command{
	Use:   "p3-submit-fastqutils [options] output-path output-name",
	Short: "Submit a FASTQ utilities job to BV-BRC",
	Long: `Submit FASTQ files for various processing operations.

Examples:

  # Run FastQC quality control
  p3-submit-fastqutils --fastqc --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/fastq MyQC

  # Trim reads and run FastQC
  p3-submit-fastqutils --trim --fastqc --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/fastq MyQC

  # Align reads to a reference genome
  p3-submit-fastqutils --reference-genome-id 83332.12 \
    --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/fastq MyAlignment`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	// Read library options
	rootCmd.Flags().StringArrayVar(&pairedEndLibs, "paired-end-lib", nil, "paired-end read library (file1,file2)")
	rootCmd.Flags().StringArrayVar(&singleEndLibs, "single-end-lib", nil, "single-end read library")
	rootCmd.Flags().StringArrayVar(&srrIDs, "srr-id", nil, "SRA run ID")

	// Processing options
	rootCmd.Flags().BoolVar(&trim, "trim", false, "trim the sequences")
	rootCmd.Flags().BoolVar(&pairedFilter, "paired-filter", false, "perform paired-end filtering")
	rootCmd.Flags().BoolVar(&fastqc, "fastqc", false, "run FastQC quality control")
	rootCmd.Flags().StringVar(&referenceGenomeID, "reference-genome-id", "", "reference genome ID for alignment")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Build recipe list based on options
	var recipes []string
	if pairedFilter {
		recipes = append(recipes, "paired_filter")
	}
	if trim {
		recipes = append(recipes, "trim")
	}
	if fastqc {
		recipes = append(recipes, "fastqc")
	}
	if referenceGenomeID != "" {
		recipes = append(recipes, "align")
	}

	if len(recipes) == 0 {
		return fmt.Errorf("no service specified (use --trim, --fastqc, --paired-filter, or --reference-genome-id)")
	}

	// Validate we have input
	if len(pairedEndLibs) == 0 && len(singleEndLibs) == 0 && len(srrIDs) == 0 {
		return fmt.Errorf("at least one read library or SRR ID must be specified")
	}

	// Get auth token
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to submit jobs")
	}

	// Create clients
	ws := workspace.New(workspace.WithToken(token))
	app := appservice.New(appservice.WithToken(token))

	// Clean output path
	outputPath = strings.TrimPrefix(outputPath, "ws:")
	outputPath = expandWorkspacePath(outputPath)
	outputPath = strings.TrimSuffix(outputPath, "/")

	// Set upload path default
	if workspaceUploadDir == "" {
		workspaceUploadDir = outputPath
	}

	// Build parameters
	params := map[string]interface{}{
		"recipe":          recipes,
		"output_path":     outputPath,
		"output_file":     outputName,
		"paired_end_libs": []map[string]interface{}{},
		"single_end_libs": []map[string]interface{}{},
	}

	if referenceGenomeID != "" {
		params["reference_genome_id"] = referenceGenomeID
	}

	// Process paired-end libraries
	pairedLibs := params["paired_end_libs"].([]map[string]interface{})
	for _, lib := range pairedEndLibs {
		parts := strings.Split(lib, ",")
		if len(parts) != 2 {
			return fmt.Errorf("paired-end library must have two files separated by comma: %s", lib)
		}
		read1, err := processFilename(ws, parts[0], "reads", token)
		if err != nil {
			return err
		}
		read2, err := processFilename(ws, parts[1], "reads", token)
		if err != nil {
			return err
		}
		pairedLibs = append(pairedLibs, map[string]interface{}{
			"read1": read1,
			"read2": read2,
		})
	}
	params["paired_end_libs"] = pairedLibs

	// Process single-end libraries
	singleLibs := params["single_end_libs"].([]map[string]interface{})
	for _, lib := range singleEndLibs {
		read, err := processFilename(ws, lib, "reads", token)
		if err != nil {
			return err
		}
		singleLibs = append(singleLibs, map[string]interface{}{
			"read": read,
		})
	}
	params["single_end_libs"] = singleLibs

	// Add SRR IDs
	if len(srrIDs) > 0 {
		params["srr_ids"] = srrIDs
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	// Submit the job
	task, err := app.StartApp2("FastqUtils", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting fastq utilities: %w", err)
	}

	fmt.Printf("Submitted fastq utilities with id %s\n", task.GetID())
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

func processFilename(ws *workspace.Client, path, fileType string, token *auth.Token) (string, error) {
	// Check if it's a workspace path
	if strings.HasPrefix(path, "ws:") {
		wsPath := expandWorkspacePath(strings.TrimPrefix(path, "ws:"))
		meta, err := ws.Stat(wsPath, false)
		if err != nil || meta.IsFolder() {
			return "", fmt.Errorf("workspace path %s not found", wsPath)
		}
		return wsPath, nil
	}

	// Local file - needs upload
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

	// Check if file exists
	existing, _ := ws.Stat(wsPath, false)
	if existing != nil && !overwrite {
		return "", fmt.Errorf("target path %s already exists and --overwrite not specified", wsPath)
	}

	// Upload the file
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
