// Command p3-submit-genome-annotation submits a genome annotation job.
//
// Usage:
//
//	p3-submit-genome-annotation [options] output-path output-name
//
// This command submits a genome to the BV-BRC genome annotation service.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/api"
	"github.com/BV-BRC/bvbrc/pkg/appservice"
	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/BV-BRC/bvbrc/pkg/workspace"
	"github.com/spf13/cobra"
)

var (
	workspacePrefix    string
	workspaceUploadDir string
	overwrite          bool
	genbankFile        string
	contigsFile        string
	phage              bool
	recipe             string
	referenceGenome    string
	referenceVirus     string
	scientificName     string
	taxonomyID         int
	geneticCode        int
	domain             string
	workflowFile       string
	importOnly         bool
	rawImportOnly      bool
	skipContigs        bool
	indexNowait        bool
	noIndex            bool
	noWorkspaceOutput  bool
	dryRun             bool
	baseURL            string
	containerID        string
	reservation        string
)

var rootCmd = &cobra.Command{
	Use:   "p3-submit-genome-annotation [options] output-path output-name",
	Short: "Submit a genome annotation job to BV-BRC",
	Long: `Submit a genome to the BV-BRC genome annotation service.

Examples:

  # Annotate a contigs file
  p3-submit-genome-annotation --contigs-file mygenome.fasta \n    --scientific-name "Escherichia coli" --taxonomy-id 562 \n    /username@patricbrc.org/home/genomes MyGenome

  # Annotate a genbank file
  p3-submit-genome-annotation --genbank-file mygenome.gbk \n    /username@patricbrc.org/home/genomes MyGenome

  # Phage annotation
  p3-submit-genome-annotation --contigs-file phage.fasta --phage \n    /username@patricbrc.org/home/phages MyPhage`,
	Args: cobra.ExactArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for workspace pathnames")
	rootCmd.Flags().StringVarP(&workspaceUploadDir, "workspace-upload-path", "P", "", "upload directory for local files")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().StringVar(&genbankFile, "genbank-file", "", "genbank file to annotate")
	rootCmd.Flags().StringVar(&contigsFile, "contigs-file", "", "contigs file to annotate")
	rootCmd.Flags().BoolVar(&phage, "phage", false, "set defaults for phage annotation")
	rootCmd.Flags().StringVar(&recipe, "recipe", "", "annotation recipe")
	rootCmd.Flags().StringVar(&referenceGenome, "reference-genome", "", "reference genome ID")
	rootCmd.Flags().StringVar(&referenceVirus, "reference-virus", "", "reference virus name")
	rootCmd.Flags().StringVarP(&scientificName, "scientific-name", "n", "", "scientific name")
	rootCmd.Flags().IntVarP(&taxonomyID, "taxonomy-id", "t", 0, "NCBI taxonomy ID")
	rootCmd.Flags().IntVarP(&geneticCode, "genetic-code", "g", 0, "genetic code (11 or 4)")
	rootCmd.Flags().StringVarP(&domain, "domain", "d", "", "domain (Bacteria or Archaea)")
	rootCmd.Flags().StringVar(&workflowFile, "workflow-file", "", "custom workflow document")
	rootCmd.Flags().BoolVar(&importOnly, "import-only", false, "import without reannotation")
	rootCmd.Flags().BoolVar(&rawImportOnly, "raw-import-only", false, "raw import without processing")
	rootCmd.Flags().BoolVar(&skipContigs, "skip-contigs", false, "skip loading contigs")
	rootCmd.Flags().BoolVar(&indexNowait, "index-nowait", false, "don't wait for indexing")
	rootCmd.Flags().BoolVar(&noIndex, "no-index", false, "skip indexing")
	rootCmd.Flags().BoolVar(&noWorkspaceOutput, "no-workspace-output", false, "skip workspace output")
	rootCmd.Flags().BoolVar(&dryRun, "dry-run", false, "validate but don't submit")
	rootCmd.Flags().StringVar(&baseURL, "base-url", "https://www.bv-brc.org", "site base URL")
	rootCmd.Flags().StringVar(&containerID, "container-id", "", "container ID")
	rootCmd.Flags().StringVar(&reservation, "reservation", "", "Slurm reservation")
}

func run(cmd *cobra.Command, args []string) error {
	outputPath := args[0]
	outputName := args[1]

	// Validate output name
	if strings.Contains(outputName, "/") {
		return fmt.Errorf("output name may not contain a slash character")
	}

	// Validate input files
	if genbankFile != "" && contigsFile != "" {
		return fmt.Errorf("only one of --genbank-file and --contigs-file may be specified")
	}
	if genbankFile == "" && contigsFile == "" {
		return fmt.Errorf("one of --genbank-file or --contigs-file must be specified")
	}

	// Validate workflow options
	if workflowFile != "" && importOnly {
		return fmt.Errorf("workflow file cannot be used with --import-only")
	}
	if workflowFile != "" && rawImportOnly {
		return fmt.Errorf("workflow file cannot be used with --raw-import-only")
	}
	if workflowFile != "" && recipe != "" {
		return fmt.Errorf("workflow file cannot be used with --recipe")
	}

	// Get auth token
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to submit annotation jobs")
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

	// Verify output path exists and is a folder
	meta, err := ws.Stat(outputPath, false)
	if err != nil || !meta.IsFolder() {
		return fmt.Errorf("output path %s does not exist or is not a directory", outputPath)
	}

	// Process input file
	var inputMode string
	var appName string
	var inputFile string

	if genbankFile != "" {
		inputFile = genbankFile
		inputMode = "genbank"
		appName = "GenomeAnnotationGenbank"
	} else {
		inputFile = contigsFile
		inputMode = "contigs"
		appName = "GenomeAnnotation"
	}

	// Handle file upload if needed
	inputWSPath, err := processFilename(ws, inputFile, token)
	if err != nil {
		return err
	}

	// Set defaults for phage
	defaultDomain := "Bacteria"
	defaultTaxonID := 6666666
	defaultName := "Unknown sp."
	defaultCode := 11

	if phage {
		if recipe == "" {
			recipe = "phage"
		}
		defaultDomain = "Viruses"
	}

	// Build parameters
	params := map[string]interface{}{
		"output_path":  outputPath,
		"output_file":  outputName,
		"queue_nowait": indexNowait,
	}

	if recipe != "" {
		params["recipe"] = recipe
	}
	if noIndex {
		params["skip_indexing"] = 1
	}
	if noWorkspaceOutput {
		params["skip_workspace_output"] = 1
	}
	if referenceVirus != "" {
		params["reference_virus_name"] = referenceVirus
	}

	if inputMode == "genbank" {
		params["genbank_file"] = strings.TrimPrefix(inputWSPath, "ws:")
		params["import_only"] = importOnly
		params["raw_import_only"] = rawImportOnly
		params["skip_contigs"] = skipContigs

		if geneticCode > 0 {
			params["code"] = geneticCode
		}
		if scientificName != "" {
			params["scientific_name"] = scientificName
		}
		if taxonomyID > 0 {
			params["taxonomy_id"] = taxonomyID
		}
		if domain != "" {
			params["domain"] = domain
		}
	} else {
		params["contigs"] = strings.TrimPrefix(inputWSPath, "ws:")

		// Look up taxonomy info if we have a taxonomy ID
		if taxonomyID > 0 {
			// Try to fill in missing fields from taxonomy
			if domain == "" || scientificName == "" || geneticCode == 0 {
				dbDomain, dbName, dbCode := lookupTaxonomy(taxonomyID)
				if domain == "" && dbDomain != "" {
					params["domain"] = dbDomain
				} else if domain != "" {
					params["domain"] = domain
				}
				if scientificName == "" && dbName != "" {
					params["scientific_name"] = dbName
				} else if scientificName != "" {
					params["scientific_name"] = scientificName
				}
				if geneticCode == 0 && dbCode > 0 {
					params["code"] = dbCode
				} else if geneticCode > 0 {
					params["code"] = geneticCode
				}
			} else {
				params["domain"] = domain
				params["code"] = geneticCode
				params["scientific_name"] = scientificName
			}
			params["taxonomy_id"] = taxonomyID
		} else {
			// Use defaults
			params["taxonomy_id"] = defaultTaxonID
			if domain == "" {
				params["domain"] = defaultDomain
			} else {
				params["domain"] = domain
			}
			if geneticCode == 0 {
				params["code"] = defaultCode
			} else {
				params["code"] = geneticCode
			}
			if scientificName == "" {
				params["scientific_name"] = defaultName
			} else {
				params["scientific_name"] = scientificName
			}
		}
	}

	// Build start params
	startParams := appservice.StartParams{}
	if baseURL != "" {
		startParams.BaseURL = baseURL
	}
	if containerID != "" {
		startParams.ContainerID = containerID
	}
	if reservation != "" {
		startParams.Reservation = reservation
	}

	if dryRun {
		fmt.Println("Would submit with data:")
		paramsJSON, _ := json.MarshalIndent(params, "", "  ")
		fmt.Println(string(paramsJSON))
		fmt.Println("and start parameters:")
		startJSON, _ := json.MarshalIndent(startParams, "", "  ")
		fmt.Println(string(startJSON))
		return nil
	}

	// Submit the job
	task, err := app.StartApp2(appName, params, startParams)
	if err != nil {
		return fmt.Errorf("submitting annotation: %w", err)
	}

	fmt.Printf("Submitted annotation with id %s\n", task.GetID())
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

	fmt.Printf("Uploading %s to %s...\n", path, wsPath)
	_, err = ws.Create(workspace.CreateParams{
		Objects: []workspace.CreateObject{{
			Path: wsPath,
			Type: "contigs",
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

func lookupTaxonomy(taxID int) (domain, name string, code int) {
	// Query taxonomy service
	client := api.NewClient()
	query := api.NewQuery().
		Eq("taxon_id", fmt.Sprintf("%d", taxID)).
		Select("lineage_names", "genetic_code", "taxon_name").
		Limit(1)

	results, err := client.Query(context.Background(), "taxonomy", query)
	if err != nil || len(results) == 0 {
		return "", "", 0
	}

	if n, ok := results[0]["taxon_name"].(string); ok {
		name = n
	}
	if c, ok := results[0]["genetic_code"].(float64); ok {
		code = int(c)
	}
	if lin, ok := results[0]["lineage_names"].([]interface{}); ok && len(lin) > 0 {
		if d, ok := lin[0].(string); ok {
			if strings.HasPrefix(d, "cellular") && len(lin) > 1 {
				if d2, ok := lin[1].(string); ok {
					domain = d2
				}
			} else {
				domain = d
			}
		}
	}

	return domain, name, code
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
