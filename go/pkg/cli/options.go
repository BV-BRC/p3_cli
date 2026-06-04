// Package cli provides utilities for building BV-BRC command-line tools.
//
// This package provides standardized option handling, tab-delimited I/O,
// and batch processing utilities that mirror the patterns in the Perl P3Utils module.
package cli

import (
	"github.com/BV-BRC/bvbrc/pkg/api"
	"github.com/spf13/cobra"
)

// DataOptions contains the standard data query options.
type DataOptions struct {
	// Attr specifies field names to return (can be repeated)
	Attr []string

	// Count if true, returns count instead of records
	Count bool

	// Fields if true, lists available field names and exits
	Fields bool

	// Equal contains equality constraints in "field,value" format
	Equal []string

	// Lt contains less-than constraints in "field,value" format
	Lt []string

	// Le contains less-or-equal constraints in "field,value" format
	Le []string

	// Gt contains greater-than constraints in "field,value" format
	Gt []string

	// Ge contains greater-or-equal constraints in "field,value" format
	Ge []string

	// Ne contains not-equal constraints in "field,value" format
	Ne []string

	// In contains any-value constraints in "field,value1,value2,..." format
	In []string

	// Required specifies fields that must have values
	Required []string

	// Keyword is a search phrase
	Keyword string

	// Limit is maximum records to return (0 = unlimited)
	Limit int

	// Debug enables debug output
	Debug bool
}

// AddDataFlags adds the standard data query flags to a cobra command.
func AddDataFlags(cmd *cobra.Command, opts *DataOptions) {
	flags := cmd.Flags()

	flags.StringSliceVarP(&opts.Attr, "attr", "a", nil,
		"field(s) to return (can be repeated or comma-separated)")
	flags.BoolVarP(&opts.Count, "count", "K", false,
		"return count of records instead of the records themselves")
	flags.BoolVar(&opts.Fields, "fields", false,
		"list available field names")
	// Use StringArrayVarP for filters - these contain commas in their values
	flags.StringArrayVarP(&opts.Equal, "eq", "e", nil,
		"equality constraint in field,value format (can be repeated)")
	flags.StringArrayVar(&opts.Lt, "lt", nil,
		"less-than constraint in field,value format")
	flags.StringArrayVar(&opts.Le, "le", nil,
		"less-or-equal constraint in field,value format")
	flags.StringArrayVar(&opts.Gt, "gt", nil,
		"greater-than constraint in field,value format")
	flags.StringArrayVar(&opts.Ge, "ge", nil,
		"greater-or-equal constraint in field,value format")
	flags.StringArrayVar(&opts.Ne, "ne", nil,
		"not-equal constraint in field,value format")
	flags.StringArrayVar(&opts.In, "in", nil,
		"any-value constraint in field,value1,value2,... format")
	flags.StringSliceVarP(&opts.Required, "required", "r", nil,
		"field(s) that must have values")
	flags.StringVar(&opts.Keyword, "keyword", "",
		"keyword or phrase to search in all fields")
	flags.IntVar(&opts.Limit, "limit", 0,
		"maximum number of records to return")
	flags.BoolVar(&opts.Debug, "debug", false,
		"enable debug output")

	// Add the equal alias
	flags.StringArrayVar(&opts.Equal, "equal", nil, "")
	_ = flags.MarkHidden("equal")
}

// BuildQuery creates an API query from the data options.
func (d *DataOptions) BuildQuery(defaultFields []string) (*api.Query, error) {
	q := api.NewQuery()

	// Add field selection
	if len(d.Attr) > 0 {
		q.Select(d.Attr...)
	} else if len(defaultFields) > 0 {
		q.Select(defaultFields...)
	}

	// Add equality filters
	for _, spec := range d.Equal {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Eq(field, value)
	}

	// Add less-than filters
	for _, spec := range d.Lt {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Lt(field, value)
	}

	// Add less-or-equal filters
	for _, spec := range d.Le {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Le(field, value)
	}

	// Add greater-than filters
	for _, spec := range d.Gt {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Gt(field, value)
	}

	// Add greater-or-equal filters
	for _, spec := range d.Ge {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Ge(field, value)
	}

	// Add not-equal filters
	for _, spec := range d.Ne {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Ne(field, value)
	}

	// Add in-filters
	for _, spec := range d.In {
		field, values, err := api.ParseInFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.In(field, values...)
	}

	// Add required fields
	if len(d.Required) > 0 {
		q.Required(d.Required...)
	}

	// Add keyword
	if d.Keyword != "" {
		q.WithKeyword(d.Keyword)
	}

	// Add limit
	if d.Limit > 0 {
		q.Limit(d.Limit)
	}

	return q, nil
}

// BuildQueryWithFields creates an API query from the data options with explicit fields.
// This is used when the caller needs to control which fields are selected.
func (d *DataOptions) BuildQueryWithFields(selectFields []string) (*api.Query, error) {
	q := api.NewQuery()

	// Add field selection from explicit fields
	if len(selectFields) > 0 {
		q.Select(selectFields...)
	}

	// Add equality filters
	for _, spec := range d.Equal {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Eq(field, value)
	}

	// Add less-than filters
	for _, spec := range d.Lt {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Lt(field, value)
	}

	// Add less-or-equal filters
	for _, spec := range d.Le {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Le(field, value)
	}

	// Add greater-than filters
	for _, spec := range d.Gt {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Gt(field, value)
	}

	// Add greater-or-equal filters
	for _, spec := range d.Ge {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Ge(field, value)
	}

	// Add not-equal filters
	for _, spec := range d.Ne {
		field, value, err := api.ParseFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.Ne(field, value)
	}

	// Add in-filters
	for _, spec := range d.In {
		field, values, err := api.ParseInFilterSpec(spec)
		if err != nil {
			return nil, err
		}
		q.In(field, values...)
	}

	// Add required fields
	if len(d.Required) > 0 {
		q.Required(d.Required...)
	}

	// Add keyword
	if d.Keyword != "" {
		q.WithKeyword(d.Keyword)
	}

	// Add limit
	if d.Limit > 0 {
		q.Limit(d.Limit)
	}

	return q, nil
}

// GetSelectFields returns the fields to select, using defaults if none specified.
func (d *DataOptions) GetSelectFields(defaultFields []string) []string {
	if len(d.Attr) > 0 {
		return d.Attr
	}
	return defaultFields
}

// ColOptions contains column selection options for input processing.
type ColOptions struct {
	// Col is the key column (1-based index or header name, 0 = last column)
	Col string

	// BatchSize is the number of rows to process at a time
	BatchSize int

	// NoHead indicates the input has no header row
	NoHead bool
}

// AddColFlags adds the column selection flags to a cobra command.
func AddColFlags(cmd *cobra.Command, opts *ColOptions, defaultBatchSize int) {
	if defaultBatchSize <= 0 {
		defaultBatchSize = 100
	}

	flags := cmd.Flags()

	flags.StringVarP(&opts.Col, "col", "c", "0",
		"key column (1-based index or header name, 0 = last)")
	flags.IntVarP(&opts.BatchSize, "batchSize", "b", defaultBatchSize,
		"number of rows to process at a time")
	flags.BoolVar(&opts.NoHead, "nohead", false,
		"input file has no header row")
}

// IOOptions contains input/output options.
type IOOptions struct {
	// Input is the input file path (empty = stdin)
	Input string

	// Output is the output file path (empty = stdout)
	Output string

	// Delim is the delimiter for multi-valued fields
	Delim string
}

// AddIOFlags adds the I/O flags to a cobra command.
func AddIOFlags(cmd *cobra.Command, opts *IOOptions) {
	flags := cmd.Flags()

	flags.StringVarP(&opts.Input, "input", "i", "",
		"input file (default: stdin)")
	flags.StringVarP(&opts.Output, "output", "o", "",
		"output file (default: stdout)")
	flags.StringVar(&opts.Delim, "delim", "::",
		"delimiter for multi-valued fields (::, tab, space, semi, comma)")
}

// GetDelimiter returns the actual delimiter string.
func (o *IOOptions) GetDelimiter() string {
	switch o.Delim {
	case "tab":
		return "\t"
	case "space":
		return " "
	case "semi":
		return "; "
	case "comma":
		return ","
	default:
		return o.Delim
	}
}
