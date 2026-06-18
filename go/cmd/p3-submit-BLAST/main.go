// Command p3-submit-BLAST submits a BLAST job.
//
// Usage:
//
//	p3-submit-BLAST [options] output-path output-name
//
// This command submits a BLAST search to the BV-BRC service.
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

	// Query options
	inType       string
	inIDList     string
	inFastaFile  string

	// Database options
	dbType       string
	dbFastaFile  string
	dbGenomeList string
	dbTaxonList  string
	dbDatabase   string

	// BLAST parameters
	evalueCutoff float64
	maxHits      int
	minCoverage  int
)

var inputTypeMap = map[string]string{
	"dna": "n",
	"aa":  "p",
}

var inputFileTypeMap = map[string]string{
	"dna": "feature_dna_fasta",
	"aa":  "feature_protein_fasta",
}

var dbTypeMap = map[string]string{
	"fna": "n",
	"ffn": "n",
	"frn": "n",
	"faa": "p",
}

var dbFileTypeMap = map[string]string{
	"fna": "contigs",
	"ffn": "feature_dna_fasta",
	"frn": "feature_dna_fasta",
	"faa": "feature_protein_fasta",
}

var blastProgramMap = map[string]string{
	"nn": "blastn",
	"np": "blastx",
	"pn": "tblastn",
	"pp": "blastp",
}

var validDatabases = map[string]bool{
	"BV-BRC":   true,
	"REFSEQ":   true,
	"Plasmids": true,
	"Phages":   true,
}

var rootCmd = &cobra.Command{
	Use:   "p3-submit-BLAST [options] output-path output-name",
	Short: "Submit a BLAST job to BV-BRC",
	Long: `Submit a BLAST search to the BV-BRC service.

Examples:

  # BLAST protein sequences against a genome list
  p3-submit-BLAST --in-fasta-file query.faa --db-genome-list 83332.12,511145.12 \n    /username@patricbrc.org/home/blast MyBlast

  # BLAST against precomputed database
  p3-submit-BLAST --in-fasta-file query.faa --db-database BV-BRC \n    /username@patricbrc.org/home/blast MyBlast

  # BLAST DNA against contigs
  p3-submit-BLAST --in-type dna --db-type fna \n    --in-fasta-file query.fna --db-fasta-file contigs.fna \n    /username@patricbrc.org/home/blast MyBlast`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")

	// Query options
	rootCmd.Flags().StringVar(&inType, "in-type", "aa", "input type (dna or aa)")
	rootCmd.Flags().StringVar(&inIDList, "in-id-list", "", "comma-delimited list of feature IDs")
	rootCmd.Flags().StringVar(&inFastaFile, "in-fasta-file", "", "FASTA file of query sequences")

	// Database options
	rootCmd.Flags().StringVar(&dbType, "db-type", "faa", "database type (fna, ffn, frn, faa)")
	rootCmd.Flags().StringVar(&dbFastaFile, "db-fasta-file", "", "FASTA file for database")
	rootCmd.Flags().StringVar(&dbGenomeList, "db-genome-list", "", "comma-delimited list of genome IDs or file")
	rootCmd.Flags().StringVar(&dbTaxonList, "db-taxon-list", "", "comma-delimited list of taxon IDs")
	rootCmd.Flags().StringVar(&dbDatabase, "db-database", "", "precomputed database (BV-BRC, REFSEQ, Plasmids, Phages)")

	// BLAST parameters
	rootCmd.Flags().Float64Var(&evalueCutoff, "evalue-cutoff", 1e-5, "maximum e-value cutoff")
	rootCmd.Flags().IntVar(&maxHits, "max-hits", 10, "maximum hits per query")
	rootCmd.Flags().IntVar(&minCoverage, "min-coverage", 0, "minimum percent coverage")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate input type
	qType, ok := inputTypeMap[inType]
	if !ok {
		return fmt.Errorf("invalid input type: %s", inType)
	}

	// Validate database type
	sType, ok := dbTypeMap[dbType]
	if !ok {
		return fmt.Errorf("invalid database type: %s", dbType)
	}

	// Determine BLAST program
	blastProgram := blastProgramMap[qType+sType]
	fmt.Printf("Selected BLAST program is %s.\n", blastProgram)

	// Validate input sources
	if inIDList != "" && inFastaFile != "" {
		return fmt.Errorf("only one type of query input can be specified")
	}
	if inIDList == "" && inFastaFile == "" {
		return fmt.Errorf("no input query specified")
	}

	// Validate database sources
	dbCount := 0
	if dbFastaFile != "" {
		dbCount++
	}
	if dbGenomeList != "" {
		dbCount++
	}
	if dbTaxonList != "" {
		dbCount++
	}
	if dbDatabase != "" {
		dbCount++
	}
	if dbCount > 1 {
		return fmt.Errorf("only one type of subject database can be specified")
	}
	if dbCount == 0 {
		return fmt.Errorf("no database source specified")
	}

	// Validate precomputed database name
	if dbDatabase != "" && !validDatabases[dbDatabase] {
		return fmt.Errorf("invalid precomputed database name: %s", dbDatabase)
	}

	// Validate parameters
	if evalueCutoff < 0 {
		return fmt.Errorf("e-value cutoff must not be negative")
	}
	if maxHits <= 0 {
		return fmt.Errorf("max-hits must be at least 1")
	}
	if minCoverage < 0 || minCoverage > 100 {
		return fmt.Errorf("minimum coverage must be between 0 and 100")
	}

	// Get auth token
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to submit BLAST jobs")
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
		"input_type":           inType,
		"db_type":              dbType,
		"blast_program":        blastProgram,
		"blast_evalue_cutoff":  evalueCutoff,
		"blast_max_hits":       maxHits,
		"blast_min_coverage":   minCoverage,
		"output_path":          outputPath,
		"output_file":          outputName,
	}

	// Process input source
	if inFastaFile != "" {
		wsPath, err := processFilename(ws, inFastaFile, inputFileTypeMap[inType], token)
		if err != nil {
			return err
		}
		params["input_fasta_file"] = wsPath
		params["input_source"] = "fasta_file"
	} else if inIDList != "" {
		params["input_id_list"] = strings.Split(inIDList, ",")
		params["input_source"] = "id_list"
	}

	// Process database source
	if dbFastaFile != "" {
		wsPath, err := processFilename(ws, dbFastaFile, dbFileTypeMap[dbType], token)
		if err != nil {
			return err
		}
		params["db_fasta_file"] = wsPath
		params["db_source"] = "fasta_file"
	} else if dbGenomeList != "" {
		// Check if it's a file or comma-separated list
		genomeIDs, err := parseGenomeList(dbGenomeList)
		if err != nil {
			return err
		}
		params["db_genome_list"] = genomeIDs
		params["db_source"] = "genome_list"
	} else if dbTaxonList != "" {
		params["db_taxon_list"] = strings.Split(dbTaxonList, ",")
		params["db_source"] = "taxon_list"
	} else if dbDatabase != "" {
		params["db_precomputed_database"] = dbDatabase
		params["db_source"] = "precomputed_database"
	}

	startParams := appservice.StartParams{}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		return nil
	}

	// Submit the job
	task, err := app.StartApp2("Homology", params, startParams)
	if err != nil {
		return fmt.Errorf("submitting BLAST: %w", err)
	}

	fmt.Printf("Submitted BLAST with id %s\n", task.GetID())
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

func parseGenomeList(input string) ([]string, error) {
	// Check if input is a file
	info, err := os.Stat(input)
	if err == nil && !info.IsDir() {
		// Read genome IDs from file
		data, err := os.ReadFile(input)
		if err != nil {
			return nil, fmt.Errorf("reading genome list file: %w", err)
		}
		lines := strings.Split(string(data), "\n")
		var ids []string
		for i, line := range lines {
			if i == 0 {
				// Skip header if present
				if strings.Contains(line, "genome") || strings.Contains(line, "id") {
					continue
				}
			}
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			// Take first column if tab-separated
			parts := strings.Split(line, "\t")
			id := strings.TrimSpace(parts[0])
			if id != "" {
				ids = append(ids, id)
			}
		}
		return ids, nil
	}

	// Treat as comma-separated list
	return strings.Split(input, ","), nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
