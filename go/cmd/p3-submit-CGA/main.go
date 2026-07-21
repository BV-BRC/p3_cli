// Command p3-submit-CGA submits a Comprehensive Genome Analysis job.
//
// Usage:
//
//	p3-submit-CGA [options] output-path output-name
//
// This command submits a CGA job that performs assembly (if needed) and annotation.
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

	// Read library options
	pairedEndLibs   []string
	singleEndLibs   []string
	srrIDs          []string
	platform        string
	readOrientation string

	// Assembly options
	contigs       string
	recipe        string
	trimReads     bool
	raconIter     int
	pilonIter     int
	minContigLen  int
	minContigCov  float64

	// Annotation options
	scientificName string
	taxonomyID     int
	code           int
	domain         string
	label          string
)

var validRecipes = map[string]bool{
	"auto": true, "full_spades": true, "fast": true, "miseq": true, "smart": true, "kiki": true,
}

var validDomains = map[string]string{
	"A": "Archaea", "Archaea": "Archaea", "B": "Bacteria", "Bacteria": "Bacteria",
}

var rootCmd = &cobra.Command{
	Use:   "p3-submit-CGA [options] output-path output-name",
	Short: "Submit a Comprehensive Genome Analysis job to BV-BRC",
	Long: `Submit a CGA job that performs assembly (if needed) and annotation.

Examples:

  # Assemble and annotate from reads
  p3-submit-CGA --scientific-name "Escherichia coli" --taxonomy-id 562 \
    --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/cga MyAnalysis

  # Annotate from existing contigs
  p3-submit-CGA --scientific-name "Escherichia coli" --taxonomy-id 562 \
    --contigs contigs.fasta \
    /username@patricbrc.org/home/cga MyAnalysis`,
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
	rootCmd.Flags().StringVar(&platform, "platform", "infer", "sequencing platform (infer, illumina, pacbio, nanopore)")
	rootCmd.Flags().StringVar(&readOrientation, "read-orientation", "inward", "read orientation (inward, outward)")

	// Assembly options
	rootCmd.Flags().StringVar(&contigs, "contigs", "", "input FASTA file of assembled contigs")
	rootCmd.Flags().StringVar(&recipe, "recipe", "auto", "assembly recipe (auto, full_spades, fast, miseq, smart, kiki)")
	rootCmd.Flags().BoolVar(&trimReads, "trim", false, "trim reads before assembly")
	rootCmd.Flags().IntVar(&raconIter, "racon-iter", 2, "number of racon iterations")
	rootCmd.Flags().IntVar(&pilonIter, "pilon-iter", 2, "number of pilon iterations")
	rootCmd.Flags().IntVar(&minContigLen, "min-contig-length", 300, "minimum contig length")
	rootCmd.Flags().Float64Var(&minContigCov, "min-contig-cov", 5, "minimum contig coverage")

	// Annotation options
	rootCmd.Flags().StringVar(&scientificName, "scientific-name", "", "scientific name of genome")
	rootCmd.Flags().IntVar(&taxonomyID, "taxonomy-id", 0, "NCBI taxonomy ID")
	rootCmd.Flags().IntVar(&code, "code", 11, "genetic code (4 or 11)")
	rootCmd.Flags().StringVar(&domain, "domain", "Bacteria", "domain (Bacteria or Archaea)")
	rootCmd.Flags().StringVar(&label, "label", "", "label to add to scientific name")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate recipe
	if !validRecipes[recipe] {
		return fmt.Errorf("invalid recipe: %s", recipe)
	}

	// Validate domain
	realDomain, ok := validDomains[domain]
	if !ok {
		return fmt.Errorf("invalid domain: %s (must be Bacteria or Archaea)", domain)
	}

	// Validate input type
	hasReads := len(pairedEndLibs) > 0 || len(singleEndLibs) > 0 || len(srrIDs) > 0
	if contigs != "" && hasReads {
		return fmt.Errorf("cannot specify both contigs and FASTQ input")
	}
	if contigs == "" && !hasReads {
		return fmt.Errorf("must specify either contigs or FASTQ input")
	}

	// Validate taxonomy
	if taxonomyID == 0 {
		return fmt.Errorf("taxonomy-id is required")
	}
	if scientificName == "" {
		return fmt.Errorf("scientific-name is required")
	}

	// Add label to scientific name if provided
	if label != "" {
		scientificName = scientificName + " " + label
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

	// Determine input type
	inputType := "reads"
	if contigs != "" {
		inputType = "contigs"
	}

	readOrientationOutward := readOrientation == "outward"

	// Build parameters
	params := map[string]interface{}{
		"input_type":        inputType,
		"min_contig_length": minContigLen,
		"min_contig_cov":    minContigCov,
		"trim":              trimReads,
		"taxonomy_id":       taxonomyID,
		"scientific_name":   scientificName,
		"racon_iter":        raconIter,
		"pilon_iter":        pilonIter,
		"recipe":            recipe,
		"code":              code,
		"domain":            realDomain,
		"output_path":       outputPath,
		"output_file":       outputName,
		"skip_indexing":     0,
	}

	if contigs != "" {
		wsPath, err := processFilename(ws, contigs, "contigs", token)
		if err != nil {
			return err
		}
		params["contigs"] = wsPath
	} else {
		// Process read libraries
		params["paired_end_libs"] = []map[string]interface{}{}
		params["single_end_libs"] = []map[string]interface{}{}
		params["srr_ids"] = srrIDs

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
				"read1":                    read1,
				"read2":                    read2,
				"platform":                 platform,
				"interleaved":              false,
				"read_orientation_outward": readOrientationOutward,
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
				"read":     read,
				"platform": platform,
			})
		}
		params["single_end_libs"] = singleLibs
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	// Submit the job
	task, err := app.StartApp2("ComprehensiveGenomeAnalysis", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting CGA: %w", err)
	}

	fmt.Printf("Submitted CGA with id %s\n", task.GetID())
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

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
