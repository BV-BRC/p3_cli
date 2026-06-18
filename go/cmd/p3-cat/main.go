// Command p3-cat outputs workspace file contents to stdout.
//
// Usage:
//
//	p3-cat [options] path [path...]
//
// This command displays the contents of one or more workspace files.
package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/BV-BRC/bvbrc/pkg/workspace"
	"github.com/spf13/cobra"
)

var (
	adminMode bool
)

var rootCmd = &cobra.Command{
	Use:   "p3-cat [options] path [path...]",
	Short: "Output workspace file contents to stdout",
	Long: `Dump one or more workspace files to stdout.

Examples:

  # Display a file
  p3-cat /username@patricbrc.org/home/myfile.txt

  # Display multiple files
  p3-cat ws:/path/file1.txt ws:/path/file2.txt`,
	Args: cobra.MinimumNArgs(1),
	RunE: run,
}

func init() {
	rootCmd.Flags().BoolVarP(&adminMode, "admin", "A", false, "run in admin mode")
}

func run(cmd *cobra.Command, args []string) error {
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to use p3-cat")
	}

	ws := workspace.New(workspace.WithToken(token))

	for _, path := range args {
		// Strip ws: prefix if present
		path = strings.TrimPrefix(path, "ws:")

		if err := ws.Cat(path, os.Stdout); err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", path, err)
		}
	}

	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
