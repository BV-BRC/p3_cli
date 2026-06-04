// Command p3-mkdir creates directories in the workspace.
//
// Usage:
//
//	p3-mkdir [options] path [path...]
//
// This command creates one or more directories in the workspace.
package main

import (
	"fmt"
	"os"

	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/BV-BRC/bvbrc/pkg/workspace"
	"github.com/spf13/cobra"
)

var (
	adminMode    bool
	workspaceURL string
)

var rootCmd = &cobra.Command{
	Use:   "p3-mkdir [options] path [path...]",
	Short: "Create directories in the workspace",
	Long: `Create one or more directories in the workspace.

Examples:

  # Create a directory
  p3-mkdir /username@patricbrc.org/home/newdir

  # Create multiple directories
  p3-mkdir /username@patricbrc.org/home/dir1 /username@patricbrc.org/home/dir2`,
	Args: cobra.MinimumNArgs(1),
	RunE: run,
}

func init() {
	rootCmd.Flags().BoolVarP(&adminMode, "administrator", "A", false, "use admin privileges")
	rootCmd.Flags().StringVar(&workspaceURL, "url", "", "workspace URL")
}

func run(cmd *cobra.Command, args []string) error {
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to use p3-mkdir")
	}

	opts := []workspace.Option{workspace.WithToken(token)}
	if workspaceURL != "" {
		opts = append(opts, workspace.WithURL(workspaceURL))
	}
	ws := workspace.New(opts...)

	hadError := false
	for _, path := range args {
		// Check if it already exists
		meta, err := ws.Stat(path, adminMode)
		if err == nil && meta != nil {
			fmt.Fprintf(os.Stderr, "%s already exists\n", path)
			continue
		}

		// Create the directory
		_, err = ws.Mkdir(path, adminMode)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error creating directory %s: %v\n", path, err)
			hadError = true
		}
	}

	if hadError {
		return fmt.Errorf("some directories could not be created")
	}
	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
