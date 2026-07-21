package api

import (
	"testing"
)

func TestNewQuery(t *testing.T) {
	q := NewQuery()
	if q == nil {
		t.Fatal("NewQuery() returned nil")
	}
	if len(q.SelectFields) != 0 {
		t.Errorf("SelectFields should be empty, got %d", len(q.SelectFields))
	}
	if len(q.Filters) != 0 {
		t.Errorf("Filters should be empty, got %d", len(q.Filters))
	}
}

func TestQuery_Select(t *testing.T) {
	q := NewQuery().Select("field1", "field2").Select("field3")

	if len(q.SelectFields) != 3 {
		t.Errorf("len(SelectFields) = %d, want 3", len(q.SelectFields))
	}
	if q.SelectFields[0] != "field1" {
		t.Errorf("SelectFields[0] = %q, want field1", q.SelectFields[0])
	}
}

func TestQuery_Filters(t *testing.T) {
	q := NewQuery().
		Eq("name", "value").
		Ne("status", "deleted").
		Lt("age", "100").
		Le("score", "50").
		Gt("count", "0").
		Ge("level", "1")

	if len(q.Filters) != 6 {
		t.Errorf("len(Filters) = %d, want 6", len(q.Filters))
	}

	// Check filter types
	expected := []FilterOp{OpEq, OpNe, OpLt, OpLe, OpGt, OpGe}
	for i, f := range q.Filters {
		if f.Op != expected[i] {
			t.Errorf("Filters[%d].Op = %q, want %q", i, f.Op, expected[i])
		}
	}
}

func TestQuery_In(t *testing.T) {
	q := NewQuery().In("status", "active", "pending", "review")

	if len(q.Filters) != 1 {
		t.Fatalf("len(Filters) = %d, want 1", len(q.Filters))
	}

	f := q.Filters[0]
	if f.Op != OpIn {
		t.Errorf("Op = %q, want %q", f.Op, OpIn)
	}
	if f.Field != "status" {
		t.Errorf("Field = %q, want status", f.Field)
	}
	if len(f.Values) != 3 {
		t.Errorf("len(Values) = %d, want 3", len(f.Values))
	}
}

func TestQuery_Required(t *testing.T) {
	q := NewQuery().Required("field1", "field2")

	if len(q.RequiredFields) != 2 {
		t.Errorf("len(RequiredFields) = %d, want 2", len(q.RequiredFields))
	}
}

func TestQuery_Keyword(t *testing.T) {
	q := NewQuery().WithKeyword("search term")

	if q.Keyword != "search term" {
		t.Errorf("Keyword = %q, want %q", q.Keyword, "search term")
	}
}

func TestQuery_Sort(t *testing.T) {
	q := NewQuery().
		Sort("name", false).
		Sort("date", true)

	if len(q.SortSpecs) != 2 {
		t.Fatalf("len(SortSpecs) = %d, want 2", len(q.SortSpecs))
	}

	if q.SortSpecs[0].Field != "name" || q.SortSpecs[0].Descending {
		t.Error("First sort should be name ascending")
	}
	if q.SortSpecs[1].Field != "date" || !q.SortSpecs[1].Descending {
		t.Error("Second sort should be date descending")
	}
}

func TestQuery_Limit(t *testing.T) {
	q := NewQuery().Limit(100)

	if q.LimitValue != 100 {
		t.Errorf("LimitValue = %d, want 100", q.LimitValue)
	}
}

func TestQuery_Build(t *testing.T) {
	tests := []struct {
		name  string
		query *Query
		want  string
	}{
		{
			name:  "empty query",
			query: NewQuery(),
			want:  "",
		},
		{
			name:  "select only",
			query: NewQuery().Select("field1", "field2"),
			want:  "select(field1,field2)",
		},
		{
			name:  "eq filter",
			query: NewQuery().Eq("name", "value"),
			want:  "eq(name,value)",
		},
		{
			name:  "in filter",
			query: NewQuery().In("status", "a", "b", "c"),
			want:  "in(status,(a,b,c))",
		},
		{
			name:  "required field",
			query: NewQuery().Required("field"),
			want:  "ne(field,)",
		},
		{
			name:  "keyword",
			query: NewQuery().WithKeyword("test"),
			want:  "keyword(test)",
		},
		{
			name:  "sort ascending",
			query: NewQuery().Sort("name", false),
			want:  "sort(+name)",
		},
		{
			name:  "sort descending",
			query: NewQuery().Sort("date", true),
			want:  "sort(-date)",
		},
		{
			name: "complex query",
			query: NewQuery().
				Select("genome_id", "genome_name").
				Eq("genus", "Streptomyces").
				Required("genome_name").
				Sort("genome_name", false),
			want: "select(genome_id,genome_name)&eq(genus,Streptomyces)&ne(genome_name,)&sort(+genome_name)",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.query.Build()
			if got != tt.want {
				t.Errorf("Build() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestQuery_Clone(t *testing.T) {
	original := NewQuery().
		Select("field1", "field2").
		Eq("name", "value").
		Required("field1").
		WithKeyword("test").
		Sort("name", false).
		Limit(100)

	clone := original.Clone()

	// Verify clone is equal
	if len(clone.SelectFields) != len(original.SelectFields) {
		t.Error("Clone SelectFields length mismatch")
	}
	if len(clone.Filters) != len(original.Filters) {
		t.Error("Clone Filters length mismatch")
	}
	if clone.Keyword != original.Keyword {
		t.Error("Clone Keyword mismatch")
	}
	if clone.LimitValue != original.LimitValue {
		t.Error("Clone LimitValue mismatch")
	}

	// Verify clone is independent
	clone.SelectFields[0] = "modified"
	if original.SelectFields[0] == "modified" {
		t.Error("Modifying clone affected original")
	}
}

func TestParseFilterSpec(t *testing.T) {
	tests := []struct {
		spec      string
		wantField string
		wantValue string
		wantErr   bool
	}{
		{"field,value", "field", "value", false},
		{"name,test value", "name", "test value", false},
		{"field,value,with,commas", "field", "value,with,commas", false},
		{"nocomma", "", "", true},
		{"", "", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.spec, func(t *testing.T) {
			field, value, err := ParseFilterSpec(tt.spec)
			if (err != nil) != tt.wantErr {
				t.Errorf("ParseFilterSpec() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if field != tt.wantField {
				t.Errorf("field = %q, want %q", field, tt.wantField)
			}
			if value != tt.wantValue {
				t.Errorf("value = %q, want %q", value, tt.wantValue)
			}
		})
	}
}

func TestParseInFilterSpec(t *testing.T) {
	tests := []struct {
		spec       string
		wantField  string
		wantValues []string
		wantErr    bool
	}{
		{"field,a,b,c", "field", []string{"a", "b", "c"}, false},
		{"status,active", "status", []string{"active"}, false},
		{"nocomma", "", nil, true},
	}

	for _, tt := range tests {
		t.Run(tt.spec, func(t *testing.T) {
			field, values, err := ParseInFilterSpec(tt.spec)
			if (err != nil) != tt.wantErr {
				t.Errorf("ParseInFilterSpec() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if field != tt.wantField {
				t.Errorf("field = %q, want %q", field, tt.wantField)
			}
			if len(values) != len(tt.wantValues) {
				t.Errorf("len(values) = %d, want %d", len(values), len(tt.wantValues))
			}
		})
	}
}
