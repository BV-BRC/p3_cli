// Command p3-submit-MSA submits a multiple sequence alignment job.
//
// Usage:
//
//	p3-submit-MSA [options] output-path output-name
//
// This command submits sequences to the BV-BRC MSA service.
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

	aligner       string
	alphabet      string
	fastaFiles    []string
	featureGroups []string
)

var alphabetTypeMap = map[string]string{
	"dna":     "feature_dna_fasta",
	"protein": "feature_protein_fasta",
}

var validAligners = map[string]bool{
	"Muscle": true,
	"Mafft":  true,
}

var rootCmd = &cobra.Command{
	Use:   "p3-submit-MSA [options] output-path output-name",
	Short: "Submit a multiple sequence alignment job to BV-BRC",
	Long: `Submit sequences to the BV-BRC multiple sequence alignment service.

Examples:

  # Align sequences from a FASTA file
  p3-submit-MSA --fasta-file sequences.fasta \n    /username@patricbrc.org/home/msa MyAlignment

  # Align protein sequences using Mafft
  p3-submit-MSA --alphabet protein --aligner Mafft \n    --fasta-file proteins.faa /username@patricbrc.org/home/msa MyAlignment

  # Align from a feature group
  p3-submit-MSA --feature-group /username@patricbrc.org/home/features.group \n    /username@patricbrc.org/home/msa MyAlignment`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	rootCmd.Flags().StringVar(&aligner, "aligner", "Muscle", "aligner to use (Muscle or Mafft)")
	rootCmd.Flags().StringVar(&alphabet, "alphabet", "dna", "sequence type (dna or protein)")
	rootCmd.Flags().StringArrayVar(&fastaFiles, "fasta-file", nil, "FASTA file to align")
	rootCmd.Flags().StringArrayVar(&featureGroups, "feature-group", nil, "feature group to align")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate aligner
	if !validAligners[aligner] {
		return fmt.Errorf("invalid aligner: %s (must be Muscle or Mafft)", aligner)
	}

	// Validate alphabet
	fileType, ok := alphabetTypeMap[alphabet]
	if !ok {
		return fmt.Errorf("invalid alphabet: %s (must be dna or protein)", alphabet)
	}

	// Validate input
	if len(fastaFiles) == 0 && len(featureGroups) == 0 {
		return fmt.Errorf("must specify either --fasta-file or --feature-group")
	}

	// Get auth token
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to submit MSA jobs")
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
		"alphabet":    alphabet,
		"aligner":     aligner,
		"output_path": outputPath,
		"output_file": outputName,
	}

	// Process FASTA files
	if len(fastaFiles) > 0 {
		var files []map[string]string
		for _, file := range fastaFiles {
			wsPath, err := processFilename(ws, file, fileType, token)
			if err != nil {
				return err
			}
			files = append(files, map[string]string{
				"file": wsPath,
				"type": fileType,
			})
		}
		params["fasta_files"] = files
	}

	// Process feature groups
	if len(featureGroups) > 0 {
		var groups []string
		for _, group := range featureGroups {
			group = strings.TrimPrefix(group, "ws:")
			group = expandWorkspacePath(group)
			groups = append(groups, group)
		}
		params["feature_groups"] = groups
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	// Submit the job
	task, err := app.StartApp2("MSA", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting MSA: %w", err)
	}

	fmt.Printf("Submitted MSA with id %s\n", task.GetID())
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
