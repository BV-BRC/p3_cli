package api

// Objects maps user-friendly object names to PATRIC internal object names.
var Objects = map[string]string{
	"genome":           "genome",
	"feature":          "genome_feature",
	"family":           "protein_family_ref",
	"genome_drug":      "genome_amr",
	"contig":           "genome_sequence",
	"drug":             "antibiotics",
	"taxonomy":         "taxonomy",
	"experiment":       "transcriptomics_experiment",
	"expression":       "transcriptomics_gene",
	"sample":           "transcriptomics_sample",
	"sequence":         "feature_sequence",
	"subsystem":        "subsystem_ref",
	"subsystemItem":    "subsystem",
	"alt_feature":      "genome_feature",
	"sp_gene":          "sp_gene",
	"protein_region":   "protein_feature",
	"protein_structure": "protein_structure",
	"surveillance":     "surveillance",
	"serology":         "serology",
	"sf":               "sequence_feature",
	"sfvt":             "sequence_feature_vt",
}

// DefaultFields maps object types to their default field lists.
var DefaultFields = map[string][]string{
	"genome": {
		"genome_name", "genome_id", "genome_status", "sequences",
		"patric_cds", "isolation_country", "host_name", "disease",
		"collection_year", "completion_date",
	},
	"feature": {
		"patric_id", "refseq_locus_tag", "gene_id",
		"plfam_id", "pgfam_id", "product",
	},
	"alt_feature": {
		"feature_id", "refseq_locus_tag", "gene_id", "product",
	},
	"family": {
		"family_id", "family_type", "family_product",
	},
	"genome_drug": {
		"genome_id", "antibiotic", "resistant_phenotype",
	},
	"contig": {
		"genome_id", "accession", "length", "gc_content",
		"sequence_type", "topology",
	},
	"drug": {
		"cas_id", "antibiotic_name", "canonical_smiles",
	},
	"experiment": {
		"eid", "title", "genes", "pmid", "organism",
		"strain", "mutant", "timeseries", "release_date",
	},
	"sample": {
		"eid", "expid", "genes", "sig_log_ratio", "sig_z_score",
		"pmid", "organism", "strain", "mutant", "condition",
		"timepoint", "release_date",
	},
	"expression": {
		"id", "eid", "genome_id", "patric_id", "refseq_locus_tag",
		"alt_locus_tag", "log_ratio", "z_score",
	},
	"taxonomy": {
		"taxon_id", "taxon_name", "taxon_rank",
		"genome_count", "genome_length_mean",
	},
	"sequence": {
		"md5", "sequence_type", "sequence",
	},
	"sp_gene": {
		"evidence", "property", "patric_id", "refseq_locus_tag",
		"source_id", "gene", "product", "pmid", "identity", "e_value",
	},
	"subsystem": {
		"subsystem_id", "subsystem_name", "superclass", "class", "subclass",
	},
	"subsystemItem": {
		"id", "subsystem_name", "superclass", "class", "subclass",
		"subsystem_name", "role_name", "active", "patric_id", "gene", "product",
	},
	"protein_region": {
		"patric_id", "refseq_locus_tag", "gene", "product",
		"source", "source_id", "description", "e_value", "evidence",
	},
	"protein_structure": {
		"pdb_id", "title", "organism_name", "patric_id",
		"uniprotkb_accession", "gene", "product", "method", "release_date",
	},
	"surveillance": {
		"sample_identifier", "sample_material", "collector_institution",
		"collection_year", "collection_country", "pathogen_test_type",
		"pathogen_test_result", "type", "subtype", "strain",
		"host_identifier", "host_species", "host_common_name",
		"host_age", "host_health",
	},
	"serology": {
		"sample_identifier", "host_identifier", "host_type", "host_species",
		"host_common_name", "host_sex", "host_age", "host_age_group",
		"host_health", "collection_date", "test_type", "test_result", "serotype",
	},
	"sf": {
		"sf_id", "sf_name", "sf_category", "gene",
		"length", "sf_category", "start", "end", "source_strain",
	},
	"sfvt": {
		"sf_id", "sf_name", "sf_category",
		"sfvt_id", "sfvt_genome_count", "sfvt_sequence",
	},
}

// IDColumns maps object types to their primary ID column.
var IDColumns = map[string]string{
	"genome":           "genome_id",
	"feature":          "patric_id",
	"alt_feature":      "feature_id",
	"family":           "family_id",
	"genome_drug":      "id",
	"contig":           "sequence_id",
	"drug":             "antibiotic_name",
	"experiment":       "eid",
	"sample":           "expid",
	"expression":       "id",
	"taxonomy":         "taxon_id",
	"sequence":         "md5",
	"sp_gene":          "patric_id",
	"subsystem":        "subsystem_id",
	"subsystemItem":    "id",
	"protein_region":   "id",
	"protein_structure": "pdb_id",
	"surveillance":     "sample_identifier",
	"serology":         "sample_identifier",
	"sf":               "sf_id",
	"sfvt":             "id",
}

// FamilyFieldOfType maps family types to their ID field names.
var FamilyFieldOfType = map[string]string{
	"plfam":  "plfam_id",
	"pgfam":  "pgfam_id",
	"figfam": "figfam_id",
	"fig":    "figfam_id",
}

// FeatureTypeMap maps BV-BRC feature types to common names.
var FeatureTypeMap = map[string]string{
	"CDS": "peg",
}

// DerivedFields defines fields that are computed from other fields.
// Each entry maps field name to a list: [function, source_fields...]
var DerivedFields = map[string]map[string][]string{
	"genome": {
		"taxonomy": {"concatSemi", "taxon_lineage_names"},
	},
	"feature": {
		"function": {"altName", "product"},
		"ec":       {"ecParse", "product"},
	},
	"alt_feature": {
		"function": {"altName", "product"},
		"ec":       {"ecParse", "product"},
	},
	"contig": {
		"md5": {"md5", "sequence"},
	},
}

// DerivedMulti indicates which derived fields can have multiple values.
var DerivedMulti = map[string]map[string]bool{
	"feature": {
		"ec":        true,
		"subsystem": true,
		"pathway":   true,
	},
	"alt_feature": {
		"ec":        true,
		"subsystem": true,
		"pathway":   true,
	},
}

// RelatedFields defines fields that come from related records.
// Each entry is: [source_key_field, target_table, target_key_field, target_value_field]
var RelatedFields = map[string]map[string][]string{
	"feature": {
		"na_sequence": {"na_sequence_md5", "feature_sequence", "md5", "sequence"},
		"aa_sequence": {"aa_sequence_md5", "feature_sequence", "md5", "sequence"},
		"pathway":     {"patric_id", "pathway", "patric_id", "pathway_name"},
		"subsystem":   {"patric_id", "subsystem", "patric_id", "subsystem_name"},
	},
	"alt_feature": {
		"na_sequence": {"na_sequence_md5", "feature_sequence", "md5", "sequence"},
		"aa_sequence": {"aa_sequence_md5", "feature_sequence", "md5", "sequence"},
		"pathway":     {"patric_id", "pathway", "patric_id", "pathway_name"},
		"subsystem":   {"patric_id", "subsystem", "patric_id", "subsystem_name"},
	},
	"genome": {
		"genetic_code": {"taxon_id", "taxonomy", "taxon_id", "genetic_code"},
	},
	"protein": {
		"aa_sequence": {"aa_sequence_md5", "feature_sequence", "md5", "sequence"},
	},
}
