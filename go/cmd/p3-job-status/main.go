// Command p3-job-status checks the status of BV-BRC jobs.
//
// Usage:
//
//	p3-job-status [options] jobid [jobid...]
//
// This command queries the status of one or more submitted jobs.
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/BV-BRC/bvbrc/pkg/appservice"
	"github.com/BV-BRC/bvbrc/pkg/auth"
	"github.com/spf13/cobra"
)

var (
	stdoutFile string
	stderrFile string
	verbose    bool
)

var rootCmd = &cobra.Command{
	Use:   "p3-job-status [options] jobid [jobid...]",
	Short: "Check the status of BV-BRC jobs",
	Long: `Check the status of one or more BV-BRC jobs.

Examples:

  # Check status of a job
  p3-job-status 12345

  # Check status with verbose output
  p3-job-status -v 12345

  # Get stdout from a job
  p3-job-status --stdout=output.txt 12345`,
	Args: cobra.MinimumNArgs(1),
	RunE: run,
}

func init() {
	rootCmd.Flags().StringVar(&stdoutFile, "stdout", "", "write job stdout to file (use - for terminal)")
	rootCmd.Flags().StringVar(&stderrFile, "stderr", "", "write job stderr to file (use - for terminal)")
	rootCmd.Flags().BoolVarP(&verbose, "verbose", "v", false, "show all information for the given jobs")
}

func run(cmd *cobra.Command, args []string) error {
	token, err := auth.GetToken()
	if err != nil {
		return fmt.Errorf("getting token: %w", err)
	}
	if token == nil {
		return fmt.Errorf("you must be logged in to BV-BRC via the p3-login command to check job status")
	}

	client := appservice.New(appservice.WithToken(token))

	// Query all jobs at once
	tasks, err := client.QueryTasks(args)
	if err != nil {
		return fmt.Errorf("querying tasks: %w", err)
	}

	for _, jobID := range args {
		task := tasks[jobID]
		if task == nil {
			fmt.Printf("%s: job not found\n", jobID)
			continue
		}

		fmt.Printf("%s: %s\n", jobID, task.Status)

		var details *appservice.TaskDetails
		if verbose || stdoutFile != "" || stderrFile != "" {
			details, err = client.QueryTaskDetails(jobID)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error getting task details: %v\n", err)
				continue
			}
		}

		if verbose {
			if details != nil {
				fmt.Printf("\texecution host\t%s\n", details.Hostname)
				fmt.Printf("\tresult code\t%s\n", details.ExitCode)
			}

			// Print full task JSON
			taskJSON, _ := json.MarshalIndent(task, "", "  ")
			fmt.Println(string(taskJSON))
		}

		if stdoutFile != "" && details != nil && details.StdoutURL != "" {
			if err := writeOutput(client, details.StdoutURL, stdoutFile); err != nil {
				fmt.Fprintf(os.Stderr, "Error writing stdout: %v\n", err)
			}
		}

		if stderrFile != "" && details != nil && details.StderrURL != "" {
			if err := writeOutput(client, details.StderrURL, stderrFile); err != nil {
				fmt.Fprintf(os.Stderr, "Error writing stderr: %v\n", err)
			}
		}
	}

	return nil
}

func writeOutput(client *appservice.Client, url, file string) error {
	var w *os.File
	var err error

	if file == "-" {
		w = os.Stdout
	} else {
		w, err = os.Create(file)
		if err != nil {
			return fmt.Errorf("creating file: %w", err)
		}
		defer w.Close()
	}

	return client.StreamURL(url, w)
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
