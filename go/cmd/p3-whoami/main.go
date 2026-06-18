// Command p3-whoami displays the currently logged-in user.
//
// Usage:
//
//	p3-whoami
//
// This command reads the authentication token and displays the username
// of the currently logged-in user, distinguishing between BV-BRC and RAST users.
package main

import (
	"fmt"
	"os"

	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "p3-whoami",
	Short: "Display the currently logged-in user",
	Long: `Display the name of the user currently logged in to BV-BRC.

This command reads the authentication token from the environment variables
(P3_AUTH_TOKEN, KB_AUTH_TOKEN) or the token file (~/.patric_token) and
displays the associated username.`,
	Args: cobra.NoArgs,
	RunE: run,
}

func run(cmd *cobra.Command, args []string) error {
	// Get token, ignoring environment (like Perl version)
	// Read directly from file to match Perl behavior
	tokenPath := auth.DefaultTokenPath()
	if tokenPath == "" {
		return fmt.Errorf("cannot determine home directory")
	}

	token, err := auth.GetTokenFromSources([]auth.TokenSource{
		auth.FileSource(tokenPath),
	})
	if err != nil {
		return fmt.Errorf("reading token: %w", err)
	}

	if token == nil {
		fmt.Println("You are currently logged out of BV-BRC.")
		return nil
	}

	username, isPatric := auth.ExtractUsername(token.Raw)
	if username == "" {
		return fmt.Errorf("your BV-BRC login token is improperly formatted. Please log out and try again")
	}

	if isPatric {
		fmt.Printf("You are logged in as BV-BRC user %s\n", username)
	} else {
		fmt.Printf("You are logged in as RAST user %s\n", username)
	}

	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
