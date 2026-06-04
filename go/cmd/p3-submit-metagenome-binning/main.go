// Command p3-submit-metagenome-binning submits a metagenome binning job.
//
// Usage:
//
//	p3-submit-metagenome-binning [options] output-path output-name
//
// This command submits reads or contigs for metagenomic binning.
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

	pairedEndLibs []string
	singleEndLibs []string
	srrIDs        []string
	contigs       string
	genomeGroup   string
	skipIndexing  bool
	prokaryotes   bool
	viruses       bool
	danglen       int
)

var rootCmd = &cobra.Command{
	Use:   "p3-submit-metagenome-binning [options] output-path output-name",
	Short: "Submit a metagenome binning job to BV-BRC",
	Long: `Submit reads or contigs for metagenomic binning.

Examples:

  # Bin from paired-end reads
  p3-submit-metagenome-binning --paired-end-lib reads_1.fq,reads_2.fq \
    /username@patricbrc.org/home/binning MyBinning

  # Bin from existing contigs
  p3-submit-metagenome-binning --contigs contigs.fasta \
    /username@patricbrc.org/home/binning MyBinning

  # Bin only viruses
  p3-submit-metagenome-binning --viruses --contigs contigs.fasta \
    /username@patricbrc.org/home/binning MyBinning`,
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
	rootCmd.Flags().StringVar(&contigs, "contigs", "", "input FASTA file of assembled contigs")
	rootCmd.Flags().StringVar(&genomeGroup, "genome-group", "", "group name for output genomes")
	rootCmd.Flags().BoolVar(&skipIndexing, "skip-indexing", false, "do not add genomes to BV-BRC database")
	rootCmd.Flags().BoolVar(&prokaryotes, "prokaryotes", false, "perform bacterial/archaeal binning")
	rootCmd.Flags().BoolVar(&viruses, "viruses", false, "perform viral binning")
	rootCmd.Flags().IntVar(&danglen, "danglen", 50, "DNA kmer length for dangling contigs (0 to disable)")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate input
	hasReads := len(pairedEndLibs) > 0 || len(singleEndLibs) > 0 || len(srrIDs) > 0
	if contigs != "" && hasReads {
		return fmt.Errorf("cannot specify both contigs and FASTQ input")
	}
	if contigs == "" && !hasReads {
		return fmt.Errorf("must specify either contigs or FASTQ input")
	}

	// Default to both if neither specified
	if !prokaryotes && !viruses {
		prokaryotes = true
		viruses = true
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

	skipIndexStr := "false"
	if skipIndexing {
		skipIndexStr = "true"
	}
	prokStr := "false"
	if prokaryotes {
		prokStr = "true"
	}
	viralStr := "false"
	if viruses {
		viralStr = "true"
	}

	params := map[string]interface{}{
		"skip_indexing":                 skipIndexStr,
		"output_path":                   outputPath,
		"output_file":                   outputName,
		"assembler":                     "auto",
		"perform_bacterial_annotation":  prokStr,
		"perform_viral_annotation":      viralStr,
		"danglen":                       danglen,
	}

	if genomeGroup != "" {
		params["genome_group"] = genomeGroup
	}

	if contigs != "" {
		wsPath, err := processFilename(ws, contigs, "contigs", token)
		if err != nil {
			return err
		}
		params["contigs"] = wsPath
	} else {
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
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	task, err := app.StartApp2("MetagenomeBinning", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting metagenome binning: %w", err)
	}

	fmt.Printf("Submitted metagenome binning with id %s\n", task.GetID())
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
