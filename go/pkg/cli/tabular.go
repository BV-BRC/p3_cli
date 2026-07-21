package cli

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

// TabReader reads tab-delimited files with optional header support.
type TabReader struct {
	reader    *bufio.Reader
	headers   []string
	delimiter string
	hasHeader bool
	headerRead bool
}

// NewTabReader creates a new tab-delimited reader.
func NewTabReader(r io.Reader, hasHeader bool) *TabReader {
	return &TabReader{
		reader:    bufio.NewReader(r),
		delimiter: "\t",
		hasHeader: hasHeader,
	}
}

// Headers returns the header row. If the file has no headers,
// returns nil. Must be called before Read.
func (t *TabReader) Headers() ([]string, error) {
	if t.headerRead {
		return t.headers, nil
	}

	t.headerRead = true

	if !t.hasHeader {
		return nil, nil
	}

	line, err := t.readLine()
	if err != nil {
		return nil, err
	}

	t.headers = strings.Split(line, t.delimiter)
	return t.headers, nil
}

// Read reads the next row as a slice of strings.
// Returns io.EOF when there are no more rows.
func (t *TabReader) Read() ([]string, error) {
	// Ensure headers are read first if applicable
	if !t.headerRead {
		_, err := t.Headers()
		if err != nil {
			return nil, err
		}
	}

	line, err := t.readLine()
	if err != nil {
		return nil, err
	}

	return strings.Split(line, t.delimiter), nil
}

// ReadBatch reads up to n rows, returning the key column values and full rows.
func (t *TabReader) ReadBatch(n int, keyCol int) (keys []string, rows [][]string, err error) {
	for i := 0; i < n; i++ {
		row, err := t.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, nil, err
		}

		// Get key value
		var key string
		if keyCol < 0 {
			// Last column
			if len(row) > 0 {
				key = row[len(row)-1]
			}
		} else if keyCol < len(row) {
			key = row[keyCol]
		}

		keys = append(keys, key)
		rows = append(rows, row)
	}

	return keys, rows, nil
}

// FindColumn finds a column by name or 1-based index.
// If col is "0" or empty, returns -1 (indicating last column).
// If col is a number, returns the 0-based index.
// Otherwise, searches the headers for a matching name.
func (t *TabReader) FindColumn(col string) (int, error) {
	// Handle special case for "last column"
	if col == "" || col == "0" {
		return -1, nil // -1 means last column
	}

	// Try to parse as number (1-based)
	if idx, err := strconv.Atoi(col); err == nil {
		if idx < 0 {
			return 0, fmt.Errorf("invalid column index: %d", idx)
		}
		return idx - 1, nil // Convert to 0-based
	}

	// Search headers for matching name
	for i, h := range t.headers {
		if h == col {
			return i, nil
		}
	}

	return 0, fmt.Errorf("column %q not found in headers", col)
}

// readLine reads a line, skipping empty lines.
func (t *TabReader) readLine() (string, error) {
	for {
		line, err := t.reader.ReadString('\n')
		if err != nil && len(line) == 0 {
			return "", err
		}

		// Trim newline
		line = strings.TrimRight(line, "\r\n")

		// Skip empty lines
		if line == "" && err == nil {
			continue
		}

		return line, nil
	}
}

// TabWriter writes tab-delimited output.
type TabWriter struct {
	writer    *bufio.Writer
	delimiter string
}

// NewTabWriter creates a new tab-delimited writer.
func NewTabWriter(w io.Writer) *TabWriter {
	return &TabWriter{
		writer:    bufio.NewWriter(w),
		delimiter: "\t",
	}
}

// WriteHeaders writes the header row.
func (t *TabWriter) WriteHeaders(headers []string) error {
	return t.WriteRow(headers...)
}

// WriteRow writes a single row.
func (t *TabWriter) WriteRow(fields ...string) error {
	line := strings.Join(fields, t.delimiter)
	_, err := t.writer.WriteString(line + "\n")
	return err
}

// Flush flushes any buffered data to the underlying writer.
func (t *TabWriter) Flush() error {
	return t.writer.Flush()
}

// OpenInput opens the input file, or returns stdin if path is empty.
func OpenInput(path string) (io.ReadCloser, error) {
	if path == "" || path == "-" {
		return io.NopCloser(os.Stdin), nil
	}
	return os.Open(path)
}

// OpenOutput opens the output file, or returns stdout if path is empty.
func OpenOutput(path string) (io.WriteCloser, error) {
	if path == "" || path == "-" {
		return nopWriteCloser{os.Stdout}, nil
	}
	return os.Create(path)
}

// nopWriteCloser wraps a writer with a no-op Close.
type nopWriteCloser struct {
	io.Writer
}

func (nopWriteCloser) Close() error {
	return nil
}

// FormatValue formats a value for output, handling multi-valued fields.
func FormatValue(v any, delim string) string {
	switch val := v.(type) {
	case nil:
		return ""
	case string:
		return val
	case []any:
		parts := make([]string, len(val))
		for i, item := range val {
			parts[i] = fmt.Sprint(item)
		}
		return strings.Join(parts, delim)
	case []string:
		return strings.Join(val, delim)
	default:
		return fmt.Sprint(v)
	}
}

// FormatRecord formats a record as a tab-delimited row.
func FormatRecord(record map[string]any, fields []string, delim string) []string {
	row := make([]string, len(fields))
	for i, field := range fields {
		row[i] = FormatValue(record[field], delim)
	}
	return row
}
