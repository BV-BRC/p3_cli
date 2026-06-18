// Package types defines the primary data structures for BV-BRC entities.
//
// These types provide strongly-typed access to BV-BRC data, with JSON tags
// matching the API field names for easy unmarshalling.
package types

// Genome represents a BV-BRC genome record.
type Genome struct {
	GenomeID       string  `json:"genome_id"`
	GenomeName     string  `json:"genome_name"`
	GenomeStatus   string  `json:"genome_status"`
	GenomeLength   int     `json:"genome_length"`
	GCContent      float64 `json:"gc_content"`
	Contigs        int     `json:"contigs"`
	Sequences      int     `json:"sequences"`
	PatricCDS      int     `json:"patric_cds"`
	RefSeqCDS      int     `json:"refseq_cds"`
	TaxonID        int     `json:"taxon_id"`
	Kingdom        string  `json:"kingdom"`
	Phylum         string  `json:"phylum"`
	Class          string  `json:"class"`
	Order          string  `json:"order"`
	Family         string  `json:"family"`
	Genus          string  `json:"genus"`
	Species        string  `json:"species"`
	Strain         string  `json:"strain"`
	IsolationCountry string `json:"isolation_country"`
	HostName       string  `json:"host_name"`
	Disease        string  `json:"disease"`
	CollectionDate string  `json:"collection_date"`
	CollectionYear int     `json:"collection_year"`
	CompletionDate string  `json:"completion_date"`
	SequencingCenter string `json:"sequencing_center"`
	PublicationID  string  `json:"publication"`
	BioProjectAccession string `json:"bioproject_accession"`
	BioSampleAccession  string `json:"biosample_accession"`
	AssemblyAccession   string `json:"assembly_accession"`
	GenBankAccessions   string `json:"genbank_accessions"`
	RefSeqAccessions    string `json:"refseq_accessions"`
	OwnedBy        string  `json:"owner"`
	Public         bool    `json:"public"`
}

// Feature represents a BV-BRC genome feature (gene, CDS, etc.).
type Feature struct {
	PatricID       string  `json:"patric_id"`
	FeatureID      string  `json:"feature_id"`
	GenomeID       string  `json:"genome_id"`
	GenomeName     string  `json:"genome_name"`
	Accession      string  `json:"accession"`
	SequenceID     string  `json:"sequence_id"`
	Annotation     string  `json:"annotation"`
	FeatureType    string  `json:"feature_type"`
	Start          int     `json:"start"`
	End            int     `json:"end"`
	Strand         string  `json:"strand"`
	NaLength       int     `json:"na_length"`
	AaLength       int     `json:"aa_length"`
	Gene           string  `json:"gene"`
	Product        string  `json:"product"`
	RefSeqLocusTag string  `json:"refseq_locus_tag"`
	AltLocusTag    string  `json:"alt_locus_tag"`
	GeneID         int     `json:"gene_id"`
	GI             int     `json:"gi"`
	PLFamID        string  `json:"plfam_id"`
	PGFamID        string  `json:"pgfam_id"`
	FIGFamID       string  `json:"figfam_id"`
	ProteinID      string  `json:"protein_id"`
	AASequenceMD5  string  `json:"aa_sequence_md5"`
	NASequenceMD5  string  `json:"na_sequence_md5"`
	TaxonID        int     `json:"taxon_id"`
	Public         bool    `json:"public"`
}

// Contig represents a genome sequence/contig.
type Contig struct {
	SequenceID   string  `json:"sequence_id"`
	GenomeID     string  `json:"genome_id"`
	GenomeName   string  `json:"genome_name"`
	Accession    string  `json:"accession"`
	Description  string  `json:"description"`
	Length       int     `json:"length"`
	GCContent    float64 `json:"gc_content"`
	SequenceType string  `json:"sequence_type"`
	Topology     string  `json:"topology"`
	Chromosome   string  `json:"chromosome"`
	Plasmid      string  `json:"plasmid"`
	Sequence     string  `json:"sequence"`
	TaxonID      int     `json:"taxon_id"`
	Public       bool    `json:"public"`
}

// Subsystem represents a functional subsystem.
type Subsystem struct {
	SubsystemID   string `json:"subsystem_id"`
	SubsystemName string `json:"subsystem_name"`
	Superclass    string `json:"superclass"`
	Class         string `json:"class"`
	Subclass      string `json:"subclass"`
	RoleID        string `json:"role_id"`
	RoleName      string `json:"role_name"`
	Active        bool   `json:"active"`
}

// SubsystemItem represents a feature's participation in a subsystem.
type SubsystemItem struct {
	ID            string `json:"id"`
	SubsystemName string `json:"subsystem_name"`
	Superclass    string `json:"superclass"`
	Class         string `json:"class"`
	Subclass      string `json:"subclass"`
	RoleName      string `json:"role_name"`
	Active        bool   `json:"active"`
	PatricID      string `json:"patric_id"`
	Gene          string `json:"gene"`
	Product       string `json:"product"`
	GenomeID      string `json:"genome_id"`
	GenomeName    string `json:"genome_name"`
	TaxonID       int    `json:"taxon_id"`
}

// Taxonomy represents a taxonomic classification.
type Taxonomy struct {
	TaxonID        int      `json:"taxon_id"`
	TaxonName      string   `json:"taxon_name"`
	TaxonRank      string   `json:"taxon_rank"`
	GeneticCode    int      `json:"genetic_code"`
	ParentID       int      `json:"parent_id"`
	Division       string   `json:"division"`
	LineageIDs     []int    `json:"taxon_lineage_ids"`
	LineageNames   []string `json:"taxon_lineage_names"`
	LineageRanks   []string `json:"taxon_lineage_ranks"`
	GenomeCount    int      `json:"genome_count"`
	GenomeLengthMean float64 `json:"genome_length_mean"`
}

// ProteinFamily represents a protein family reference.
type ProteinFamily struct {
	FamilyID      string `json:"family_id"`
	FamilyType    string `json:"family_type"`
	FamilyProduct string `json:"family_product"`
}

// GenomeDrug represents genome AMR (antimicrobial resistance) data.
type GenomeDrug struct {
	ID                 string `json:"id"`
	GenomeID           string `json:"genome_id"`
	GenomeName         string `json:"genome_name"`
	TaxonID            int    `json:"taxon_id"`
	Antibiotic         string `json:"antibiotic"`
	ResistantPhenotype string `json:"resistant_phenotype"`
	Measurement        string `json:"measurement"`
	MeasurementSign    string `json:"measurement_sign"`
	MeasurementValue   string `json:"measurement_value"`
	MeasurementUnit    string `json:"measurement_unit"`
	LaboratoryTyping   string `json:"laboratory_typing"`
	Source             string `json:"source"`
	PMID               string `json:"pmid"`
}

// Drug represents an antibiotic/drug.
type Drug struct {
	CasID             string   `json:"cas_id"`
	AntibioticName    string   `json:"antibiotic_name"`
	CanonicalSMILES   string   `json:"canonical_smiles"`
	InChIKey          string   `json:"inchi_key"`
	MolecularFormula  string   `json:"molecular_formula"`
	MolecularWeight   float64  `json:"molecular_weight"`
	DrugbankID        string   `json:"drugbank_id"`
	PubChemCID        int      `json:"pubchem_cid"`
	AntibioticClass   []string `json:"antibiotic_class"`
}

// Experiment represents a transcriptomics experiment.
type Experiment struct {
	EID          string `json:"eid"`
	Title        string `json:"title"`
	Description  string `json:"description"`
	Organism     string `json:"organism"`
	Strain       string `json:"strain"`
	Mutant       string `json:"mutant"`
	Timeseries   string `json:"timeseries"`
	Genes        int    `json:"genes"`
	Samples      int    `json:"samples"`
	PMID         string `json:"pmid"`
	ReleaseDate  string `json:"release_date"`
	GenomeID     string `json:"genome_id"`
	TaxonID      int    `json:"taxon_id"`
}

// ExpressionSample represents a transcriptomics sample.
type ExpressionSample struct {
	ExpID        string `json:"expid"`
	EID          string `json:"eid"`
	Organism     string `json:"organism"`
	Strain       string `json:"strain"`
	Mutant       string `json:"mutant"`
	Condition    string `json:"condition"`
	Timepoint    string `json:"timepoint"`
	Genes        int    `json:"genes"`
	SigLogRatio  int    `json:"sig_log_ratio"`
	SigZScore    int    `json:"sig_z_score"`
	PMID         string `json:"pmid"`
	ReleaseDate  string `json:"release_date"`
	GenomeID     string `json:"genome_id"`
	TaxonID      int    `json:"taxon_id"`
}

// GeneExpression represents gene expression data.
type GeneExpression struct {
	ID            string  `json:"id"`
	EID           string  `json:"eid"`
	ExpID         string  `json:"expid"`
	GenomeID      string  `json:"genome_id"`
	PatricID      string  `json:"patric_id"`
	RefSeqLocusTag string `json:"refseq_locus_tag"`
	AltLocusTag   string  `json:"alt_locus_tag"`
	LogRatio      float64 `json:"log_ratio"`
	ZScore        float64 `json:"z_score"`
}

// SpecialtyGene represents a specialty gene (virulence, AMR, etc.).
type SpecialtyGene struct {
	ID             string  `json:"id"`
	PatricID       string  `json:"patric_id"`
	RefSeqLocusTag string  `json:"refseq_locus_tag"`
	Gene           string  `json:"gene"`
	Product        string  `json:"product"`
	Property       string  `json:"property"`
	Source         string  `json:"source"`
	SourceID       string  `json:"source_id"`
	Evidence       string  `json:"evidence"`
	PMID           string  `json:"pmid"`
	Identity       float64 `json:"identity"`
	EValue         float64 `json:"e_value"`
	GenomeID       string  `json:"genome_id"`
	GenomeName     string  `json:"genome_name"`
	TaxonID        int     `json:"taxon_id"`
}

// ProteinRegion represents a protein domain or feature.
type ProteinRegion struct {
	ID             string  `json:"id"`
	PatricID       string  `json:"patric_id"`
	RefSeqLocusTag string  `json:"refseq_locus_tag"`
	Gene           string  `json:"gene"`
	Product        string  `json:"product"`
	Source         string  `json:"source"`
	SourceID       string  `json:"source_id"`
	Description    string  `json:"description"`
	Evidence       string  `json:"evidence"`
	EValue         float64 `json:"e_value"`
	Score          float64 `json:"score"`
	Start          int     `json:"start"`
	End            int     `json:"end"`
	Segments       string  `json:"segments"`
	GenomeID       string  `json:"genome_id"`
	GenomeName     string  `json:"genome_name"`
	TaxonID        int     `json:"taxon_id"`
}

// ProteinStructure represents a protein structure from PDB.
type ProteinStructure struct {
	PDBID             string `json:"pdb_id"`
	Title             string `json:"title"`
	OrganismName      string `json:"organism_name"`
	PatricID          string `json:"patric_id"`
	UniProtKBAccession string `json:"uniprotkb_accession"`
	Gene              string `json:"gene"`
	Product           string `json:"product"`
	Method            string `json:"method"`
	Resolution        string `json:"resolution"`
	ReleaseDate       string `json:"release_date"`
	GenomeID          string `json:"genome_id"`
	TaxonID           int    `json:"taxon_id"`
}

// Surveillance represents disease surveillance data.
type Surveillance struct {
	SampleIdentifier     string `json:"sample_identifier"`
	SampleMaterial       string `json:"sample_material"`
	CollectorInstitution string `json:"collector_institution"`
	CollectionDate       string `json:"collection_date"`
	CollectionYear       int    `json:"collection_year"`
	CollectionCountry    string `json:"collection_country"`
	Region               string `json:"region"`
	PathogenTestType     string `json:"pathogen_test_type"`
	PathogenTestResult   string `json:"pathogen_test_result"`
	Subtype              string `json:"subtype"`
	Strain               string `json:"strain"`
	HostIdentifier       string `json:"host_identifier"`
	HostSpecies          string `json:"host_species"`
	HostCommonName       string `json:"host_common_name"`
	HostAge              string `json:"host_age"`
	HostSex              string `json:"host_sex"`
	HostHealth           string `json:"host_health"`
}

// Serology represents serology testing data.
type Serology struct {
	SampleIdentifier string `json:"sample_identifier"`
	HostIdentifier   string `json:"host_identifier"`
	HostType         string `json:"host_type"`
	HostSpecies      string `json:"host_species"`
	HostCommonName   string `json:"host_common_name"`
	HostSex          string `json:"host_sex"`
	HostAge          string `json:"host_age"`
	HostAgeGroup     string `json:"host_age_group"`
	HostHealth       string `json:"host_health"`
	CollectionDate   string `json:"collection_date"`
	TestType         string `json:"test_type"`
	TestResult       string `json:"test_result"`
	Serotype         string `json:"serotype"`
}

// FeatureSequence represents a feature sequence (protein or nucleotide).
type FeatureSequence struct {
	MD5          string `json:"md5"`
	SequenceType string `json:"sequence_type"`
	Sequence     string `json:"sequence"`
}
