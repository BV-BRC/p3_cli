package auth

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestParseToken(t *testing.T) {
	tests := []struct {
		name      string
		raw       string
		wantUser  string
		wantAdmin bool
		wantValid bool
	}{
		{
			name:      "valid token with user",
			raw:       "un=testuser@example.com|expiry=9999999999|sig=abc123",
			wantUser:  "testuser@example.com",
			wantAdmin: false,
			wantValid: true,
		},
		{
			name:      "admin token",
			raw:       "un=admin@example.com|scope=user|roles=admin|expiry=9999999999",
			wantUser:  "admin@example.com",
			wantAdmin: true,
			wantValid: true,
		},
		{
			name:      "expired token",
			raw:       "un=testuser@example.com|expiry=1000000000",
			wantUser:  "testuser@example.com",
			wantAdmin: false,
			wantValid: false, // expired
		},
		{
			name:      "empty token",
			raw:       "",
			wantUser:  "",
			wantAdmin: false,
			wantValid: false,
		},
		{
			name:      "invalid format",
			raw:       "not-a-valid-token",
			wantUser:  "",
			wantAdmin: false,
			wantValid: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			token := parseToken(tt.raw)
			if token.UserID != tt.wantUser {
				t.Errorf("UserID = %q, want %q", token.UserID, tt.wantUser)
			}
			if token.IsAdmin != tt.wantAdmin {
				t.Errorf("IsAdmin = %v, want %v", token.IsAdmin, tt.wantAdmin)
			}
			if token.IsValid() != tt.wantValid {
				t.Errorf("IsValid() = %v, want %v", token.IsValid(), tt.wantValid)
			}
		})
	}
}

func TestTokenExpiry(t *testing.T) {
	// Token that expires in the future
	futureToken := parseToken("un=user@example.com|expiry=9999999999")
	if futureToken.IsExpired() {
		t.Error("Future token should not be expired")
	}

	// Token that expired in the past
	pastToken := parseToken("un=user@example.com|expiry=1000000000")
	if !pastToken.IsExpired() {
		t.Error("Past token should be expired")
	}

	// Token with no expiry
	noExpiryToken := parseToken("un=user@example.com|sig=abc")
	if noExpiryToken.IsExpired() {
		t.Error("Token without expiry should not be expired")
	}
	if noExpiryToken.Expiry != (time.Time{}) {
		t.Error("Token without expiry should have zero time")
	}
}

func TestEnvSource(t *testing.T) {
	const testVar = "TEST_P3_TOKEN_12345"
	const testToken = "un=envuser@example.com|expiry=9999999999"

	// Set the environment variable
	os.Setenv(testVar, testToken)
	defer os.Unsetenv(testVar)

	source := EnvSource(testVar)

	token, err := source.Token()
	if err != nil {
		t.Fatalf("Token() error = %v", err)
	}
	if token != testToken {
		t.Errorf("Token() = %q, want %q", token, testToken)
	}

	// Test non-existent variable
	emptySource := EnvSource("NONEXISTENT_VAR_12345")
	token, err = emptySource.Token()
	if err != nil {
		t.Fatalf("Token() error = %v", err)
	}
	if token != "" {
		t.Errorf("Token() = %q, want empty", token)
	}
}

func TestFileSource(t *testing.T) {
	// Create a temporary token file
	tmpDir := t.TempDir()
	tokenPath := filepath.Join(tmpDir, ".patric_token")
	testToken := "un=fileuser@example.com|expiry=9999999999"

	if err := os.WriteFile(tokenPath, []byte(testToken+"\n"), 0600); err != nil {
		t.Fatalf("Failed to write test token file: %v", err)
	}

	source := FileSource(tokenPath)

	token, err := source.Token()
	if err != nil {
		t.Fatalf("Token() error = %v", err)
	}
	if token != testToken {
		t.Errorf("Token() = %q, want %q", token, testToken)
	}

	// Test non-existent file
	missingSource := FileSource(filepath.Join(tmpDir, "nonexistent"))
	token, err = missingSource.Token()
	if err != nil {
		t.Fatalf("Token() error = %v", err)
	}
	if token != "" {
		t.Errorf("Token() = %q, want empty", token)
	}
}

func TestGetTokenFromSources(t *testing.T) {
	const testVar = "TEST_P3_TOKEN_CHAIN"
	const testToken = "un=chainuser@example.com|expiry=9999999999"

	os.Setenv(testVar, testToken)
	defer os.Unsetenv(testVar)

	sources := []TokenSource{
		EnvSource("NONEXISTENT_VAR"),
		EnvSource(testVar),
	}

	token, err := GetTokenFromSources(sources)
	if err != nil {
		t.Fatalf("GetTokenFromSources() error = %v", err)
	}
	if token == nil {
		t.Fatal("GetTokenFromSources() returned nil")
	}
	if token.UserID != "chainuser@example.com" {
		t.Errorf("UserID = %q, want %q", token.UserID, "chainuser@example.com")
	}
}

func TestNewToken(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		wantNil bool
	}{
		{
			name:    "valid token",
			raw:     "un=user@example.com|expiry=9999999999",
			wantNil: false,
		},
		{
			name:    "empty string",
			raw:     "",
			wantNil: true,
		},
		{
			name:    "invalid format",
			raw:     "not-a-token",
			wantNil: true,
		},
		{
			name:    "expired token",
			raw:     "un=user@example.com|expiry=1000000000",
			wantNil: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			token := NewToken(tt.raw)
			if (token == nil) != tt.wantNil {
				t.Errorf("NewToken() returned nil = %v, want %v", token == nil, tt.wantNil)
			}
		})
	}
}
