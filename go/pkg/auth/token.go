// Package auth provides authentication token handling for BV-BRC API access.
//
// The package implements a token resolution chain that checks multiple sources
// in order of priority:
//  1. Explicitly provided token
//  2. Environment variables (P3_AUTH_TOKEN, KB_AUTH_TOKEN)
//  3. Token file (~/.patric_token)
//
// This mirrors the behavior of the Perl P3AuthToken module.
package auth

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Token represents a BV-BRC authentication token with parsed metadata.
type Token struct {
	// Raw is the complete token string
	Raw string

	// UserID is the username extracted from the token
	UserID string

	// Expiry is the token expiration time (zero if not present)
	Expiry time.Time

	// IsAdmin indicates if the token has admin privileges
	IsAdmin bool
}

// String returns the raw token string for use in HTTP headers.
func (t *Token) String() string {
	return t.Raw
}

// IsExpired returns true if the token has expired.
func (t *Token) IsExpired() bool {
	if t.Expiry.IsZero() {
		return false
	}
	return time.Now().After(t.Expiry)
}

// IsValid returns true if the token appears to be syntactically valid and not expired.
func (t *Token) IsValid() bool {
	if t.Raw == "" {
		return false
	}
	if !strings.Contains(t.Raw, "un=") {
		return false
	}
	return !t.IsExpired()
}

// parseToken parses a raw token string and extracts metadata.
func parseToken(raw string) *Token {
	t := &Token{Raw: raw}

	// Extract user ID: un=<userid>|
	if m := regexp.MustCompile(`\bun=([^|]+)`).FindStringSubmatch(raw); m != nil {
		t.UserID = m[1]
	}

	// Extract expiry: expiry=<unix_timestamp>
	if m := regexp.MustCompile(`\bexpiry=(\d+)`).FindStringSubmatch(raw); m != nil {
		if exp, err := strconv.ParseInt(m[1], 10, 64); err == nil {
			t.Expiry = time.Unix(exp, 0)
		}
	}

	// Check for admin role
	t.IsAdmin = strings.Contains(raw, "|scope=user|") && strings.Contains(raw, "|roles=admin|")

	return t
}

// TokenSource represents a source that can provide authentication tokens.
type TokenSource interface {
	// Token returns the token from this source, or empty string if not available.
	Token() (string, error)

	// Name returns a human-readable name for this source.
	Name() string
}

// envSource reads a token from an environment variable.
type envSource struct {
	varName string
}

// EnvSource creates a TokenSource that reads from the specified environment variable.
func EnvSource(varName string) TokenSource {
	return &envSource{varName: varName}
}

func (s *envSource) Token() (string, error) {
	return os.Getenv(s.varName), nil
}

func (s *envSource) Name() string {
	return fmt.Sprintf("environment variable %s", s.varName)
}

// fileSource reads a token from a file.
type fileSource struct {
	path string
}

// FileSource creates a TokenSource that reads from the specified file path.
func FileSource(path string) TokenSource {
	return &fileSource{path: path}
}

func (s *fileSource) Token() (string, error) {
	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil // Not an error, just no token
		}
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

func (s *fileSource) Name() string {
	return fmt.Sprintf("file %s", s.path)
}

// getHomeDir returns the user's home directory, handling Windows compatibility.
func getHomeDir() string {
	// Try HOME first (works on Unix and some Windows configs)
	if home := os.Getenv("HOME"); home != "" {
		return home
	}

	// Windows-specific fallbacks
	if profile := os.Getenv("USERPROFILE"); profile != "" {
		return profile
	}

	if drive := os.Getenv("HOMEDRIVE"); drive != "" {
		if path := os.Getenv("HOMEPATH"); path != "" {
			return filepath.Join(drive, path)
		}
	}

	return ""
}

// DefaultTokenPath returns the default path for the token file.
func DefaultTokenPath() string {
	home := getHomeDir()
	if home == "" {
		return ""
	}
	return filepath.Join(home, ".patric_token")
}

// DefaultSources returns the default token source chain.
func DefaultSources() []TokenSource {
	sources := []TokenSource{
		EnvSource("P3_AUTH_TOKEN"),
		EnvSource("KB_AUTH_TOKEN"),
	}

	if tokenPath := DefaultTokenPath(); tokenPath != "" {
		sources = append(sources, FileSource(tokenPath))
	}

	return sources
}

// GetToken resolves a token using the default source chain.
// Returns nil if no valid token is found.
func GetToken() (*Token, error) {
	return GetTokenFromSources(DefaultSources())
}

// GetTokenFromSources resolves a token using the provided source chain.
// Returns nil if no valid token is found.
func GetTokenFromSources(sources []TokenSource) (*Token, error) {
	for _, source := range sources {
		raw, err := source.Token()
		if err != nil {
			return nil, fmt.Errorf("error reading from %s: %w", source.Name(), err)
		}
		if raw == "" {
			continue
		}

		token := parseToken(raw)
		if token.IsValid() {
			return token, nil
		}
	}
	return nil, nil
}

// RequireToken returns a valid token or exits with an error.
// This is a convenience function for CLI tools that require authentication.
func RequireToken() *Token {
	token, err := GetToken()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting authentication token: %v\n", err)
		os.Exit(1)
	}
	if token == nil {
		fmt.Fprintln(os.Stderr, "Authentication required. Please log in with p3-login.")
		os.Exit(1)
	}
	return token
}

// NewToken creates a Token from an explicit token string.
// Returns nil if the token string is empty or invalid.
func NewToken(raw string) *Token {
	if raw == "" {
		return nil
	}
	token := parseToken(raw)
	if !token.IsValid() {
		return nil
	}
	return token
}
