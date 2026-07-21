// Package api provides a client for the BV-BRC Data API.
package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	// DefaultBaseURL is the default BV-BRC API endpoint.
	DefaultBaseURL = "https://www.bv-brc.org/api"
	// DefaultChunkSize is the default number of records to fetch per request.
	DefaultChunkSize = 25000
	// DefaultMaxRetries is the default number of retry attempts for failed requests.
	DefaultMaxRetries = 3
)

// Client provides access to the BV-BRC Data API.
type Client struct {
	BaseURL    string
	HTTPClient *http.Client
	Token      string
	ChunkSize  int
	MaxRetries int
	Debug      bool
}

// ChunkInfo contains information about a response chunk from Content-Range header.
type ChunkInfo struct {
	Start  int
	Next   int
	Count  int
	IsLast bool
}

// ClientOption is a function that configures a Client.
type ClientOption func(*Client)

// WithBaseURL sets the base URL for the API client.
func WithBaseURL(baseURL string) ClientOption {
	return func(c *Client) {
		c.BaseURL = strings.TrimSuffix(baseURL, "/")
	}
}

// WithHTTPClient sets a custom HTTP client.
func WithHTTPClient(httpClient *http.Client) ClientOption {
	return func(c *Client) {
		c.HTTPClient = httpClient
	}
}

// WithToken sets the authentication token.
// Accepts either a string or a *auth.Token.
func WithToken(token any) ClientOption {
	return func(c *Client) {
		switch t := token.(type) {
		case string:
			c.Token = t
		case interface{ String() string }:
			c.Token = t.String()
		default:
			if token != nil {
				c.Token = fmt.Sprintf("%v", token)
			}
		}
	}
}

// WithChunkSize sets the number of records to fetch per request.
func WithChunkSize(size int) ClientOption {
	return func(c *Client) {
		c.ChunkSize = size
	}
}

// WithMaxRetries sets the maximum number of retry attempts.
func WithMaxRetries(retries int) ClientOption {
	return func(c *Client) {
		c.MaxRetries = retries
	}
}

// WithDebug enables debug output.
func WithDebug(debug bool) ClientOption {
	return func(c *Client) {
		c.Debug = debug
	}
}

// NewClient creates a new BV-BRC API client with the given options.
func NewClient(opts ...ClientOption) *Client {
	c := &Client{
		BaseURL:    DefaultBaseURL,
		HTTPClient: &http.Client{Timeout: 30 * time.Second},
		ChunkSize:  DefaultChunkSize,
		MaxRetries: DefaultMaxRetries,
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

// Query executes a query against the specified object type and returns the results.
// It handles automatic pagination to fetch all matching records.
func (c *Client) Query(ctx context.Context, objectType string, q *Query) ([]map[string]any, error) {
	var allResults []map[string]any

	// Resolve object type alias
	resolvedType := GetObjectType(objectType)

	// Ensure query has at least one filter (BV-BRC API requirement)
	if !q.HasFilters() {
		// Add a wildcard filter using the ID column for this object type
		idCol := GetIDColumn(resolvedType)
		if idCol == "" {
			idCol = "id" // fallback
		}
		q = q.Clone()
		q.Eq(idCol, "*")
	}

	// Build query string
	queryStr := q.Build()

	// Determine chunk size
	chunkSize := c.ChunkSize
	if q.LimitValue > 0 && q.LimitValue < chunkSize {
		chunkSize = q.LimitValue
	}

	offset := 0
	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		// Build request URL
		reqURL := fmt.Sprintf("%s/%s/", c.BaseURL, resolvedType)

		// Build request body with limit
		body := queryStr
		if body != "" {
			body += "&"
		}
		if offset > 0 {
			body += fmt.Sprintf("limit(%d,%d)", chunkSize, offset)
		} else {
			body += fmt.Sprintf("limit(%d)", chunkSize)
		}

		if c.Debug {
			fmt.Printf("DEBUG: POST %s\n", reqURL)
			fmt.Printf("DEBUG: Body: %s\n", body)
		}

		// Execute request with retries
		results, chunkInfo, err := c.doQueryRequest(ctx, reqURL, body)
		if err != nil {
			return nil, err
		}

		allResults = append(allResults, results...)

		// Check if we have all results
		if chunkInfo.IsLast || len(results) < chunkSize {
			break
		}

		// Check if we've reached the requested limit
		if q.LimitValue > 0 && len(allResults) >= q.LimitValue {
			break
		}

		offset = chunkInfo.Next
	}

	// Trim to requested limit if specified
	if q.LimitValue > 0 && len(allResults) > q.LimitValue {
		allResults = allResults[:q.LimitValue]
	}

	return allResults, nil
}

// doQueryRequest executes a single query request with retry logic.
func (c *Client) doQueryRequest(ctx context.Context, url, body string) ([]map[string]any, *ChunkInfo, error) {
	var lastErr error

	for attempt := 0; attempt <= c.MaxRetries; attempt++ {
		if attempt > 0 {
			// Exponential backoff
			delay := time.Duration(1<<uint(attempt-1)) * time.Second
			select {
			case <-ctx.Done():
				return nil, nil, ctx.Err()
			case <-time.After(delay):
			}
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(body))
		if err != nil {
			return nil, nil, fmt.Errorf("creating request: %w", err)
		}

		c.setHeaders(req)
		req.Header.Set("Accept", "application/json")
		req.Header.Set("Content-Type", "application/rqlquery+x-www-form-urlencoded")

		resp, err := c.HTTPClient.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("executing request: %w", err)
			continue
		}

		// Check for server errors (retry-able)
		if resp.StatusCode >= 500 {
			resp.Body.Close()
			lastErr = fmt.Errorf("server error: %s", resp.Status)
			continue
		}

		// Check for client errors (not retry-able)
		if resp.StatusCode >= 400 {
			bodyBytes, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			return nil, nil, fmt.Errorf("API error: %s - %s", resp.Status, string(bodyBytes))
		}

		// Parse Content-Range header
		chunkInfo := parseContentRange(resp.Header.Get("Content-Range"))

		// Parse response body
		var results []map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&results); err != nil {
			resp.Body.Close()
			lastErr = fmt.Errorf("decoding response: %w", err)
			continue
		}
		resp.Body.Close()

		return results, chunkInfo, nil
	}

	return nil, nil, lastErr
}

// Count returns the count of records matching the query.
func (c *Client) Count(ctx context.Context, objectType string, q *Query) (int, error) {
	resolvedType := GetObjectType(objectType)

	// Ensure query has at least one filter (BV-BRC API requirement)
	if !q.HasFilters() {
		idCol := GetIDColumn(resolvedType)
		if idCol == "" {
			idCol = "id"
		}
		q = q.Clone()
		q.Eq(idCol, "*")
	}

	queryStr := q.Build()

	reqURL := fmt.Sprintf("%s/%s/", c.BaseURL, resolvedType)
	body := queryStr
	if body != "" {
		body += "&"
	}
	body += "limit(1)"

	if c.Debug {
		fmt.Printf("DEBUG: POST %s (count)\n", reqURL)
		fmt.Printf("DEBUG: Body: %s\n", body)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, reqURL, strings.NewReader(body))
	if err != nil {
		return 0, fmt.Errorf("creating request: %w", err)
	}

	c.setHeaders(req)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/rqlquery+x-www-form-urlencoded")
	req.Header.Set("Range", "items=0-0")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return 0, fmt.Errorf("executing request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return 0, fmt.Errorf("API error: %s - %s", resp.Status, string(bodyBytes))
	}

	chunkInfo := parseContentRange(resp.Header.Get("Content-Range"))
	return chunkInfo.Count, nil
}

// Stream returns results via channels for efficient processing of large datasets.
func (c *Client) Stream(ctx context.Context, objectType string, q *Query) (<-chan map[string]any, <-chan error) {
	results := make(chan map[string]any, 100)
	errs := make(chan error, 1)

	go func() {
		defer close(results)
		defer close(errs)

		resolvedType := GetObjectType(objectType)

		// Ensure query has at least one filter (BV-BRC API requirement)
		if !q.HasFilters() {
			idCol := GetIDColumn(resolvedType)
			if idCol == "" {
				idCol = "id"
			}
			q = q.Clone()
			q.Eq(idCol, "*")
		}

		queryStr := q.Build()

		chunkSize := c.ChunkSize
		if q.LimitValue > 0 && q.LimitValue < chunkSize {
			chunkSize = q.LimitValue
		}

		offset := 0
		totalSent := 0

		for {
			select {
			case <-ctx.Done():
				errs <- ctx.Err()
				return
			default:
			}

			reqURL := fmt.Sprintf("%s/%s/", c.BaseURL, resolvedType)
			body := queryStr
			if body != "" {
				body += "&"
			}
			if offset > 0 {
				body += fmt.Sprintf("limit(%d,%d)", chunkSize, offset)
			} else {
				body += fmt.Sprintf("limit(%d)", chunkSize)
			}

			batch, chunkInfo, err := c.doQueryRequest(ctx, reqURL, body)
			if err != nil {
				errs <- err
				return
			}

			for _, record := range batch {
				if q.LimitValue > 0 && totalSent >= q.LimitValue {
					return
				}
				select {
				case results <- record:
					totalSent++
				case <-ctx.Done():
					errs <- ctx.Err()
					return
				}
			}

			if chunkInfo.IsLast || len(batch) < chunkSize {
				return
			}

			offset = chunkInfo.Next
		}
	}()

	return results, errs
}

// GetByID retrieves a single record by its ID.
func (c *Client) GetByID(ctx context.Context, objectType, id string) (map[string]any, error) {
	resolvedType := GetObjectType(objectType)
	reqURL := fmt.Sprintf("%s/%s/%s", c.BaseURL, resolvedType, c.urlEncode(id))

	if c.Debug {
		fmt.Printf("DEBUG: GET %s\n", reqURL)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}

	c.setHeaders(req)
	req.Header.Set("Accept", "application/json")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("executing request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}

	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API error: %s - %s", resp.Status, string(bodyBytes))
	}

	var result map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decoding response: %w", err)
	}

	return result, nil
}

// setHeaders sets common headers for API requests.
func (c *Client) setHeaders(req *http.Request) {
	if c.Token != "" {
		req.Header.Set("Authorization", c.Token)
	}
	req.Header.Set("User-Agent", "BV-BRC-Go-Client/1.0")
}

// urlEncode encodes a string for use in URLs, using PATRIC-specific encoding.
// This matches the encoding used by the Perl P3DataAPI.
func (c *Client) urlEncode(s string) string {
	// Replace special characters with encoded versions
	// Note: PATRIC uses non-standard encoding for some characters
	replacements := map[string]string{
		"<":  "%60",
		">":  "%62",
		"=":  "%61",
		`"`:  "%22",
		"&":  "%26",
		"#":  "%23",
		" ":  "%20",
		"\t": "%09",
	}

	result := s
	for old, new := range replacements {
		result = strings.ReplaceAll(result, old, new)
	}
	return result
}

// parseContentRange parses a Content-Range header value.
// Format: "items START-END/TOTAL"
func parseContentRange(header string) *ChunkInfo {
	info := &ChunkInfo{}

	if header == "" {
		return info
	}

	// Match pattern: items START-END/TOTAL
	re := regexp.MustCompile(`items\s+(\d+)-(\d+)/(\d+)`)
	matches := re.FindStringSubmatch(header)
	if len(matches) != 4 {
		return info
	}

	info.Start, _ = strconv.Atoi(matches[1])
	info.Next, _ = strconv.Atoi(matches[2])
	info.Count, _ = strconv.Atoi(matches[3])
	info.IsLast = info.Next >= info.Count

	return info
}

// GetObjectType returns the internal object type name for a given alias.
// If no alias is found, returns the input unchanged.
func GetObjectType(name string) string {
	if mapped, ok := Objects[name]; ok {
		return mapped
	}
	return name
}

// GetIDColumn returns the primary ID column for an object type.
// Returns empty string if the object type is unknown.
func GetIDColumn(objectType string) string {
	return IDColumns[objectType]
}

// GetDefaultFields returns the default fields for an object type.
// Returns nil if no defaults are defined.
func GetDefaultFields(objectType string) []string {
	return DefaultFields[objectType]
}

// FieldInfo describes a field in an object schema.
type FieldInfo struct {
	Name        string `json:"name"`
	Type        string `json:"type"`
	MultiValued bool   `json:"multiValued"`
}

// GetSchema returns the schema (field definitions) for an object type.
func (c *Client) GetSchema(ctx context.Context, objectType string) ([]FieldInfo, error) {
	resolvedType := GetObjectType(objectType)
	reqURL := fmt.Sprintf("%s/%s/schema?http_content-type=application/solrquery+x-www-form-urlencoded&http_accept=application/solr+json",
		c.BaseURL, resolvedType)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}

	c.setHeaders(req)
	req.Header.Set("Accept", "application/json")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("executing request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API error: %s - %s", resp.Status, string(bodyBytes))
	}

	var schema struct {
		Schema struct {
			Fields []FieldInfo `json:"fields"`
		} `json:"schema"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&schema); err != nil {
		return nil, fmt.Errorf("decoding schema: %w", err)
	}

	return schema.Schema.Fields, nil
}

// QueryCallback executes a query and calls the callback function with each batch of results.
// The callback receives the records and chunk information. Return false to stop fetching.
func (c *Client) QueryCallback(ctx context.Context, objectType string, q *Query, callback func([]map[string]any, *ChunkInfo) bool) error {
	resolvedType := GetObjectType(objectType)

	// Ensure query has at least one filter (BV-BRC API requirement)
	if !q.HasFilters() {
		idCol := GetIDColumn(resolvedType)
		if idCol == "" {
			idCol = "id"
		}
		q = q.Clone()
		q.Eq(idCol, "*")
	}

	queryStr := q.Build()

	chunkSize := c.ChunkSize
	if q.LimitValue > 0 && q.LimitValue < chunkSize {
		chunkSize = q.LimitValue
	}

	offset := 0
	totalFetched := 0

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		reqURL := fmt.Sprintf("%s/%s/", c.BaseURL, resolvedType)
		body := queryStr
		if body != "" {
			body += "&"
		}
		if offset > 0 {
			body += fmt.Sprintf("limit(%d,%d)", chunkSize, offset)
		} else {
			body += fmt.Sprintf("limit(%d)", chunkSize)
		}

		if c.Debug {
			fmt.Printf("DEBUG: POST %s\n", reqURL)
			fmt.Printf("DEBUG: Body: %s\n", body)
		}

		results, chunkInfo, err := c.doQueryRequest(ctx, reqURL, body)
		if err != nil {
			return err
		}

		// Trim results if we would exceed the limit
		if q.LimitValue > 0 && totalFetched+len(results) > q.LimitValue {
			results = results[:q.LimitValue-totalFetched]
		}

		totalFetched += len(results)

		// Call the callback
		if !callback(results, chunkInfo) {
			return nil
		}

		// Check if we have all results
		if chunkInfo.IsLast || len(results) < chunkSize {
			return nil
		}

		// Check if we've reached the requested limit
		if q.LimitValue > 0 && totalFetched >= q.LimitValue {
			return nil
		}

		offset = chunkInfo.Next
	}
}
