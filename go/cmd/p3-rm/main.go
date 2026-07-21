// Command p3-rm removes files and directories from the workspace.
//
// Usage:
//
//	p3-rm [options] path [path...]
//
// This command removes one or more files or directories from the workspace.
package main

import (
	"fmt"
	"os"

	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/BV-BRC/bvbrc/pkg/workspace"
	"github.com/spf13/cobra"
)

var (
	recursive    bool
	workspaceURL string
)

var rootCmd = &cobra.Command{
	Use:   "p3-rm [options] path [path...]",
	Short: "Remove files and directories from the workspace",
	Long: `Remove one or more files or directories from the workspace.

Examples:

  # Remove a file
  p3-rm /username@patricbrc.org/home/myfile.txt

  # Remove a directory recursively
  p3-rm -r /username@patricbrc.org/home/mydir`,
	Args: cobra.MinimumNArgs(1),
	RunE: run,
}

func init() {
	rootCmd.Flags().BoolVarP(&recursive, "recursive", "r", false, "recursively remove directories")
	rootCmd.Flags().StringVar(&workspaceURL, "url", "", "workspace URL")
}

func run(cmd *cobra.Command, args []string) error {
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to use p3-rm")
	}

	opts := []workspace.Option{workspace.WithToken(token)}
	if workspaceURL != "" {
		opts = append(opts, workspace.WithURL(workspaceURL))
	}
	ws := workspace.New(opts...)

	hadError := false
	for _, path := range args {
		// Check if it exists and get type
		meta, err := ws.Stat(path, false)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Not removing %s: file does not exist\n", path)
			hadError = true
			continue
		}

		// Check if it's a directory
		if meta.IsFolder() {
			if !recursive {
				fmt.Fprintf(os.Stderr, "Not removing %s: is a directory\n", path)
				hadError = true
				continue
			}

			// Recursive delete - first list all contents
			result, err := ws.Ls(workspace.LsParams{
				Paths:     []string{path},
				Recursive: true,
			})
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error listing %s: %v\n", path, err)
				hadError = true
				continue
			}

			// Collect all paths to delete
			var toDelete []string
			for _, item := range result[path] {
				objPath := item.Path + item.Name
				toDelete = append(toDelete, objPath)
			}
			// Add the directory itself
			toDelete = append(toDelete, path)

			// Delete all
			err = ws.Delete(workspace.DeleteParams{
				Objects:           toDelete,
				DeleteDirectories: true,
				Force:             true,
			})
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error in recursive remove: %v\n", err)
				hadError = true
			}
		} else {
			// Single file delete
			err = ws.Delete(workspace.DeleteParams{
				Objects: []string{path},
			})
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error removing file %s: %v\n", path, err)
				hadError = true
			}
		}
	}

	if hadError {
		return fmt.Errorf("some files could not be removed")
	}
	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
