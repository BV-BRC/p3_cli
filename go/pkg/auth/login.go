// Package auth provides authentication token handling for BV-BRC API access.
package auth

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const (
	// PatricAuthURL is the BV-BRC authentication endpoint
	PatricAuthURL = "https://user.patricbrc.org/authenticate"

	// RastAuthURL is the RAST authentication endpoint
	RastAuthURL = "http://rast.nmpdr.org/goauth/token?grant_type=client_credentials"

	// DefaultTimeout is the HTTP client timeout for authentication requests
	DefaultTimeout = 10 * time.Second
)

// LoginPatric authenticates with the BV-BRC service and returns a token.
// The username should not include the @patricbrc.org suffix.
func LoginPatric(username, password string) (string, error) {
	// Trim the @patricbrc.org suffix if present
	username = strings.TrimSuffix(username, "@patricbrc.org")

	client := &http.Client{Timeout: DefaultTimeout}

	// Prepare form data
	data := url.Values{}
	data.Set("username", username)
	data.Set("password", password)

	resp, err := client.PostForm(PatricAuthURL, data)
	if err != nil {
		return "", fmt.Errorf("authentication request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("reading response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("login failed (status %d)", resp.StatusCode)
	}

	token := strings.TrimSpace(string(body))
	if token == "" {
		return "", fmt.Errorf("empty token received")
	}

	// Validate token format
	if !strings.Contains(token, "un=") {
		return "", fmt.Errorf("invalid token format")
	}

	return token, nil
}

// LoginRast authenticates with the RAST service and returns a token.
func LoginRast(username, password string) (string, error) {
	client := &http.Client{Timeout: DefaultTimeout}

	req, err := http.NewRequest("GET", RastAuthURL, nil)
	if err != nil {
		return "", fmt.Errorf("creating request: %w", err)
	}

	req.SetBasicAuth(username, password)

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("authentication request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("login failed (status %d)", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("reading response: %w", err)
	}

	// RAST returns JSON with access_token field
	// Parse it manually to avoid json import for simple extraction
	tokenStr := string(body)
	start := strings.Index(tokenStr, `"access_token":"`)
	if start == -1 {
		return "", fmt.Errorf("invalid response format: no access_token found")
	}
	start += len(`"access_token":"`)
	end := strings.Index(tokenStr[start:], `"`)
	if end == -1 {
		return "", fmt.Errorf("invalid response format: malformed access_token")
	}

	token := tokenStr[start : start+end]
	if token == "" {
		return "", fmt.Errorf("empty token received")
	}

	return token, nil
}

// SaveToken writes the token to the default token file with mode 0600.
func SaveToken(token string) error {
	tokenPath := DefaultTokenPath()
	if tokenPath == "" {
		return fmt.Errorf("cannot determine home directory")
	}

	// Write with mode 0600 for security
	err := os.WriteFile(tokenPath, []byte(token+"\n"), 0600)
	if err != nil {
		return fmt.Errorf("writing token file: %w", err)
	}

	return nil
}

// DeleteToken removes the token file if it exists.
func DeleteToken() error {
	tokenPath := DefaultTokenPath()
	if tokenPath == "" {
		return fmt.Errorf("cannot determine home directory")
	}

	err := os.Remove(tokenPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // Already logged out
		}
		return fmt.Errorf("deleting token file: %w", err)
	}

	return nil
}

// TokenFileExists returns true if the token file exists.
func TokenFileExists() bool {
	tokenPath := DefaultTokenPath()
	if tokenPath == "" {
		return false
	}

	_, err := os.Stat(tokenPath)
	return err == nil
}

// ExtractUsername extracts the username from a token string.
// Returns the bare username without @patricbrc.org suffix for PATRIC users.
func ExtractUsername(token string) (username string, isPatric bool) {
	t := parseToken(token)
	if t.UserID == "" {
		return "", false
	}

	if strings.HasSuffix(t.UserID, "@patricbrc.org") {
		return strings.TrimSuffix(t.UserID, "@patricbrc.org"), true
	}

	return t.UserID, false
}
