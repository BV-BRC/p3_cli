package cli

import (
	"testing"

	"github.com/spf13/cobra"
)

func TestAddDataFlags(t *testing.T) {
	cmd := &cobra.Command{}
	opts := &DataOptions{}

	AddDataFlags(cmd, opts)

	// Check that all flags were added
	flags := []string{"attr", "count", "eq", "lt", "le", "gt", "ge", "ne", "in", "required", "keyword", "limit", "debug"}
	for _, name := range flags {
		if cmd.Flags().Lookup(name) == nil {
			t.Errorf("flag %q not found", name)
		}
	}

	// Check short flags
	shortFlags := map[string]string{
		"a": "attr",
		"K": "count",
		"e": "eq",
		"r": "required",
	}
	for short, long := range shortFlags {
		if cmd.Flags().ShorthandLookup(short) == nil {
			t.Errorf("short flag %q (for %s) not found", short, long)
		}
	}
}

func TestAddColFlags(t *testing.T) {
	cmd := &cobra.Command{}
	opts := &ColOptions{}

	AddColFlags(cmd, opts, 200)

	// Check flags
	if cmd.Flags().Lookup("col") == nil {
		t.Error("col flag not found")
	}
	if cmd.Flags().Lookup("batchSize") == nil {
		t.Error("batchSize flag not found")
	}
	if cmd.Flags().Lookup("nohead") == nil {
		t.Error("nohead flag not found")
	}

	// Check default batch size
	if opts.BatchSize != 200 {
		t.Errorf("BatchSize = %d, want 200", opts.BatchSize)
	}
}

func TestAddIOFlags(t *testing.T) {
	cmd := &cobra.Command{}
	opts := &IOOptions{}

	AddIOFlags(cmd, opts)

	// Check flags
	if cmd.Flags().Lookup("input") == nil {
		t.Error("input flag not found")
	}
	if cmd.Flags().Lookup("output") == nil {
		t.Error("output flag not found")
	}
	if cmd.Flags().Lookup("delim") == nil {
		t.Error("delim flag not found")
	}

	// Check default delimiter
	if opts.Delim != "::" {
		t.Errorf("Delim = %q, want %q", opts.Delim, "::")
	}
}

func TestDataOptions_BuildQuery(t *testing.T) {
	tests := []struct {
		name          string
		opts          DataOptions
		defaultFields []string
		wantErr       bool
		wantSelect    int
		wantFilters   int
	}{
		{
			name:          "empty options uses defaults",
			opts:          DataOptions{},
			defaultFields: []string{"id", "name"},
			wantErr:       false,
			wantSelect:    2,
			wantFilters:   0,
		},
		{
			name: "explicit attrs override defaults",
			opts: DataOptions{
				Attr: []string{"field1", "field2", "field3"},
			},
			defaultFields: []string{"id"},
			wantErr:       false,
			wantSelect:    3,
			wantFilters:   0,
		},
		{
			name: "equality filter",
			opts: DataOptions{
				Equal: []string{"name,value"},
			},
			wantErr:     false,
			wantFilters: 1,
		},
		{
			name: "multiple filter types",
			opts: DataOptions{
				Equal: []string{"a,1"},
				Lt:    []string{"b,2"},
				Gt:    []string{"c,3"},
			},
			wantErr:     false,
			wantFilters: 3,
		},
		{
			name: "invalid filter spec",
			opts: DataOptions{
				Equal: []string{"invalid-no-comma"},
			},
			wantErr: true,
		},
		{
			name: "with keyword and limit",
			opts: DataOptions{
				Keyword: "search term",
				Limit:   100,
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			q, err := tt.opts.BuildQuery(tt.defaultFields)
			if (err != nil) != tt.wantErr {
				t.Errorf("BuildQuery() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if tt.wantErr {
				return
			}

			if tt.wantSelect > 0 && len(q.SelectFields) != tt.wantSelect {
				t.Errorf("len(SelectFields) = %d, want %d", len(q.SelectFields), tt.wantSelect)
			}
			if len(q.Filters) != tt.wantFilters {
				t.Errorf("len(Filters) = %d, want %d", len(q.Filters), tt.wantFilters)
			}
		})
	}
}

func TestDataOptions_GetSelectFields(t *testing.T) {
	defaults := []string{"default1", "default2"}

	// With explicit attrs
	opts := DataOptions{Attr: []string{"explicit1"}}
	fields := opts.GetSelectFields(defaults)
	if len(fields) != 1 || fields[0] != "explicit1" {
		t.Errorf("GetSelectFields with attrs = %v, want [explicit1]", fields)
	}

	// Without explicit attrs
	opts = DataOptions{}
	fields = opts.GetSelectFields(defaults)
	if len(fields) != 2 || fields[0] != "default1" {
		t.Errorf("GetSelectFields without attrs = %v, want defaults", fields)
	}
}
