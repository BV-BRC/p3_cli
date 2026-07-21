// Command p3-submit-viral-assembly submits a viral assembly job.
//
// Usage:
//
//	p3-submit-viral-assembly [options] output-path output-name
//
// This command submits reads to the viral genome assembly service.
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

	pairedEndLib string
	singleEndLib string
	srrID        string
	strategy     string
)

var validStrategies = map[string]bool{
	"auto": true, "IRMA": true,
}

var rootCmd = &cobra.Command{
	Use:   "p3-submit-viral-assembly [options] output-path output-name",
	Short: "Submit a viral assembly job to BV-BRC",
	Long: `Submit reads to the viral genome assembly service.

Examples:

  # Assemble from paired-end reads
  p3-submit-viral-assembly --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/viral MyAssembly

  # Assemble from SRA
  p3-submit-viral-assembly --srr-id SRR12345 \
    /username@patricbrc.org/home/viral MyAssembly`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	rootCmd.Flags().StringVar(&pairedEndLib, "paired-end-lib", "", "paired-end read library (file1,file2)")
	rootCmd.Flags().StringVar(&singleEndLib, "single-end-lib", "", "single-end read library")
	rootCmd.Flags().StringVar(&srrID, "srr-id", "", "SRA run ID")
	rootCmd.Flags().StringVar(&strategy, "strategy", "auto", "assembly strategy (auto, IRMA)")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate strategy
	if !validStrategies[strategy] {
		return fmt.Errorf("invalid strategy: %s (must be auto or IRMA)", strategy)
	}

	// Validate input
	inputCount := 0
	if pairedEndLib != "" {
		inputCount++
	}
	if singleEndLib != "" {
		inputCount++
	}
	if srrID != "" {
		inputCount++
	}
	if inputCount == 0 {
		return fmt.Errorf("must specify one of --paired-end-lib, --single-end-lib, or --srr-id")
	}
	if inputCount > 1 {
		return fmt.Errorf("only one input type can be specified")
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
		"recipe":      strategy,
		"module":      "FLU",
		"output_path": outputPath,
		"output_file": outputName,
	}

	if pairedEndLib != "" {
		parts := strings.Split(pairedEndLib, ",")
		if len(parts) != 2 {
			return fmt.Errorf("paired-end library must have two files separated by comma: %s", pairedEndLib)
		}
		read1, err := processFilename(ws, parts[0], "reads", token)
		if err != nil {
			return err
		}
		read2, err := processFilename(ws, parts[1], "reads", token)
		if err != nil {
			return err
		}
		params["paired_end_lib"] = map[string]string{
			"read1": read1,
			"read2": read2,
		}
	}

	if singleEndLib != "" {
		read, err := processFilename(ws, singleEndLib, "reads", token)
		if err != nil {
			return err
		}
		params["single_end_lib"] = map[string]string{
			"read": read,
		}
	}

	if srrID != "" {
		params["srr_id"] = srrID
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	task, err := app.StartApp2("ViralAssembly", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting viral assembly: %w", err)
	}

	fmt.Printf("Submitted viral assembly with id %s\n", task.GetID())
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
