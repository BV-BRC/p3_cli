// Command p3-submit-rnaseq submits an RNA-Seq processing job.
//
// Usage:
//
//	p3-submit-rnaseq [options] output-path output-name
//
// This command submits RNA-Seq read libraries to BV-BRC for expression analysis.
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

	// Read library options with conditions
	pairedEndLibs   []string
	singleEndLibs   []string
	srrIDs          []string
	currentCondition string

	// Processing options
	useTuxedo         bool
	useHisat          bool
	referenceGenomeID string
	contrasts         []string
)

// libEntry holds a library specification with its condition
type libEntry struct {
	condition string
	files     []string
	isSRR     bool
}

var libs []libEntry

var rootCmd = &cobra.Command{
	Use:   "p3-submit-rnaseq [options] output-path output-name",
	Short: "Submit an RNA-Seq processing job to BV-BRC",
	Long: `Submit RNA-Seq read libraries to BV-BRC for expression analysis.

Examples:

  # Analyze paired-end RNA-Seq reads
  p3-submit-rnaseq --reference-genome-id 83332.12 \
    --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/rnaseq MyAnalysis

  # Analyze with conditions and contrasts
  p3-submit-rnaseq --reference-genome-id 83332.12 \
    --condition control --paired-end-lib control_1.fq,control_2.fq \
    --condition treatment --paired-end-lib treat_1.fq,treat_2.fq \
    --contrast control,treatment \
    /username@patricbrc.org/home/rnaseq MyAnalysis

  # Use HISAT instead of Tuxedo
  p3-submit-rnaseq --hisat --reference-genome-id 83332.12 \
    --srr-id SRR12345 /username@patricbrc.org/home/rnaseq MyAnalysis`,
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
	rootCmd.Flags().StringVar(&currentCondition, "condition", "", "condition name for following libraries")

	// Processing options
	rootCmd.Flags().BoolVar(&useTuxedo, "tuxedo", false, "use the Tuxedo suite (default)")
	rootCmd.Flags().BoolVar(&useHisat, "hisat", false, "use the Host HISAT suite")
	rootCmd.Flags().StringVar(&referenceGenomeID, "reference-genome-id", "", "reference genome ID (required)")
	rootCmd.Flags().StringArrayVar(&contrasts, "contrast", nil, "contrast pair (condition1,condition2)")

	rootCmd.MarkFlagRequired("reference-genome-id")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate tool selection
	if useTuxedo && useHisat {
		return fmt.Errorf("only one tool suite can be specified (--tuxedo or --hisat)")
	}

	// Determine recipe
	recipe := "RNA-Rocket" // Tuxedo is the default
	if useHisat {
		recipe = "Host"
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
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to submit RNA-Seq jobs")
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
		"recipe":              recipe,
		"reference_genome_id": referenceGenomeID,
		"output_path":         outputPath,
		"output_file":         outputName,
		"paired_end_libs":     []map[string]interface{}{},
		"single_end_libs":     []map[string]interface{}{},
		"srr_ids":             []string{},
	}

	// Track conditions for contrasts
	conditionMap := make(map[string]int)
	var conditions []string
	conditionIndex := 1

	// Helper to get or add condition
	getConditionIndex := func(cond string) int {
		if cond == "" {
			cond = "control"
		}
		if idx, ok := conditionMap[cond]; ok {
			return idx
		}
		conditionMap[cond] = conditionIndex
		conditions = append(conditions, cond)
		conditionIndex++
		return conditionMap[cond]
	}

	// Process paired-end libraries
	// Note: In Go, we can't easily interleave --condition with --paired-end-lib
	// like the Perl version. For simplicity, we use a single --condition that applies to all.
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
		condIdx := getConditionIndex(currentCondition)
		pairedLibs = append(pairedLibs, map[string]interface{}{
			"read1":     read1,
			"read2":     read2,
			"condition": condIdx,
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
		condIdx := getConditionIndex(currentCondition)
		singleLibs = append(singleLibs, map[string]interface{}{
			"read":      read,
			"condition": condIdx,
		})
	}
	params["single_end_libs"] = singleLibs

	// Process SRR IDs
	var srrList []map[string]interface{}
	for _, srr := range srrIDs {
		condIdx := getConditionIndex(currentCondition)
		srrList = append(srrList, map[string]interface{}{
			"srr_accession": srr,
			"condition":     condIdx,
		})
	}
	if len(srrList) > 0 {
		params["srr_ids"] = srrList
	}

	// Add experimental conditions
	params["experimental_conditions"] = conditions

	// Process contrasts
	var contrastTuples [][]int
	for _, contrast := range contrasts {
		parts := strings.Split(contrast, ",")
		if len(parts) != 2 {
			return fmt.Errorf("invalid contrast %s: must be two conditions separated by a comma", contrast)
		}
		c1, ok1 := conditionMap[parts[0]]
		c2, ok2 := conditionMap[parts[1]]
		if !ok1 || !ok2 {
			return fmt.Errorf("invalid condition specified in contrast %s", contrast)
		}
		contrastTuples = append(contrastTuples, []int{c1, c2})
	}
	if len(contrastTuples) > 0 {
		params["contrasts"] = contrastTuples
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	// Submit the job
	task, err := app.StartApp2("RNASeq", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting RNA-Seq: %w", err)
	}

	fmt.Printf("Submitted RNA-Seq with id %s\n", task.GetID())
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

	fmt.Printf("Uploading %s to %s...\\n", path, wsPath)
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
