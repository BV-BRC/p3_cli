// Command p3-submit-taxonomic-classification submits a taxonomic classification job.
//
// Usage:
//
//	p3-submit-taxonomic-classification [options] output-path output-name
//
// This command submits reads to the BV-BRC Kraken2 taxonomic classification service.
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

	// Classification options
	is16S            bool
	analysisType     string
	database         string
	confidence       string
	saveClassified   bool
	saveUnclassified bool
	hostGenome       string
)

var validConfidence = map[string]bool{
	"0": true, "0.1": true, "0.2": true, "0.3": true, "0.4": true,
	"0.5": true, "0.6": true, "0.7": true, "0.8": true, "0.9": true, "1": true,
}

var validDB16S = map[string]bool{"SILVA": true, "Greengenes": true}
var validDBWGS = map[string]bool{"standard": true, "bvbrc": true}
var validHosts = map[string]bool{
	"homo_sapiens": true, "mus_musculus": true, "rattus_norvegicus": true,
	"caenorhabditis_elegans": true, "drosophila_melanogaster_strain": true,
	"danio_rerio_strain_tuebingen": true, "gallus_gallus": true,
	"macaca_mulatta": true, "mustela_putorius_furo": true, "sus_scrofa": true,
	"no_host": true,
}

var rootCmd = &cobra.Command{
	Use:   "p3-submit-taxonomic-classification [options] output-path output-name",
	Short: "Submit a taxonomic classification job to BV-BRC",
	Long: `Submit reads to the BV-BRC Kraken2 taxonomic classification service.

Examples:

  # Classify paired-end reads
  p3-submit-taxonomic-classification --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/classification MyClassification

  # Classify as microbiome sample
  p3-submit-taxonomic-classification --analysis-type microbiome \
    --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/classification MyClassification

  # Classify 16S sequences
  p3-submit-taxonomic-classification --16S --database SILVA \
    --single-end-lib 16s_reads.fq \
    /username@patricbrc.org/home/classification MyClassification`,
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

	// Classification options
	rootCmd.Flags().BoolVar(&is16S, "16S", false, "sample is 16S instead of whole-genome")
	rootCmd.Flags().StringVar(&analysisType, "analysis-type", "", "analysis type (species-identification or microbiome)")
	rootCmd.Flags().StringVar(&database, "database", "", "database to use (bvbrc, standard for WGS; SILVA, Greengenes for 16S)")
	rootCmd.Flags().StringVar(&confidence, "confidence", "0.1", "confidence interval (0, 0.1-0.9, or 1)")
	rootCmd.Flags().BoolVar(&saveClassified, "save-classified", false, "save classified sequences")
	rootCmd.Flags().BoolVar(&saveUnclassified, "save-unclassified", false, "save unclassified sequences")
	rootCmd.Flags().StringVar(&hostGenome, "host-genome", "no_host", "host genome for filtering")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate confidence
	if !validConfidence[confidence] {
		return fmt.Errorf("invalid confidence interval: must be 0, 1, or 0.X where X is a single digit")
	}

	// Validate host genome
	if !validHosts[hostGenome] {
		return fmt.Errorf("invalid host genome: %s", hostGenome)
	}

	// Set defaults and validate based on 16S vs WGS
	var sequenceType string
	if is16S {
		sequenceType = "16S"
		if analysisType == "" {
			analysisType = "16S"
		}
		if analysisType != "16S" {
			return fmt.Errorf("for a 16S sample the analysis type must be 16S")
		}
		if database == "" {
			database = "SILVA"
		}
		if !validDB16S[database] {
			return fmt.Errorf("invalid database for 16S: must be SILVA or Greengenes")
		}
	} else {
		sequenceType = "wgs"
		if analysisType == "" {
			analysisType = "pathogen"
		}
		// Map external name to internal name
		if analysisType == "species-identification" {
			analysisType = "pathogen"
		}
		if analysisType != "pathogen" && analysisType != "microbiome" {
			return fmt.Errorf("invalid analysis type: must be species-identification or microbiome")
		}
		if database == "" {
			database = "bvbrc"
		}
		if !validDBWGS[database] {
			return fmt.Errorf("invalid database for WGS: must be bvbrc or standard")
		}
	}
	_ = sequenceType // Used for documentation purposes

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
		"analysis_type":               analysisType,
		"database":                    database,
		"confidence":                  confidence,
		"save_classified_sequences":   saveClassified,
		"save_unclassified_sequences": saveUnclassified,
		"host_genome":                 hostGenome,
		"output_path":                 outputPath,
		"output_file":                 outputName,
		"paired_end_libs":             []map[string]interface{}{},
		"single_end_libs":             []map[string]interface{}{},
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
	task, err := app.StartApp2("TaxonomicClassification", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting taxonomic classification: %w", err)
	}

	fmt.Printf("Submitted taxonomic classification with id %s\n", task.GetID())
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
