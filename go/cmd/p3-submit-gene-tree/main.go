// Command p3-submit-gene-tree submits a gene phylogeny tree job.
//
// Usage:
//
//	p3-submit-gene-tree [options] output-path output-name
//
// This command submits a request to build a phylogenetic tree of protein sequences.
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

	sequenceFiles     []string
	trimThreshold     float64
	gapThreshold      float64
	dnaFlag           bool
	substitutionModel string
	recipe            string
)

var validRecipes = map[string]bool{
	"RAxML":    true,
	"PhyML":    true,
	"FastTree": true,
}

var validSubModels = map[string]bool{
	"HKY85": true, "JC69": true, "K80": true, "F81": true, "F84": true,
	"TN93": true, "GTR": true, "LG": true, "WAG": true, "JTT": true,
	"MtREV": true, "Dayhoff": true, "DCMut": true, "RtREV": true,
	"CpREV": true, "VT": true, "AB": true, "Blosum62": true,
	"MtMam": true, "MtArt": true, "HIVw": true, "HIVb": true,
}

var rootCmd = &cobra.Command{
	Use:   "p3-submit-gene-tree [options] output-path output-name",
	Short: "Submit a gene phylogeny tree job to BV-BRC",
	Long: `Submit a request to build a phylogenetic tree of protein or DNA sequences.

Examples:

  # Build a tree from protein sequences
  p3-submit-gene-tree --sequences proteins.faa \
    /username@patricbrc.org/home/trees MyTree

  # Build a tree from DNA sequences using FastTree
  p3-submit-gene-tree --dna --recipe FastTree --sequences genes.fna \
    /username@patricbrc.org/home/trees MyTree

  # Specify substitution model
  p3-submit-gene-tree --sequences proteins.faa --substitution-model WAG \
    /username@patricbrc.org/home/trees MyTree`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	rootCmd.Flags().StringArrayVar(&sequenceFiles, "sequences", nil, "FASTA sequence file (can be specified multiple times)")
	rootCmd.Flags().Float64Var(&trimThreshold, "trim-threshold", 0, "alignment end-trimming threshold")
	rootCmd.Flags().Float64Var(&gapThreshold, "gap-threshold", 0, "threshold for deleting alignments with large gaps")
	rootCmd.Flags().BoolVar(&dnaFlag, "dna", false, "input sequences are DNA (default is protein)")
	rootCmd.Flags().StringVar(&substitutionModel, "substitution-model", "", "substitution model to use")
	rootCmd.Flags().StringVar(&recipe, "recipe", "RAxML", "tree-building recipe (RAxML, PhyML, FastTree)")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate recipe
	if !validRecipes[recipe] {
		return fmt.Errorf("invalid recipe: %s (must be RAxML, PhyML, or FastTree)", recipe)
	}

	// Validate substitution model if specified
	if substitutionModel != "" && !validSubModels[substitutionModel] {
		return fmt.Errorf("invalid substitution model: %s", substitutionModel)
	}

	// Validate input
	if len(sequenceFiles) == 0 {
		return fmt.Errorf("at least one --sequences file must be specified")
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

	// Determine file type and alphabet
	var fileType, alphabet string
	if dnaFlag {
		fileType = "feature_dna_fasta"
		alphabet = "DNA"
	} else {
		fileType = "feature_protein_fasta"
		alphabet = "Protein"
	}

	// Process sequence files
	var sequences []map[string]string
	for _, file := range sequenceFiles {
		wsPath, err := processFilename(ws, file, fileType, token)
		if err != nil {
			return err
		}
		sequences = append(sequences, map[string]string{
			"filename": wsPath,
			"type":     "FASTA",
		})
	}

	// Build parameters
	params := map[string]interface{}{
		"sequences":   sequences,
		"alphabet":    alphabet,
		"recipe":      recipe,
		"output_path": outputPath,
		"output_file": outputName,
	}

	// Add optional parameters
	if trimThreshold > 0 {
		params["trim_threshold"] = trimThreshold
	}
	if gapThreshold > 0 {
		params["gap_threshold"] = gapThreshold
	}
	if substitutionModel != "" {
		params["substitution_model"] = substitutionModel
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	// Submit the job
	task, err := app.StartApp2("GeneTree", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting gene tree: %w", err)
	}

	fmt.Printf("Submitted gene tree with id %s\n", task.GetID())
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
