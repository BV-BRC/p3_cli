package api

import (
	"fmt"
	"net/url"
	"strings"
)

// FilterOp represents a filter operation type.
type FilterOp string

const (
	OpEq FilterOp = "eq" // Equality (substring for strings, exact for numbers)
	OpNe FilterOp = "ne" // Not equal
	OpLt FilterOp = "lt" // Less than
	OpLe FilterOp = "le" // Less than or equal
	OpGt FilterOp = "gt" // Greater than
	OpGe FilterOp = "ge" // Greater than or equal
	OpIn FilterOp = "in" // Any of the specified values
)

// Filter represents a query filter condition.
type Filter struct {
	Op    FilterOp
	Field string
	Value string   // For single-value operators
	Values []string // For multi-value operators (in)
}

// SortSpec represents a sort specification.
type SortSpec struct {
	Field      string
	Descending bool
}

// Query represents a BV-BRC query with filters and field selection.
type Query struct {
	// SelectFields is the list of fields to return.
	SelectFields []string

	// Filters is the list of filter conditions.
	Filters []Filter

	// RequiredFields is the list of fields that must have non-empty values.
	RequiredFields []string

	// Keyword is a keyword/phrase to search across all fields.
	Keyword string

	// SortSpecs is the list of sort specifications.
	SortSpecs []SortSpec

	// LimitValue is the maximum number of records to return (0 = unlimited).
	LimitValue int
}

// NewQuery creates a new empty query.
func NewQuery() *Query {
	return &Query{}
}

// Select sets the fields to return.
func (q *Query) Select(fields ...string) *Query {
	q.SelectFields = append(q.SelectFields, fields...)
	return q
}

// Eq adds an equality filter.
func (q *Query) Eq(field, value string) *Query {
	q.Filters = append(q.Filters, Filter{Op: OpEq, Field: field, Value: value})
	return q
}

// Ne adds a not-equal filter.
func (q *Query) Ne(field, value string) *Query {
	q.Filters = append(q.Filters, Filter{Op: OpNe, Field: field, Value: value})
	return q
}

// Lt adds a less-than filter.
func (q *Query) Lt(field, value string) *Query {
	q.Filters = append(q.Filters, Filter{Op: OpLt, Field: field, Value: value})
	return q
}

// Le adds a less-than-or-equal filter.
func (q *Query) Le(field, value string) *Query {
	q.Filters = append(q.Filters, Filter{Op: OpLe, Field: field, Value: value})
	return q
}

// Gt adds a greater-than filter.
func (q *Query) Gt(field, value string) *Query {
	q.Filters = append(q.Filters, Filter{Op: OpGt, Field: field, Value: value})
	return q
}

// Ge adds a greater-than-or-equal filter.
func (q *Query) Ge(field, value string) *Query {
	q.Filters = append(q.Filters, Filter{Op: OpGe, Field: field, Value: value})
	return q
}

// In adds an any-value filter.
func (q *Query) In(field string, values ...string) *Query {
	q.Filters = append(q.Filters, Filter{Op: OpIn, Field: field, Values: values})
	return q
}

// Required adds a field that must have a non-empty value.
func (q *Query) Required(fields ...string) *Query {
	q.RequiredFields = append(q.RequiredFields, fields...)
	return q
}

// WithKeyword sets a keyword/phrase to search across all fields.
func (q *Query) WithKeyword(keyword string) *Query {
	q.Keyword = keyword
	return q
}

// Sort adds a sort specification.
func (q *Query) Sort(field string, descending bool) *Query {
	q.SortSpecs = append(q.SortSpecs, SortSpec{Field: field, Descending: descending})
	return q
}

// Limit sets the maximum number of records to return.
func (q *Query) Limit(n int) *Query {
	q.LimitValue = n
	return q
}

// Build generates the query string for the API.
func (q *Query) Build() string {
	var parts []string

	// Add select clause
	if len(q.SelectFields) > 0 {
		parts = append(parts, fmt.Sprintf("select(%s)", strings.Join(q.SelectFields, ",")))
	}

	// Add filters
	for _, f := range q.Filters {
		var part string
		switch f.Op {
		case OpIn:
			var encodedValues []string
			for _, v := range f.Values {
				encodedValues = append(encodedValues, encodeRQLValue(v))
			}
			part = fmt.Sprintf("in(%s,(%s))", f.Field, strings.Join(encodedValues, ","))
		default:
			part = fmt.Sprintf("%s(%s,%s)", f.Op, f.Field, encodeRQLValue(f.Value))
		}
		parts = append(parts, part)
	}

	// Add required fields
	for _, field := range q.RequiredFields {
		parts = append(parts, fmt.Sprintf("ne(%s,)", field))
	}

	// Add keyword search
	if q.Keyword != "" {
		parts = append(parts, fmt.Sprintf("keyword(%s)", encodeRQLValue(q.Keyword)))
	}

	// Add sort
	if len(q.SortSpecs) > 0 {
		var sortFields []string
		for _, s := range q.SortSpecs {
			prefix := "+"
			if s.Descending {
				prefix = "-"
			}
			sortFields = append(sortFields, prefix+s.Field)
		}
		parts = append(parts, fmt.Sprintf("sort(%s)", strings.Join(sortFields, ",")))
	}

	return strings.Join(parts, "&")
}

// HasFilters returns true if the query has any filter constraints.
func (q *Query) HasFilters() bool {
	return len(q.Filters) > 0 || len(q.RequiredFields) > 0 || q.Keyword != ""
}

// encodeRQLValue encodes a value for use in an RQL query.
// This handles special characters like |, (, ), etc.
func encodeRQLValue(s string) string {
	// URL encode the value, but preserve some characters that are safe
	encoded := url.QueryEscape(s)
	// QueryEscape encodes spaces as +, but RQL expects %20
	encoded = strings.ReplaceAll(encoded, "+", "%20")
	return encoded
}

// Clone creates a copy of the query.
func (q *Query) Clone() *Query {
	newQ := &Query{
		SelectFields:   make([]string, len(q.SelectFields)),
		Filters:        make([]Filter, len(q.Filters)),
		RequiredFields: make([]string, len(q.RequiredFields)),
		Keyword:        q.Keyword,
		SortSpecs:      make([]SortSpec, len(q.SortSpecs)),
		LimitValue:     q.LimitValue,
	}
	copy(newQ.SelectFields, q.SelectFields)
	copy(newQ.Filters, q.Filters)
	copy(newQ.RequiredFields, q.RequiredFields)
	copy(newQ.SortSpecs, q.SortSpecs)
	return newQ
}

// ParseFilterSpec parses a filter specification in the form "field,value".
func ParseFilterSpec(spec string) (field, value string, err error) {
	parts := strings.SplitN(spec, ",", 2)
	if len(parts) != 2 {
		return "", "", fmt.Errorf("invalid filter specification: %q (expected field,value)", spec)
	}
	return parts[0], parts[1], nil
}

// ParseInFilterSpec parses an "in" filter specification in the form "field,value1,value2,...".
func ParseInFilterSpec(spec string) (field string, values []string, err error) {
	parts := strings.Split(spec, ",")
	if len(parts) < 2 {
		return "", nil, fmt.Errorf("invalid in-filter specification: %q (expected field,value1,value2,...)", spec)
	}
	return parts[0], parts[1:], nil
}
