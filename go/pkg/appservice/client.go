// Package appservice provides a client for the BV-BRC AppService.
//
// The AppService manages job submission and status tracking for
// BV-BRC computational services.
package appservice

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/BV-BRC/bvbrc/pkg/auth"
)

const (
	// DefaultURL is the default AppService URL
	DefaultURL = "https://p3.theseed.org/services/app_service"

	// DefaultTimeout is the HTTP client timeout
	DefaultTimeout = 30 * time.Minute
)

// Client is a client for the AppService.
type Client struct {
	URL     string
	Token   string
	Timeout time.Duration
	client  *http.Client
}

// Task represents a submitted job task.
type Task struct {
	ID             interface{}            `json:"id"`
	ParentID       interface{}            `json:"parent_id,omitempty"`
	App            string                 `json:"app"`
	Workspace      string                 `json:"workspace"`
	Parameters     map[string]interface{} `json:"parameters,omitempty"`
	UserID         string                 `json:"user_id"`
	Status         string                 `json:"status"`
	AWEStatus      string                 `json:"awe_status,omitempty"`
	SubmitTime     string                 `json:"submit_time"`
	StartTime      string                 `json:"start_time,omitempty"`
	CompletedTime  string                 `json:"completed_time,omitempty"`
	ElapsedTime    string                 `json:"elapsed_time,omitempty"`
	StdoutShock    string                 `json:"stdout_shock_node,omitempty"`
	StderrShock    string                 `json:"stderr_shock_node,omitempty"`
}

// GetID returns the task ID as a string.
func (t *Task) GetID() string {
	switch v := t.ID.(type) {
	case string:
		return v
	case float64:
		return fmt.Sprintf("%.0f", v)
	case int:
		return fmt.Sprintf("%d", v)
	default:
		return fmt.Sprintf("%v", v)
	}
}

// TaskDetails contains detailed information about a task execution.
type TaskDetails struct {
	StdoutURL string `json:"stdout_url,omitempty"`
	StderrURL string `json:"stderr_url,omitempty"`
	PID       string `json:"pid,omitempty"`
	Hostname  string `json:"hostname,omitempty"`
	ExitCode  string `json:"exitcode,omitempty"`
}

// GetExitCode returns the exit code as an integer.
func (d *TaskDetails) GetExitCode() int {
	var code int
	fmt.Sscanf(d.ExitCode, "%d", &code)
	return code
}

// App represents an available application.
type App struct {
	ID          string         `json:"id"`
	Script      string         `json:"script,omitempty"`
	Label       string         `json:"label,omitempty"`
	Description string         `json:"description,omitempty"`
	Parameters  []AppParameter `json:"parameters,omitempty"`
}

// AppParameter represents a parameter for an app.
type AppParameter struct {
	ID       string `json:"id"`
	Label    string `json:"label,omitempty"`
	Required int    `json:"required,omitempty"`
	Default  string `json:"default,omitempty"`
	Desc     string `json:"desc,omitempty"`
	Type     string `json:"type,omitempty"`
	Enum     string `json:"enum,omitempty"`
	WsType   string `json:"wstype,omitempty"`
}

// StartParams contains parameters for starting an app.
type StartParams struct {
	ParentID         string            `json:"parent_id,omitempty"`
	Workspace        string            `json:"workspace,omitempty"`
	BaseURL          string            `json:"base_url,omitempty"`
	ContainerID      string            `json:"container_id,omitempty"`
	UserMetadata     string            `json:"user_metadata,omitempty"`
	Reservation      string            `json:"reservation,omitempty"`
	DataContainerID  string            `json:"data_container_id,omitempty"`
	DisablePreflight int               `json:"disable_preflight,omitempty"`
	PreflightData    map[string]string `json:"preflight_data,omitempty"`
}

// New creates a new AppService client.
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

// WithURL sets a custom AppService URL.
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

// call makes a JSON-RPC call to the AppService.
func (c *Client) call(method string, params ...interface{}) (json.RawMessage, error) {
	if params == nil {
		params = []interface{}{}
	}

	req := rpcRequest{
		Method:  "AppService." + method,
		Params:  params,
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

// ServiceStatus returns the service status.
func (c *Client) ServiceStatus() (bool, string, error) {
	result, err := c.call("service_status")
	if err != nil {
		return false, "", err
	}

	var status []interface{}
	if err := json.Unmarshal(result, &status); err != nil {
		return false, "", fmt.Errorf("parsing status: %w", err)
	}

	if len(status) < 2 {
		return false, "", fmt.Errorf("unexpected status format")
	}

	enabled, _ := status[0].(float64)
	message, _ := status[1].(string)

	return enabled != 0, message, nil
}

// EnumerateApps returns a list of available applications.
func (c *Client) EnumerateApps() ([]*App, error) {
	result, err := c.call("enumerate_apps")
	if err != nil {
		return nil, err
	}

	var apps []*App
	if err := json.Unmarshal(result, &apps); err != nil {
		return nil, fmt.Errorf("parsing apps: %w", err)
	}

	return apps, nil
}

// StartApp starts an application with the given parameters.
func (c *Client) StartApp(appID string, params map[string]interface{}, workspace string) (*Task, error) {
	result, err := c.call("start_app", appID, params, workspace)
	if err != nil {
		return nil, err
	}

	// Result is wrapped in an array: [task]
	var outerArray []json.RawMessage
	if err := json.Unmarshal(result, &outerArray); err != nil {
		return nil, fmt.Errorf("parsing task outer array: %w", err)
	}

	if len(outerArray) == 0 {
		return nil, fmt.Errorf("no task returned")
	}

	var task Task
	if err := json.Unmarshal(outerArray[0], &task); err != nil {
		return nil, fmt.Errorf("parsing task: %w", err)
	}

	return &task, nil
}

// StartApp2 starts an application with extended start parameters.
func (c *Client) StartApp2(appID string, params map[string]interface{}, startParams StartParams) (*Task, error) {
	result, err := c.call("start_app2", appID, params, startParams)
	if err != nil {
		return nil, err
	}

	// Result is wrapped in an array: [task]
	var outerArray []json.RawMessage
	if err := json.Unmarshal(result, &outerArray); err != nil {
		return nil, fmt.Errorf("parsing task outer array: %w", err)
	}

	if len(outerArray) == 0 {
		return nil, fmt.Errorf("no task returned")
	}

	var task Task
	if err := json.Unmarshal(outerArray[0], &task); err != nil {
		return nil, fmt.Errorf("parsing task: %w", err)
	}

	return &task, nil
}

// QueryTasks queries the status of multiple tasks.
func (c *Client) QueryTasks(taskIDs []string) (map[string]*Task, error) {
	result, err := c.call("query_tasks", taskIDs)
	if err != nil {
		return nil, err
	}

	// Result is wrapped in an array: [{ "id": {...}, ... }]
	var outerArray []json.RawMessage
	if err := json.Unmarshal(result, &outerArray); err != nil {
		return nil, fmt.Errorf("parsing tasks outer array: %w", err)
	}

	if len(outerArray) == 0 {
		return nil, nil
	}

	var tasks map[string]*Task
	if err := json.Unmarshal(outerArray[0], &tasks); err != nil {
		return nil, fmt.Errorf("parsing tasks: %w", err)
	}

	return tasks, nil
}

// QueryTaskDetails gets detailed information about a task.
func (c *Client) QueryTaskDetails(taskID string) (*TaskDetails, error) {
	result, err := c.call("query_task_details", taskID)
	if err != nil {
		return nil, err
	}

	// Result is wrapped in an array: [{ ... }]
	var outerArray []json.RawMessage
	if err := json.Unmarshal(result, &outerArray); err != nil {
		return nil, fmt.Errorf("parsing details outer array: %w", err)
	}

	if len(outerArray) == 0 {
		return nil, nil
	}

	var details TaskDetails
	if err := json.Unmarshal(outerArray[0], &details); err != nil {
		return nil, fmt.Errorf("parsing details: %w", err)
	}

	return &details, nil
}

// QueryTaskSummary returns a summary of task counts by status.
func (c *Client) QueryTaskSummary() (map[string]int, error) {
	result, err := c.call("query_task_summary")
	if err != nil {
		return nil, err
	}

	var summary map[string]int
	if err := json.Unmarshal(result, &summary); err != nil {
		return nil, fmt.Errorf("parsing summary: %w", err)
	}

	return summary, nil
}

// EnumerateTasks lists tasks with pagination.
func (c *Client) EnumerateTasks(offset, count int) ([]*Task, error) {
	result, err := c.call("enumerate_tasks", offset, count)
	if err != nil {
		return nil, err
	}

	var tasks []*Task
	if err := json.Unmarshal(result, &tasks); err != nil {
		return nil, fmt.Errorf("parsing tasks: %w", err)
	}

	return tasks, nil
}

// GetStdout fetches the stdout output for a task.
func (c *Client) GetStdout(taskID string) (string, error) {
	details, err := c.QueryTaskDetails(taskID)
	if err != nil {
		return "", err
	}
	if details.StdoutURL == "" {
		return "", nil
	}
	return c.fetchURL(details.StdoutURL)
}

// GetStderr fetches the stderr output for a task.
func (c *Client) GetStderr(taskID string) (string, error) {
	details, err := c.QueryTaskDetails(taskID)
	if err != nil {
		return "", err
	}
	if details.StderrURL == "" {
		return "", nil
	}
	return c.fetchURL(details.StderrURL)
}

// fetchURL fetches content from a URL.
func (c *Client) fetchURL(url string) (string, error) {
	resp, err := c.client.Get(url)
	if err != nil {
		return "", fmt.Errorf("fetching URL: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("fetch failed with status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("reading response: %w", err)
	}

	return string(body), nil
}

// StreamURL streams content from a URL to a writer.
func (c *Client) StreamURL(url string, w io.Writer) error {
	resp, err := c.client.Get(url)
	if err != nil {
		return fmt.Errorf("fetching URL: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("fetch failed with status %d", resp.StatusCode)
	}

	_, err = io.Copy(w, resp.Body)
	return err
}
