// Command p3-cp copies files between local computer and workspace.
//
// Usage:
//
//	p3-cp [options] source dest
//	p3-cp [options] source... directory
//
// Source and destination may be local paths or workspace paths (prefixed with ws:).
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/BV-BRC/bvbrc/pkg/workspace"
	"github.com/spf13/cobra"
)

var (
	recursive       bool
	overwrite       bool
	workspacePrefix string
	defaultType     string
	adminMode       bool
)

// File type mappings based on extension
var suffixMap = map[string]string{
	"fa":       "reads",
	"fasta":    "reads",
	"fq":       "reads",
	"fastq":    "reads",
	"fq.gz":    "reads",
	"fastq.gz": "reads",
	"tgz":      "tar_gz",
	"tar.gz":   "tar_gz",
	"fna":      "contigs",
	"faa":      "feature_protein_fasta",
	"txt":      "txt",
	"html":     "html",
}

var rootCmd = &cobra.Command{
	Use:   "p3-cp [options] source dest",
	Short: "Copy files between local computer and workspace",
	Long: `Copy files between the local computer and the BV-BRC workspace.

Source and destination files may either be local paths or workspace paths.
Workspace paths are denoted with a ws: prefix.

Examples:

  # Upload a file to workspace
  p3-cp myfile.txt ws:/username@patricbrc.org/home/myfile.txt

  # Download a file from workspace
  p3-cp ws:/username@patricbrc.org/home/myfile.txt ./myfile.txt

  # Copy within workspace
  p3-cp ws:/path/file1.txt ws:/path/file2.txt

  # Upload multiple files to a directory
  p3-cp file1.txt file2.txt ws:/username@patricbrc.org/home/`,
	Args: cobra.MinimumNArgs(2),
	RunE: run,
}

func init() {
	rootCmd.Flags().BoolVarP(&recursive, "recursive", "r", false, "copy directories recursively")
	rootCmd.Flags().BoolVarP(&overwrite, "overwrite", "f", false, "overwrite existing files")
	rootCmd.Flags().StringVarP(&workspacePrefix, "workspace-path-prefix", "p", "", "prefix for relative workspace paths")
	rootCmd.Flags().StringVarP(&defaultType, "default-type", "T", "", "default type for uploaded files")
	rootCmd.Flags().BoolVarP(&adminMode, "administrator", "A", false, "run as administrator")
}

func run(cmd *cobra.Command, args []string) error {
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to use p3-cp")
	}

	ws := workspace.New(workspace.WithToken(token))

	// Last argument is destination
	dest := args[len(args)-1]
	sources := args[:len(args)-1]

	// Determine if dest is a directory
	destIsWs := isWorkspacePath(dest)
	destPath := cleanPath(dest)

	var destIsDir bool
	if destIsWs {
		// Check if workspace path is a directory
		meta, err := ws.Stat(destPath, adminMode)
		if err == nil && meta.IsFolder() {
			destIsDir = true
		}
	} else {
		// Check if local path is a directory
		info, err := os.Stat(destPath)
		if err == nil && info.IsDir() {
			destIsDir = true
		}
	}

	// If multiple sources, dest must be a directory
	if len(sources) > 1 && !destIsDir {
		return fmt.Errorf("target %s is not a directory", dest)
	}

	for _, src := range sources {
		srcIsWs := isWorkspacePath(src)
		srcPath := cleanPath(src)

		targetPath := destPath
		if destIsDir {
			baseName := filepath.Base(srcPath)
			if destIsWs {
				targetPath = destPath + "/" + baseName
			} else {
				targetPath = filepath.Join(destPath, baseName)
			}
		}

		if err := copyFile(ws, srcIsWs, srcPath, destIsWs, targetPath); err != nil {
			fmt.Fprintf(os.Stderr, "Error copying %s to %s: %v\n", src, targetPath, err)
		}
	}

	return nil
}

func isWorkspacePath(path string) bool {
	return strings.HasPrefix(path, "ws:")
}

func cleanPath(path string) string {
	path = strings.TrimPrefix(path, "ws:")
	if !strings.HasPrefix(path, "/") && workspacePrefix != "" {
		path = workspacePrefix + "/" + path
	}
	return path
}

func copyFile(ws *workspace.Client, srcIsWs bool, srcPath string, destIsWs bool, destPath string) error {
	fmt.Printf("Copy %s to %s\n", srcPath, destPath)

	switch {
	case srcIsWs && destIsWs:
		// Workspace to workspace copy
		return ws.Copy(workspace.CopyParams{
			Objects:   [][2]string{{srcPath, destPath}},
			Overwrite: overwrite,
			AdminMode: adminMode,
		})

	case srcIsWs && !destIsWs:
		// Download from workspace to local
		return ws.DownloadFile(srcPath, destPath)

	case !srcIsWs && destIsWs:
		// Upload from local to workspace
		return uploadFile(ws, srcPath, destPath)

	default:
		// Local to local copy (use system copy)
		return localCopy(srcPath, destPath)
	}
}

func uploadFile(ws *workspace.Client, localPath, wsPath string) error {
	// Read file content
	data, err := os.ReadFile(localPath)
	if err != nil {
		return fmt.Errorf("reading file: %w", err)
	}

	// Determine file type from extension
	fileType := guessFileType(localPath)

	// Create the object
	_, err = ws.Create(workspace.CreateParams{
		Objects: []workspace.CreateObject{{
			Path: wsPath,
			Type: fileType,
			Data: string(data),
		}},
		Overwrite: overwrite,
		AdminMode: adminMode,
	})
	return err
}

func guessFileType(path string) string {
	// Check multi-part extensions first
	for ext, fileType := range suffixMap {
		if strings.Contains(ext, ".") && strings.HasSuffix(path, "."+ext) {
			return fileType
		}
	}

	// Check single extensions
	ext := strings.TrimPrefix(filepath.Ext(path), ".")
	if fileType, ok := suffixMap[ext]; ok {
		return fileType
	}

	if defaultType != "" {
		return defaultType
	}
	return "unspecified"
}

func localCopy(src, dest string) error {
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	destFile, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer destFile.Close()

	_, err = io.Copy(destFile, srcFile)
	return err
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
