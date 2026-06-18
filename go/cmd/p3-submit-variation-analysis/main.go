// Command p3-submit-variation-analysis submits a variation analysis job.
//
// Usage:
//
//	p3-submit-variation-analysis [options] output-path output-name
//
// This command submits reads to be analyzed for small variations against a reference genome.
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

	pairedEndLibs     []string
	singleEndLibs     []string
	srrIDs            []string
	referenceGenomeID string
	mapper            string
	caller            string
)

var validMappers = map[string]bool{
	"BWA-mem": true, "BWA-mem-strict": true, "Bowtie2": true, "LAST": true, "minimap2": true,
}

var validCallers = map[string]bool{
	"FreeBayes": true, "BCFtools": true,
}

var rootCmd = &cobra.Command{
	Use:   "p3-submit-variation-analysis [options] output-path output-name",
	Short: "Submit a variation analysis job to BV-BRC",
	Long: `Submit reads to be analyzed for small variations against a reference genome.

Examples:

  # Analyze variations against a reference genome
  p3-submit-variation-analysis --reference-genome-id 83332.12 \
    --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/variation MyAnalysis

  # Use specific mapper and caller
  p3-submit-variation-analysis --reference-genome-id 83332.12 \
    --mapper Bowtie2 --caller BCFtools \
    --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/variation MyAnalysis`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	rootCmd.Flags().StringArrayVar(&pairedEndLibs, "paired-end-lib", nil, "paired-end read library (file1,file2)")
	rootCmd.Flags().StringArrayVar(&singleEndLibs, "single-end-lib", nil, "single-end read library")
	rootCmd.Flags().StringArrayVar(&srrIDs, "srr-id", nil, "SRA run ID")
	rootCmd.Flags().StringVar(&referenceGenomeID, "reference-genome-id", "", "reference genome ID (required)")
	rootCmd.Flags().StringVar(&mapper, "mapper", "BWA-mem", "mapping utility (BWA-mem, BWA-mem-strict, Bowtie2, LAST, minimap2)")
	rootCmd.Flags().StringVar(&caller, "caller", "FreeBayes", "SNP calling utility (FreeBayes, BCFtools)")

	rootCmd.MarkFlagRequired("reference-genome-id")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate mapper
	if !validMappers[mapper] {
		return fmt.Errorf("invalid mapper: %s", mapper)
	}

	// Validate caller
	if !validCallers[caller] {
		return fmt.Errorf("invalid caller: %s", caller)
	}

	// Validate input
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

	ws := workspace.New(workspace.WithToken(token))
	app := appservice.New(appservice.WithToken(token))

	outputPath = strings.TrimPrefix(outputPath, "ws:")
	outputPath = expandWorkspacePath(outputPath)
	outputPath = strings.TrimSuffix(outputPath, "/")

	if workspaceUploadDir == "" {
		workspaceUploadDir = outputPath
	}

	params := map[string]interface{}{
		"reference_genome_id": referenceGenomeID,
		"mapper":              mapper,
		"caller":              caller,
		"output_path":         outputPath,
		"output_file":         outputName,
		"paired_end_libs":     []map[string]interface{}{},
		"single_end_libs":     []map[string]interface{}{},
	}

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

	task, err := app.StartApp2("Variation", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting variation analysis: %w", err)
	}

	fmt.Printf("Submitted variation analysis with id %s\n", task.GetID())
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
