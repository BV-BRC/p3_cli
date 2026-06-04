// Command p3-submit-genome-assembly submits a genome assembly job.
//
// Usage:
//
//	p3-submit-genome-assembly [options] output-path output-name
//
// This command submits read libraries to the BV-BRC genome assembly service.
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
	baseURL            string
	containerID        string

	// Read library options
	pairedEndLibs    []string
	interleavedLibs  []string
	singleEndLibs    []string
	srrIDs           []string
	platform         string
	readOrientation  string

	// Assembly options
	recipe        string
	trimReads     bool
	raconIter     int
	pilonIter     int
	minContigLen  int
	minContigCov  int
	genomeSize    string
	pipeline      string
)

var rootCmd = &cobra.Command{
	Use:   "p3-submit-genome-assembly [options] output-path output-name",
	Short: "Submit a genome assembly job to BV-BRC",
	Long: `Submit read libraries to the BV-BRC genome assembly service.

Examples:

  # Assemble paired-end reads
  p3-submit-genome-assembly --paired-end-lib reads_1.fq,reads_2.fq \n    /username@patricbrc.org/home/assemblies MyAssembly

  # Assemble from SRA
  p3-submit-genome-assembly --srr-id SRR12345 \n    /username@patricbrc.org/home/assemblies MyAssembly

  # Assemble with specific recipe
  p3-submit-genome-assembly --paired-end-lib reads_1.fq,reads_2.fq \n    --recipe unicycler /username@patricbrc.org/home/assemblies MyAssembly`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")
	rootCmd.Flags().StringVar(&baseURL, "base-url", "https://www.bv-brc.org", "site base URL")
	rootCmd.Flags().StringVar(&containerID, "container-id", "", "container ID")

	// Read library options
	rootCmd.Flags().StringArrayVar(&pairedEndLibs, "paired-end-lib", nil, "paired-end read library (file1,file2)")
	rootCmd.Flags().StringArrayVar(&interleavedLibs, "interleaved-lib", nil, "interleaved paired-end library")
	rootCmd.Flags().StringArrayVar(&singleEndLibs, "single-end-lib", nil, "single-end read library")
	rootCmd.Flags().StringArrayVar(&srrIDs, "srr-id", nil, "SRA run ID")
	rootCmd.Flags().StringVar(&platform, "platform", "infer", "sequencing platform (infer, illumina, pacbio, nanopore, iontorrent)")
	rootCmd.Flags().StringVar(&readOrientation, "read-orientation", "inward", "read orientation (inward, outward)")

	// Assembly options
	rootCmd.Flags().StringVar(&recipe, "recipe", "auto", "assembly recipe (auto, unicycler, canu, spades, meta-spades, plasmid-spades, single-cell)")
	rootCmd.Flags().BoolVar(&trimReads, "trim-reads", false, "trim reads before assembly")
	rootCmd.Flags().IntVar(&raconIter, "racon-iter", 0, "number of racon polishing iterations")
	rootCmd.Flags().IntVar(&pilonIter, "pilon-iter", 0, "number of pilon polishing iterations")
	rootCmd.Flags().IntVar(&minContigLen, "min-contig-len", 300, "minimum contig length")
	rootCmd.Flags().IntVar(&minContigCov, "min-contig-cov", 5, "minimum contig coverage")
	rootCmd.Flags().StringVar(&genomeSize, "genome-size", "", "estimated genome size (for canu)")
	rootCmd.Flags().StringVar(&pipeline, "pipeline", "", "assembly pipeline")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate that we have at least one input
	if len(pairedEndLibs) == 0 && len(interleavedLibs) == 0 && len(singleEndLibs) == 0 && len(srrIDs) == 0 {
		return fmt.Errorf("at least one read library or SRR ID must be specified")
	}

	// Get auth token
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to submit assembly jobs")
	}

	// Create clients
	ws := workspace.New(workspace.WithToken(token))
	app := appservice.New(appservice.WithToken(token))

	// Clean output path
	outputPath = strings.TrimPrefix(outputPath, "ws:")
	outputPath = expandWorkspacePath(outputPath)
	outputPath = strings.TrimSuffix(outputPath, "/")

	// Verify output path exists and is a folder
	meta, err := ws.Stat(outputPath, false)
	if err != nil || !meta.IsFolder() {
		return fmt.Errorf("output path %s does not exist or is not a directory", outputPath)
	}

	// Set upload path default
	if workspaceUploadDir == "" {
		workspaceUploadDir = outputPath
	}

	readOrientationOutward := readOrientation == "outward"

	// Build parameters
	params := map[string]interface{}{
		"output_path":     outputPath,
		"output_file":     outputName,
		"recipe":          recipe,
		"min_contig_len":  minContigLen,
		"min_contig_cov":  minContigCov,
		"trim_reads":      trimReads,
		"paired_end_libs": []map[string]interface{}{},
		"single_end_libs": []map[string]interface{}{},
		"srr_ids":         srrIDs,
	}

	if pipeline != "" {
		params["pipeline"] = pipeline
	}
	if raconIter > 0 {
		params["racon_iter"] = raconIter
	}
	if pilonIter > 0 {
		params["pilon_iter"] = pilonIter
	}

	// Process paired-end libraries
	pairedLibs := params["paired_end_libs"].([]map[string]interface{})
	for _, lib := range pairedEndLibs {
		parts := strings.Split(lib, ",")
		if len(parts) != 2 {
			return fmt.Errorf("paired-end library must have two files separated by comma: %s", lib)
		}
		read1, err := processFilename(ws, parts[0], token)
		if err != nil {
			return err
		}
		read2, err := processFilename(ws, parts[1], token)
		if err != nil {
			return err
		}
		pairedLibs = append(pairedLibs, map[string]interface{}{
			"read1":                     read1,
			"read2":                     read2,
			"platform":                  platform,
			"interleaved":               false,
			"read_orientation_outward":  readOrientationOutward,
		})
	}

	// Process interleaved libraries
	for _, lib := range interleavedLibs {
		read1, err := processFilename(ws, lib, token)
		if err != nil {
			return err
		}
		pairedLibs = append(pairedLibs, map[string]interface{}{
			"read1":                     read1,
			"platform":                  platform,
			"interleaved":               true,
			"read_orientation_outward":  readOrientationOutward,
		})
	}
	params["paired_end_libs"] = pairedLibs

	// Process single-end libraries
	singleLibs := params["single_end_libs"].([]map[string]interface{})
	for _, lib := range singleEndLibs {
		read, err := processFilename(ws, lib, token)
		if err != nil {
			return err
		}
		singleLibs = append(singleLibs, map[string]interface{}{
			"read":     read,
			"platform": platform,
		})
	}
	params["single_end_libs"] = singleLibs

	// Build start params
	startParams := appservice.StartParams{}
	if baseURL != "" {
		startParams.BaseURL = baseURL
	}
	if containerID != "" {
		startParams.ContainerID = containerID
	}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		fmt.Println("Start parameters:")
		startJSON, _ := json.MarshalIndent(startParams, "", "  ")
		fmt.Println(string(startJSON))
		return nil
	}

	// Submit the job
	task, err := app.StartApp2("GenomeAssembly2", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting assembly: %w", err)
	}

	fmt.Printf("Submitted assembly with id %s\n", task.GetID())
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

func processFilename(ws *workspace.Client, path string, token *auth.Token) (string, error) {
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

	fmt.Printf("Uploading %s to %s (%s)...\n", path, wsPath, formatSize(int64(len(data))))
	_, err = ws.Create(workspace.CreateParams{
		Objects: []workspace.CreateObject{{
			Path: wsPath,
			Type: "reads",
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

func formatSize(size int64) string {
	if size > 1e9 {
		return fmt.Sprintf("%.1f GB", float64(size)/1e9)
	}
	if size > 1e6 {
		return fmt.Sprintf("%.1f MB", float64(size)/1e6)
	}
	if size > 1e3 {
		return fmt.Sprintf("%.1f KB", float64(size)/1e3)
	}
	return fmt.Sprintf("%d bytes", size)
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
