// Command p3-login authenticates with BV-BRC and saves the token.
//
// Usage:
//
//	p3-login [options] username
//
// This command prompts for a password and authenticates with the BV-BRC
// or RAST authentication service, saving the token to ~/.patric_token.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)

var (
	logout  bool
	status  bool
	rast    bool
	verbose bool
)

const maxTries = 3

var rootCmd = &cobra.Command{
	Use:   "p3-login [options] username",
	Short: "Log in to BV-BRC",
	Long: `Create a BV-BRC login token, used with workspace operations.

To use this script, specify your user name on the command line as a
positional parameter. You will be asked for your password.

Examples:

  # Log in to BV-BRC
  p3-login myusername

  # Log in to RAST
  p3-login --rast myusername

  # Check login status
  p3-login --status

  # Log out
  p3-login --logout`,
	Args: cobra.MaximumNArgs(1),
	RunE: run,
}

func init() {
	rootCmd.Flags().BoolVar(&logout, "logout", false, "log out of BV-BRC")
	rootCmd.Flags().BoolVar(&status, "status", false, "display login status")
	rootCmd.Flags().BoolVarP(&status, "whoami", "s", false, "display login status")
	rootCmd.Flags().BoolVar(&rast, "rast", false, "create a RAST login token")
	rootCmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "display debugging info")
}

func run(cmd *cobra.Command, args []string) error {
	tokenPath := auth.DefaultTokenPath()

	if verbose {
		fmt.Printf("Token path is %s.\n", tokenPath)
	}

	// Handle --status flag
	if status || verbose {
		token, _ := auth.GetTokenFromSources([]auth.TokenSource{
			auth.FileSource(tokenPath),
		})

		if token == nil {
			fmt.Println("You are currently logged out of BV-BRC.")
		} else {
			username, isPatric := auth.ExtractUsername(token.Raw)
			if username == "" {
				return fmt.Errorf("your BV-BRC login token is improperly formatted. Please log out and try again")
			}

			if isPatric {
				fmt.Printf("You are logged in as BV-BRC user %s\n", username)
			} else {
				fmt.Printf("You are logged in as RAST user %s\n", username)
			}
		}
	}

	// Handle --logout flag
	if logout {
		if !auth.TokenFileExists() {
			fmt.Println("You are already logged out of BV-BRC.")
		} else {
			if err := auth.DeleteToken(); err != nil {
				return fmt.Errorf("could not delete login file: %w", err)
			}
			fmt.Println("Logged out of BV-BRC.")
		}
	}

	// If just status or logout, we're done
	if status || logout {
		return nil
	}

	// Need username for actual login
	if len(args) == 0 {
		return fmt.Errorf("a user name is required")
	}
	username := args[0]

	// Try to login with up to maxTries attempts
	var token string
	var err error

	for try := 1; try <= maxTries; try++ {
		password, readErr := getPassword()
		if readErr != nil {
			return readErr
		}
		if password == "" {
			return fmt.Errorf("password required")
		}

		if rast {
			token, err = auth.LoginRast(username, password)
		} else {
			token, err = auth.LoginPatric(username, password)
		}

		if err == nil && token != "" {
			break
		}

		if try < maxTries {
			fmt.Println("Sorry, try again.")
		}
	}

	if token == "" {
		return fmt.Errorf("too many incorrect login attempts; exiting")
	}

	// Extract username from token for display
	tokenUser, _ := auth.ExtractUsername(token)

	// Save the token
	if err := auth.SaveToken(token); err != nil {
		return err
	}

	fmt.Printf("Logged in with username %s\n", tokenUser)
	return nil
}

// getPassword prompts for a password with masked input.
func getPassword() (string, error) {
	fmt.Print("Password: ")

	// Check if stdin is a terminal
	fd := int(os.Stdin.Fd())
	if term.IsTerminal(fd) {
		// Read password with masked input
		password, err := term.ReadPassword(fd)
		fmt.Println() // Add newline after password input
		if err != nil {
			return "", fmt.Errorf("reading password: %w", err)
		}
		return string(password), nil
	}

	// Not a terminal, read from stdin directly (for scripting)
	reader := bufio.NewReader(os.Stdin)
	password, err := reader.ReadString('\n')
	if err != nil {
		return "", fmt.Errorf("reading password: %w", err)
	}
	return strings.TrimSpace(password), nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
