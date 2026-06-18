// Command p3-logout logs out from BV-BRC by removing the token file.
//
// Usage:
//
//	p3-logout
//
// This command removes the authentication token file (~/.patric_token).
package main

import (
	"fmt"
	"os"

	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "p3-logout",
	Short: "Log out from BV-BRC",
	Long: `Log out from BV-BRC by removing the authentication token file.

This command deletes the token file at ~/.patric_token, ending your
current session.`,
	Args: cobra.NoArgs,
	RunE: run,
}

func run(cmd *cobra.Command, args []string) error {
	if !auth.TokenFileExists() {
		fmt.Println("You are already logged out of BV-BRC.")
		return nil
	}

	if err := auth.DeleteToken(); err != nil {
		return fmt.Errorf("could not delete login file: %w", err)
	}

	fmt.Println("Logged out of BV-BRC.")
	return nil
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
