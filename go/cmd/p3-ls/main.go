// Command p3-ls lists workspace files and directories.
//
// Usage:
//
//	p3-ls [options] path [path...]
//
// This command lists the contents of one or more workspace paths.
package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/BV-BRC/bvbrc/pkg/workspace"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)

var (
	longFormat   bool
	oneColumn    bool
	showDir      bool
	sortByTime   bool
	reverse      bool
	showType     bool
	showIDs      bool
	adminMode    bool
	workspaceURL string
)

var rootCmd = &cobra.Command{
	Use:   "p3-ls [options] path [path...]",
	Short: "List workspace files and directories",
	Long: `List one or more workspace paths.

Examples:

  # List home directory
  p3-ls /username@patricbrc.org/home

  # Long format listing
  p3-ls -l /username@patricbrc.org/home

  # Show directory itself, not contents
  p3-ls -d /username@patricbrc.org/home`,
	Args: cobra.MinimumNArgs(1),
	RunE: run,
}

func init() {
	rootCmd.Flags().BoolVarP(&longFormat, "long", "l", false, "show file details")
	rootCmd.Flags().BoolVarP(&oneColumn, "one-column", "1", false, "show results in one column")
	rootCmd.Flags().BoolVarP(&showDir, "directory", "d", false, "show directory info instead of contents")
	rootCmd.Flags().BoolVarP(&sortByTime, "time", "t", false, "sort by creation time")
	rootCmd.Flags().BoolVarP(&reverse, "reverse", "r", false, "reverse sort order")
	rootCmd.Flags().BoolVarP(&showType, "type", "T", false, "show file type in long listing")
	rootCmd.Flags().BoolVar(&showIDs, "ids", false, "show workspace UUIDs in long listing")
	rootCmd.Flags().BoolVarP(&adminMode, "administrator", "A", false, "run as administrator")
	rootCmd.Flags().StringVar(&workspaceURL, "url", "", "workspace URL")
}

func run(cmd *cobra.Command, args []string) error {
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to use p3-ls")
	}

	opts := []workspace.Option{workspace.WithToken(token)}
	if workspaceURL != "" {
		opts = append(opts, workspace.WithURL(workspaceURL))
	}
	ws := workspace.New(opts...)

	// If not a terminal, use one-column output
	if !term.IsTerminal(int(os.Stdout.Fd())) {
		oneColumn = true
	}

	for _, path := range args {
		if err := listPath(ws, path); err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", path, err)
		}
	}

	return nil
}

func listPath(ws *workspace.Client, path string) error {
	// First try to list the path as a directory
	result, err := ws.Ls(workspace.LsParams{
		Paths:     []string{path},
		AdminMode: adminMode,
	})
	if err != nil {
		return err
	}

	files := result[path]

	// If showDir is set or we got no results (it might be a file, not a directory),
	// we need to handle it differently
	if showDir {
		// Show the path itself - need to get metadata for the path
		// For this we use ls on the parent and find the entry
		meta, err := ws.Stat(path, adminMode)
		if err != nil {
			return err
		}
		if longFormat {
			printLongListing([]*workspace.ObjectMeta{meta})
		} else {
			fmt.Println(path)
		}
		return nil
	}

	if files == nil {
		files = []*workspace.ObjectMeta{}
	}

	// Sort files
	sortFiles(files)

	if longFormat {
		printLongListing(files)
	} else {
		printSimpleListing(files)
	}

	return nil
}

func sortFiles(files []*workspace.ObjectMeta) {
	sort.Slice(files, func(i, j int) bool {
		a, b := files[i], files[j]
		if reverse {
			a, b = b, a
		}

		if sortByTime {
			ta, _ := a.ParseTime()
			tb, _ := b.ParseTime()
			if !ta.Equal(tb) {
				return ta.Before(tb)
			}
		}

		// Sort by name, ignoring leading dots
		na := strings.TrimPrefix(a.Name, ".")
		nb := strings.TrimPrefix(b.Name, ".")
		if na != nb {
			return na < nb
		}
		return a.Name < b.Name
	})
}

func printLongListing(files []*workspace.ObjectMeta) {
	if len(files) == 0 {
		return
	}

	// Calculate column widths
	maxOwner := 0
	maxSize := 0
	maxID := 0
	maxType := 0

	for _, meta := range files {
		if len(meta.Owner) > maxOwner {
			maxOwner = len(meta.Owner)
		}
		sizeStr := fmt.Sprintf("%d", meta.Size)
		if len(sizeStr) > maxSize {
			maxSize = len(sizeStr)
		}
		if showIDs && len(meta.ID) > maxID {
			maxID = len(meta.ID)
		}
		if showType && len(meta.Type) > maxType {
			maxType = len(meta.Type)
		}
	}

	for _, meta := range files {
		// Permissions (fixed width)
		perms := computePerms(meta)
		fmt.Print(perms)
		fmt.Print("  ")

		// Owner (left-aligned)
		fmt.Printf("%-*s  ", maxOwner, meta.Owner)

		// Size (right-aligned)
		fmt.Printf("%*d  ", maxSize, meta.Size)

		// Time (fixed width)
		fmt.Printf("%s  ", formatTime(meta.CreationTime))

		// ID (optional, left-aligned)
		if showIDs {
			fmt.Printf("%-*s  ", maxID, meta.ID)
		}

		// Type (optional, left-aligned)
		if showType {
			fmt.Printf("%-*s  ", maxType, meta.Type)
		}

		// Name (last, no padding)
		fmt.Println(meta.Name)
	}
}

func computePerms(meta *workspace.ObjectMeta) string {
	var perms strings.Builder

	// Type indicator
	if meta.IsFolder() {
		perms.WriteByte('d')
	} else if meta.ShockURL != "" {
		perms.WriteByte('S')
	} else {
		perms.WriteByte('-')
	}

	// User permissions (owner can always access)
	perms.WriteString("rw")

	// Global permissions
	if meta.GlobalPerm == "n" {
		perms.WriteString("--")
	} else {
		perms.WriteString("r-")
	}

	return perms.String()
}

func formatTime(ts string) string {
	t, err := time.Parse(time.RFC3339, ts)
	if err != nil {
		// Try other formats
		t, err = time.Parse("2006-01-02T15:04:05", ts)
		if err != nil {
			return ts
		}
	}

	// If older than 180 days, show year instead of time
	if time.Since(t) > 180*24*time.Hour {
		return t.Format("Jan _2  2006")
	}
	return t.Format("Jan _2 15:04")
}

func printSimpleListing(files []*workspace.ObjectMeta) {
	names := make([]string, len(files))
	for i, meta := range files {
		names[i] = meta.Name
	}

	if oneColumn {
		for _, name := range names {
			fmt.Println(name)
		}
	} else {
		// Tabular output
		printTabular(names)
	}
}

func printTabular(names []string) {
	if len(names) == 0 {
		return
	}

	// Get terminal width
	width := 80
	if w, _, err := term.GetSize(int(os.Stdout.Fd())); err == nil && w > 0 {
		width = w
	}

	// Find longest name
	maxLen := 0
	for _, name := range names {
		if len(name) > maxLen {
			maxLen = len(name)
		}
	}

	gutter := 3
	colWidth := maxLen + gutter
	cols := width / colWidth
	if cols < 1 {
		cols = 1
	}

	rows := (len(names) + cols - 1) / cols

	for r := 0; r < rows; r++ {
		var line strings.Builder
		for c := 0; c < cols; c++ {
			idx := c*rows + r
			if idx >= len(names) {
				break
			}
			name := names[idx]
			line.WriteString(name)
			if c < cols-1 && idx+rows < len(names) {
				// Add padding
				padding := colWidth - len(name)
				for i := 0; i < padding; i++ {
					line.WriteByte(' ')
				}
			}
		}
		fmt.Println(line.String())
	}
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
