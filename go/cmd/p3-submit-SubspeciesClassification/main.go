// Command p3-submit-SubspeciesClassification submits a subspecies classification job.
//
// Usage:
//
//	p3-submit-SubspeciesClassification [options] output-path output-name
//
// This command classifies viral contigs into the appropriate taxonomic tree.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
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

	fastaFile string
	virusType string
	showNames bool
)

var virusTypes = map[string]string{
	"BOVDIARRHEA1": "Flaviviridae - Bovine viral diarrhea virus",
	"DENGUE":       "Flaviviridae - Dengue virus",
	"HCV":          "Flaviviridae - Hepatitis C virus",
	"INFLUENZAH5":  "Orthomyxoviridae - Influenza A H5",
	"JAPANENCEPH":  "Flaviviridae - Japanese encephalitis virus",
	"MASTADENO_A":  "Adenoviridae - Human mastadenovirus A",
	"MASTADENO_B":  "Adenoviridae - Human mastadenovirus B",
	"MASTADENO_C":  "Adenoviridae - Human mastadenovirus C",
	"MASTADENO_E":  "Adenoviridae - Human mastadenovirus E",
	"MASTADENO_F":  "Adenoviridae - Human mastadenovirus F",
	"MEASLES":      "Paramyxoviridae - Measles morbilivirus",
	"MPOX":         "Poxviridae - Monkeypox virus",
	"MUMPS":        "Paramyxoviridae - Mumps orthorubulavirus",
	"MURRAY":       "Flaviviridae - Murray Valley encephalitis virus",
	"NOROORF1":     "Caliciviridae - Norovirus [VP1]",
	"NOROORF2":     "Caliciviridae - Norovirus [VP2]",
	"ROTAA":        "Reoviridae - Rotavirus A",
	"STLOUIS":      "Flaviviridae - St. Louis encephalitis virus",
	"SWINEH1":      "Orthomyxoviridae - Swine influenza H1 (global)",
	"SWINEH1US":    "Orthomyxoviridae - Swine influenza H1 (US)",
	"SWINEH3":      "Orthomyxoviridae - Swine influenza H3 (global)",
	"TKBENCEPH":    "Flaviviridae - Tick-borne encephalitis virus",
	"WESTNILE":     "Flaviviridae - West Nile virus",
	"YELLOWFEVER":  "Flaviviridae - Yellow fever",
	"ZIKA":         "Flaviviridae - Zika virus",
}

var rootCmd = &cobra.Command{
	Use:   "p3-submit-SubspeciesClassification [options] output-path output-name",
	Short: "Submit a subspecies classification job to BV-BRC",
	Long: `Classify viral contigs into the appropriate taxonomic tree.

Examples:

  # Classify influenza sequences
  p3-submit-SubspeciesClassification --virus-type INFLUENZAH5 \
    --fasta-file sequences.fasta \
    /username@patricbrc.org/home/classification MyClassification

  # Show available virus types
  p3-submit-SubspeciesClassification --show-names`,
	Args: func(cmd *cobra.Command, args []string) error {
		if showNames {
			return nil
		}
		if len(args) != 2 {
			return fmt.Errorf("requires output-path and output-name arguments")
		}
		return nil
	},
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	rootCmd.Flags().StringVar(&fastaFile, "fasta-file", "", "FASTA file containing viral sequences")
	rootCmd.Flags().StringVar(&virusType, "virus-type", "INFLUENZAH5", "virus type code")
	rootCmd.Flags().BoolVar(&showNames, "show-names", false, "display valid virus types and exit")
}

func run(cmd *cobra.Command, args []string) error {
	// Handle show-names
	if showNames {
		fmt.Printf("%-20s %s\n", "virus_type", "name")
		var keys []string
		for k := range virusTypes {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			fmt.Printf("%-20s %s\n", k, virusTypes[k])
		}
		return nil
	}

	outputPath := args[0]
	outputName := args[1]

	// Validate virus type
	if _, ok := virusTypes[virusType]; !ok {
		return fmt.Errorf("invalid virus type: %s (use --show-names to see valid types)", virusType)
	}

	// Validate input
	if fastaFile == "" {
		return fmt.Errorf("--fasta-file is required")
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

	wsPath, err := processFilename(ws, fastaFile, "contigs", token)
	if err != nil {
		return err
	}

	params := map[string]interface{}{
		"virus_type":       virusType,
		"input_source":     "fasta_file",
		"input_fasta_file": wsPath,
		"output_path":      outputPath,
		"output_file":      outputName,
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	task, err := app.StartApp2("SubspeciesClassification", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting subspecies classification: %w", err)
	}

	fmt.Printf("Submitted subspecies classification with id %s\n", task.GetID())
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
