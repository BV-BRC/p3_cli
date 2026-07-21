package cli

import (
	"io"
	"strings"
	"testing"
)

func TestTabReader_Headers(t *testing.T) {
	input := "col1\tcol2\tcol3\nval1\tval2\tval3"
	reader := NewTabReader(strings.NewReader(input), true)

	headers, err := reader.Headers()
	if err != nil {
		t.Fatalf("Headers() error = %v", err)
	}

	if len(headers) != 3 {
		t.Errorf("len(headers) = %d, want 3", len(headers))
	}

	expected := []string{"col1", "col2", "col3"}
	for i, h := range headers {
		if h != expected[i] {
			t.Errorf("headers[%d] = %q, want %q", i, h, expected[i])
		}
	}
}

func TestTabReader_NoHeaders(t *testing.T) {
	input := "val1\tval2\tval3"
	reader := NewTabReader(strings.NewReader(input), false)

	headers, err := reader.Headers()
	if err != nil {
		t.Fatalf("Headers() error = %v", err)
	}

	if headers != nil {
		t.Errorf("headers should be nil for no-header mode")
	}
}

func TestTabReader_Read(t *testing.T) {
	input := "col1\tcol2\nval1\tval2\nval3\tval4"
	reader := NewTabReader(strings.NewReader(input), true)

	// Read headers first
	_, err := reader.Headers()
	if err != nil {
		t.Fatalf("Headers() error = %v", err)
	}

	// Read first data row
	row, err := reader.Read()
	if err != nil {
		t.Fatalf("Read() error = %v", err)
	}
	if len(row) != 2 || row[0] != "val1" || row[1] != "val2" {
		t.Errorf("row = %v, want [val1 val2]", row)
	}

	// Read second data row
	row, err = reader.Read()
	if err != nil {
		t.Fatalf("Read() error = %v", err)
	}
	if len(row) != 2 || row[0] != "val3" || row[1] != "val4" {
		t.Errorf("row = %v, want [val3 val4]", row)
	}

	// Read past end
	_, err = reader.Read()
	if err != io.EOF {
		t.Errorf("Read() at EOF should return io.EOF, got %v", err)
	}
}

func TestTabReader_ReadBatch(t *testing.T) {
	input := "key\tvalue\na\t1\nb\t2\nc\t3\nd\t4\ne\t5"
	reader := NewTabReader(strings.NewReader(input), true)

	_, err := reader.Headers()
	if err != nil {
		t.Fatalf("Headers() error = %v", err)
	}

	// Read batch of 3
	keys, rows, err := reader.ReadBatch(3, 0)
	if err != nil {
		t.Fatalf("ReadBatch() error = %v", err)
	}

	if len(keys) != 3 {
		t.Errorf("len(keys) = %d, want 3", len(keys))
	}
	if len(rows) != 3 {
		t.Errorf("len(rows) = %d, want 3", len(rows))
	}

	expectedKeys := []string{"a", "b", "c"}
	for i, k := range keys {
		if k != expectedKeys[i] {
			t.Errorf("keys[%d] = %q, want %q", i, k, expectedKeys[i])
		}
	}
}

func TestTabReader_FindColumn(t *testing.T) {
	input := "id\tname\tvalue"
	reader := NewTabReader(strings.NewReader(input), true)
	_, _ = reader.Headers()

	tests := []struct {
		col     string
		want    int
		wantErr bool
	}{
		{"0", -1, false},     // 0 means last column
		{"", -1, false},      // empty means last column
		{"1", 0, false},      // 1-based -> 0-based
		{"2", 1, false},
		{"3", 2, false},
		{"id", 0, false},     // by name
		{"name", 1, false},
		{"value", 2, false},
		{"unknown", 0, true}, // unknown column
		{"-1", 0, true},      // negative index
	}

	for _, tt := range tests {
		t.Run(tt.col, func(t *testing.T) {
			got, err := reader.FindColumn(tt.col)
			if (err != nil) != tt.wantErr {
				t.Errorf("FindColumn(%q) error = %v, wantErr %v", tt.col, err, tt.wantErr)
				return
			}
			if got != tt.want {
				t.Errorf("FindColumn(%q) = %d, want %d", tt.col, got, tt.want)
			}
		})
	}
}

func TestTabWriter_WriteRow(t *testing.T) {
	var buf strings.Builder
	writer := NewTabWriter(&buf)

	err := writer.WriteRow("a", "b", "c")
	if err != nil {
		t.Fatalf("WriteRow() error = %v", err)
	}

	err = writer.Flush()
	if err != nil {
		t.Fatalf("Flush() error = %v", err)
	}

	expected := "a\tb\tc\n"
	if buf.String() != expected {
		t.Errorf("output = %q, want %q", buf.String(), expected)
	}
}

func TestFormatValue(t *testing.T) {
	tests := []struct {
		name  string
		value any
		delim string
		want  string
	}{
		{"nil", nil, "::", ""},
		{"string", "hello", "::", "hello"},
		{"int", 42, "::", "42"},
		{"float", 3.14, "::", "3.14"},
		{"string slice", []string{"a", "b", "c"}, "::", "a::b::c"},
		{"string slice comma", []string{"a", "b", "c"}, ",", "a,b,c"},
		{"any slice", []any{"x", 1, true}, "::", "x::1::true"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := FormatValue(tt.value, tt.delim)
			if got != tt.want {
				t.Errorf("FormatValue(%v, %q) = %q, want %q", tt.value, tt.delim, got, tt.want)
			}
		})
	}
}

func TestFormatRecord(t *testing.T) {
	record := map[string]any{
		"id":     "123",
		"name":   "Test",
		"values": []string{"a", "b"},
	}

	fields := []string{"id", "name", "values", "missing"}
	got := FormatRecord(record, fields, "::")

	expected := []string{"123", "Test", "a::b", ""}
	if len(got) != len(expected) {
		t.Fatalf("len(got) = %d, want %d", len(got), len(expected))
	}

	for i, g := range got {
		if g != expected[i] {
			t.Errorf("got[%d] = %q, want %q", i, g, expected[i])
		}
	}
}

func TestIOOptions_GetDelimiter(t *testing.T) {
	tests := []struct {
		delim string
		want  string
	}{
		{"::", "::"},
		{"tab", "\t"},
		{"space", " "},
		{"semi", "; "},
		{"comma", ","},
		{"custom", "custom"},
	}

	for _, tt := range tests {
		t.Run(tt.delim, func(t *testing.T) {
			opts := &IOOptions{Delim: tt.delim}
			got := opts.GetDelimiter()
			if got != tt.want {
				t.Errorf("GetDelimiter() = %q, want %q", got, tt.want)
			}
		})
	}
}
