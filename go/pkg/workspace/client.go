// Package workspace provides a client for the BV-BRC Workspace service.
//
// The Workspace service provides file and object storage for BV-BRC users.
// It uses a JSON-RPC protocol over HTTP.
package workspace

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/BV-BRC/bvbrc/pkg/auth"
)

const (
	// DefaultURL is the default Workspace service URL
	DefaultURL = "https://p3.theseed.org/services/Workspace"

	// DefaultTimeout is the HTTP client timeout
	DefaultTimeout = 30 * time.Minute
)

// Client is a client for the Workspace service.
type Client struct {
	URL     string
	Token   string
	Timeout time.Duration
	client  *http.Client
}

// ObjectMeta represents metadata for a workspace object.
// The array positions match the Perl API:
// [name, type, path, creation_time, id, owner, size, user_metadata, auto_metadata, user_perm, global_perm, shockurl, error]
type ObjectMeta struct {
	Name           string            `json:"name"`
	Type           string            `json:"type"`
	Path           string            `json:"path"`
	CreationTime   string            `json:"creation_time"`
	ID             string            `json:"id"`
	Owner          string            `json:"owner"`
	Size           int64             `json:"size"`
	UserMetadata   map[string]string `json:"user_metadata"`
	AutoMetadata   map[string]string `json:"auto_metadata"`
	UserPermission string            `json:"user_permission"`
	GlobalPerm     string            `json:"global_permission"`
	ShockURL       string            `json:"shockurl"`
	Error          string            `json:"error"`
}

// IsFolder returns true if this object is a folder.
func (m *ObjectMeta) IsFolder() bool {
	return m.Type == "folder" || m.Type == "modelfolder" ||
		(m.AutoMetadata != nil && m.AutoMetadata["is_folder"] == "1")
}

// FullPath returns the complete path including the name.
func (m *ObjectMeta) FullPath() string {
	return m.Path + m.Name
}

// ParseTime parses the creation time.
func (m *ObjectMeta) ParseTime() (time.Time, error) {
	return time.Parse(time.RFC3339, m.CreationTime)
}

// parseObjectMetaFromArray parses ObjectMeta from a JSON array (the API format).
func parseObjectMetaFromArray(arr []interface{}) *ObjectMeta {
	if len(arr) < 12 {
		return nil
	}

	meta := &ObjectMeta{}

	if v, ok := arr[0].(string); ok {
		meta.Name = v
	}
	if v, ok := arr[1].(string); ok {
		meta.Type = v
	}
	if v, ok := arr[2].(string); ok {
		meta.Path = v
	}
	if v, ok := arr[3].(string); ok {
		meta.CreationTime = v
	}
	if v, ok := arr[4].(string); ok {
		meta.ID = v
	}
	if v, ok := arr[5].(string); ok {
		meta.Owner = v
	}
	if v, ok := arr[6].(float64); ok {
		meta.Size = int64(v)
	}
	if v, ok := arr[7].(map[string]interface{}); ok {
		meta.UserMetadata = make(map[string]string)
		for k, val := range v {
			if s, ok := val.(string); ok {
				meta.UserMetadata[k] = s
			}
		}
	}
	if v, ok := arr[8].(map[string]interface{}); ok {
		meta.AutoMetadata = make(map[string]string)
		for k, val := range v {
			if s, ok := val.(string); ok {
				meta.AutoMetadata[k] = s
			}
		}
	}
	if v, ok := arr[9].(string); ok {
		meta.UserPermission = v
	}
	if v, ok := arr[10].(string); ok {
		meta.GlobalPerm = v
	}
	if len(arr) > 11 {
		if v, ok := arr[11].(string); ok {
			meta.ShockURL = v
		}
	}
	if len(arr) > 12 {
		if v, ok := arr[12].(string); ok {
			meta.Error = v
		}
	}

	return meta
}

// New creates a new Workspace client.
func New(opts ...Option) *Client {
	c := &Client{
		URL:     DefaultURL,
		Timeout: DefaultTimeout,
	}

	for _, opt := range opts {
		opt(c)
	}

	c.client = &http.Client{Timeout: c.Timeout}

	return c
}

// Option is a functional option for configuring the client.
type Option func(*Client)

// WithURL sets a custom Workspace service URL.
func WithURL(url string) Option {
	return func(c *Client) {
		c.URL = url
	}
}

// WithToken sets the authentication token.
func WithToken(token interface{}) Option {
	return func(c *Client) {
		switch t := token.(type) {
		case string:
			c.Token = t
		case *auth.Token:
			if t != nil {
				c.Token = t.String()
			}
		}
	}
}

// WithTimeout sets a custom timeout.
func WithTimeout(timeout time.Duration) Option {
	return func(c *Client) {
		c.Timeout = timeout
	}
}

// rpcRequest represents a JSON-RPC request.
type rpcRequest struct {
	Method  string        `json:"method"`
	Params  []interface{} `json:"params"`
	Version string        `json:"version"`
	ID      string        `json:"id"`
}

// rpcResponse represents a JSON-RPC response.
type rpcResponse struct {
	Result json.RawMessage `json:"result"`
	Error  *rpcError       `json:"error,omitempty"`
	ID     string          `json:"id"`
}

type rpcError struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Error   json.RawMessage `json:"error,omitempty"`
}

func (e *rpcError) String() string {
	if e.Error != nil {
		return string(e.Error)
	}
	return e.Message
}

// call makes a JSON-RPC call to the Workspace service.
func (c *Client) call(method string, params interface{}) (json.RawMessage, error) {
	req := rpcRequest{
		Method:  "Workspace." + method,
		Params:  []interface{}{params},
		Version: "1.1",
		ID:      "1",
	}

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("marshaling request: %w", err)
	}

	httpReq, err := http.NewRequest("POST", c.URL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("creating request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	if c.Token != "" {
		httpReq.Header.Set("Authorization", c.Token)
	}

	resp, err := c.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("making request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("reading response: %w", err)
	}

	var rpcResp rpcResponse
	if err := json.Unmarshal(respBody, &rpcResp); err != nil {
		return nil, fmt.Errorf("parsing response: %w (body: %s)", err, string(respBody))
	}

	if rpcResp.Error != nil {
		errMsg := rpcResp.Error.String()
		// Extract error message from _ERROR_..._ERROR_ format
		if start := strings.Index(errMsg, "_ERROR_"); start != -1 {
			if end := strings.LastIndex(errMsg, "_ERROR_"); end > start {
				errMsg = errMsg[start+7 : end]
			}
		}
		return nil, fmt.Errorf("%s", errMsg)
	}

	return rpcResp.Result, nil
}

// LsParams are parameters for the ls method.
type LsParams struct {
	Paths     []string `json:"paths"`
	Recursive bool     `json:"recursive,omitempty"`
	AdminMode bool     `json:"adminmode,omitempty"`
}

// Ls lists the contents of workspace paths.
// Returns a map of path -> list of ObjectMeta.
func (c *Client) Ls(params LsParams) (map[string][]*ObjectMeta, error) {
	result, err := c.call("ls", params)
	if err != nil {
		return nil, err
	}

	// The result can come back as either:
	// 1. A map of path -> array of arrays (when wrapped in JSON-RPC result)
	// 2. An array containing such a map (JSON-RPC array wrapper)

	// First, try to parse as an array and extract the first element
	var arrayResult []json.RawMessage
	if err := json.Unmarshal(result, &arrayResult); err == nil && len(arrayResult) > 0 {
		// It's an array, use the first element
		result = arrayResult[0]
	}

	// Now try to parse as a map
	var rawResult map[string][]json.RawMessage
	if err := json.Unmarshal(result, &rawResult); err != nil {
		return nil, fmt.Errorf("parsing ls result: %w", err)
	}

	parsedResult := make(map[string][]*ObjectMeta)
	for path, entries := range rawResult {
		var metas []*ObjectMeta
		for _, entry := range entries {
			var arr []interface{}
			if err := json.Unmarshal(entry, &arr); err != nil {
				continue
			}
			if meta := parseObjectMetaFromArray(arr); meta != nil {
				metas = append(metas, meta)
			}
		}
		parsedResult[path] = metas
	}

	return parsedResult, nil
}

// GetParams are parameters for the get method.
type GetParams struct {
	Objects      []string `json:"objects"`
	MetadataOnly bool     `json:"metadata_only,omitempty"`
	AdminMode    bool     `json:"adminmode,omitempty"`
}

// GetResult represents the result of a get call.
type GetResult struct {
	Meta *ObjectMeta
	Data string
}

// Get retrieves objects from the workspace.
func (c *Client) Get(params GetParams) ([]*GetResult, error) {
	result, err := c.call("get", params)
	if err != nil {
		return nil, err
	}

	// The result is wrapped in an array: [[obj1, obj2, ...]]
	// where each obj is [metadata_array, data_string]
	var outerArray []json.RawMessage
	if err := json.Unmarshal(result, &outerArray); err != nil {
		return nil, fmt.Errorf("parsing get result outer array: %w", err)
	}

	if len(outerArray) == 0 {
		return nil, nil
	}

	// Parse the inner array of object results
	var rawResult [][]json.RawMessage
	if err := json.Unmarshal(outerArray[0], &rawResult); err != nil {
		return nil, fmt.Errorf("parsing get result: %w", err)
	}

	var results []*GetResult
	for _, entry := range rawResult {
		if len(entry) < 1 {
			continue
		}

		resultItem := &GetResult{}

		// Parse metadata array
		var metaArr []interface{}
		if err := json.Unmarshal(entry[0], &metaArr); err == nil {
			resultItem.Meta = parseObjectMetaFromArray(metaArr)
		}

		// Parse data if present
		if len(entry) > 1 {
			var data string
			if err := json.Unmarshal(entry[1], &data); err == nil {
				resultItem.Data = data
			}
		}

		results = append(results, resultItem)
	}

	return results, nil
}

// Stat returns metadata for a single object.
func (c *Client) Stat(path string, adminMode bool) (*ObjectMeta, error) {
	results, err := c.Get(GetParams{
		Objects:      []string{path},
		MetadataOnly: true,
		AdminMode:    adminMode,
	})
	if err != nil {
		return nil, err
	}
	if len(results) == 0 || results[0].Meta == nil {
		return nil, fmt.Errorf("object not found: %s", path)
	}
	return results[0].Meta, nil
}

// CreateParams are parameters for the create method.
type CreateParams struct {
	Objects           []CreateObject `json:"-"` // Will be serialized specially
	Permission        string         `json:"permission,omitempty"`
	CreateUploadNodes bool           `json:"createUploadNodes,omitempty"`
	Overwrite         bool           `json:"overwrite,omitempty"`
	AdminMode         bool           `json:"adminmode,omitempty"`
}

// CreateObject represents an object to create.
type CreateObject struct {
	Path         string
	Type         string
	UserMetadata map[string]string
	Data         string
	CreationTime string
}

// MarshalJSON custom marshals CreateParams for the API.
func (p CreateParams) MarshalJSON() ([]byte, error) {
	type alias CreateParams

	// Convert objects to array format: [[path, type, metadata, data, creation_time], ...]
	// Only include creation_time if it has a value
	objects := make([][]interface{}, len(p.Objects))
	for i, obj := range p.Objects {
		// Use empty map instead of nil for metadata to avoid null in JSON
		metadata := obj.UserMetadata
		if metadata == nil {
			metadata = map[string]string{}
		}

		// Build object array - only include creation_time if specified
		if obj.CreationTime != "" {
			objects[i] = []interface{}{
				obj.Path,
				obj.Type,
				metadata,
				obj.Data,
				obj.CreationTime,
			}
		} else if obj.Data != "" {
			objects[i] = []interface{}{
				obj.Path,
				obj.Type,
				metadata,
				obj.Data,
			}
		} else {
			// For folders and empty files, just path and type
			objects[i] = []interface{}{
				obj.Path,
				obj.Type,
			}
		}
	}

	// Permission must be a valid value: a, w, r, o, n, or p
	// Default to "n" (none) if not specified
	permission := p.Permission
	if permission == "" {
		permission = "n"
	}

	result := map[string]interface{}{
		"objects":    objects,
		"permission": permission,
	}

	// Only include optional fields if they have non-default values
	if p.CreateUploadNodes {
		result["createUploadNodes"] = true
	}
	if p.Overwrite {
		result["overwrite"] = true
	}
	if p.AdminMode {
		result["adminmode"] = true
	}

	return json.Marshal(result)
}

// Create creates objects in the workspace.
func (c *Client) Create(params CreateParams) ([]*ObjectMeta, error) {
	result, err := c.call("create", params)
	if err != nil {
		return nil, err
	}

	// Result is wrapped in an array: [[ [meta1], [meta2], ... ]]
	var outerArray []json.RawMessage
	if err := json.Unmarshal(result, &outerArray); err != nil {
		return nil, fmt.Errorf("parsing create result outer array: %w", err)
	}

	if len(outerArray) == 0 {
		return nil, nil
	}

	var rawResult []json.RawMessage
	if err := json.Unmarshal(outerArray[0], &rawResult); err != nil {
		return nil, fmt.Errorf("parsing create result: %w", err)
	}

	var metas []*ObjectMeta
	for _, entry := range rawResult {
		var arr []interface{}
		if err := json.Unmarshal(entry, &arr); err != nil {
			continue
		}
		if meta := parseObjectMetaFromArray(arr); meta != nil {
			metas = append(metas, meta)
		}
	}

	return metas, nil
}

// Mkdir creates a folder in the workspace.
func (c *Client) Mkdir(path string, adminMode bool) (*ObjectMeta, error) {
	results, err := c.Create(CreateParams{
		Objects: []CreateObject{{
			Path: path,
			Type: "folder",
		}},
		AdminMode: adminMode,
	})
	if err != nil {
		return nil, err
	}
	if len(results) == 0 {
		return nil, fmt.Errorf("failed to create directory")
	}
	return results[0], nil
}

// DeleteParams are parameters for the delete method.
type DeleteParams struct {
	Objects           []string `json:"objects"`
	DeleteDirectories bool     `json:"deleteDirectories,omitempty"`
	Force             bool     `json:"force,omitempty"`
	AdminMode         bool     `json:"adminmode,omitempty"`
}

// Delete removes objects from the workspace.
func (c *Client) Delete(params DeleteParams) error {
	_, err := c.call("delete", params)
	return err
}

// CopyParams are parameters for the copy method.
type CopyParams struct {
	Objects   [][2]string `json:"objects"` // [[src, dest], ...]
	Overwrite bool        `json:"overwrite,omitempty"`
	AdminMode bool        `json:"adminmode,omitempty"`
}

// Copy copies objects in the workspace.
func (c *Client) Copy(params CopyParams) error {
	_, err := c.call("copy", params)
	return err
}

// DownloadFile downloads a workspace file to a local path.
func (c *Client) DownloadFile(wsPath, localPath string) error {
	results, err := c.Get(GetParams{
		Objects:      []string{wsPath},
		MetadataOnly: false,
	})
	if err != nil {
		return err
	}
	if len(results) == 0 {
		return fmt.Errorf("object not found: %s", wsPath)
	}

	result := results[0]

	// If the data is in shock, we need to download from there
	if result.Meta != nil && result.Meta.ShockURL != "" {
		return c.downloadFromShock(result.Meta.ShockURL, localPath)
	}

	// Otherwise, the data is inline
	return os.WriteFile(localPath, []byte(result.Data), 0644)
}

// Cat writes the content of a workspace file to a writer.
func (c *Client) Cat(wsPath string, w io.Writer) error {
	results, err := c.Get(GetParams{
		Objects:      []string{wsPath},
		MetadataOnly: false,
	})
	if err != nil {
		return err
	}
	if len(results) == 0 {
		return fmt.Errorf("object not found: %s", wsPath)
	}

	result := results[0]

	// If the data is in shock, stream from there
	if result.Meta != nil && result.Meta.ShockURL != "" {
		return c.streamFromShock(result.Meta.ShockURL, w)
	}

	// Otherwise, write inline data
	_, err = w.Write([]byte(result.Data))
	return err
}

// downloadFromShock downloads data from a shock URL to a local file.
func (c *Client) downloadFromShock(shockURL, localPath string) error {
	f, err := os.Create(localPath)
	if err != nil {
		return fmt.Errorf("creating file: %w", err)
	}
	defer f.Close()

	return c.streamFromShock(shockURL, f)
}

// streamFromShock streams data from a shock URL to a writer.
func (c *Client) streamFromShock(shockURL string, w io.Writer) error {
	req, err := http.NewRequest("GET", shockURL+"?download", nil)
	if err != nil {
		return fmt.Errorf("creating shock request: %w", err)
	}

	if c.Token != "" {
		req.Header.Set("Authorization", "OAuth "+c.Token)
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("downloading from shock: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("shock download failed (status %d): %s", resp.StatusCode, string(body))
	}

	_, err = io.Copy(w, resp.Body)
	return err
}
