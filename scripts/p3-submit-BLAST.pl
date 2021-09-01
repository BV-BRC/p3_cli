=head1 Submit a BLAST Request

This script submits a request to submit a BLAST job to BV-BRC.  It is a swiss army knife, accepting two sources of query input of
two types and five sources of subject input of four types.

=head1 Usage Synopsis

    p3-submit-BLAST [options] output-path output-name

Start a BLAST job, producing output in the specified workspace path, using the specified name for the base filename
of the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Prefix to be put in front of the output path.  This is optional, and is provided for uniformity with other commands.

=item --workspace-upload-path

Name of workspace directory to which local files should be uplaoded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --in-type

The type of input-- C<dna> or C<aa>.  The default is C<aa>.

=item --db-type

The type of database to search-- C<fna> (contig DNA), C<ffn> (feature DNA), C<frn> (RNA), or C<faa> (protein).  The default is
C<faa>.

=item --evalue-cutoff

Maximum e-value cutoff.  The default is C<1e-5>.

=item --max-hits

The maximum number of hits to return per query.  The default is C<10>.

=item --min-coverage

The minimum percent coverage for an acceptable hit.  The default is C<0>.

=back

The following options specify the input (query) sequences.  Only one may be specified.

=over 4

=item --in-id-list

Comma-delimited list of sequence IDs.  These must be feature IDs.

=item --in-fasta-file

FASTA file of sequences.  If this is a DNA local file, it will be uploaded as C<feature_dna_fasta>.  If it is an amino acid
local file, it will be uploaded as C<feature_protein_fasta>.

=back

The following options specified the subject (database) sequences.  Only one may be specified.

=over 4

=item --db-fasta-file

FASTA file of sequences.  If this is a contig local file, it will be uploaded as C<contigs>.  If it is a feature DNA
local file or an RNA local file, it will be uploaded as C<feature_dna_fasta>.  If it is a protein file, it
will be uploaded as C<feature_protein_fasta>.

=item --db-genome-list

A comma-delimited list of genome IDs.  Alternatively, the name of a local file (tab-delimited with headers) containing a list
of genome IDs in the first column.

=item --db-taxon-list

A comma-delimited list of taxon IDs.

=item --db-database

The name of a pre-computed database-- currently C<RefSeq> (reference and representative genomes), C<BV-BRC> (all prokaryotic genomes),
C<Plasmids> (all plasmids), or C<Phages> all phages.

=back

The following options are provided for user assistance and debugging.

=over 4

=item --help

Display the command-line usage and exit.

=item --dry-run

Display the JSON submission string and exit without invoking the service or uploading files.

=back

=cut

use strict;
use Getopt::Long;
use Bio::KBase::AppService::Client;
use P3AuthToken;
use Data::Dumper;
use Bio::KBase::AppService::CommonSpec;
use Bio::KBase::AppService::GenomeIdSpec;
use Bio::KBase::AppService::UploadSpec;

use constant INPUT_TYPE => { 'dna' => 'n', 'aa' => 'p' };

use constant INPUT_FILE_TYPE => { 'dna' => 'feature_dna_fasta', 'aa' => 'feature_protein_fasta' };

use constant DB_TYPE => { 'fna' => 'n', 'ffn' => 'n', 'frn' => 'n', 'faa' => 'p' };

use constant DB_FILE_TYPE => { 'fna' => 'contigs', 'ffn' => 'feature_dna_fasta', 'frn' => 'feature_dna_fasta',
    'faa' => 'feature_protein_fasta' };

use constant BLAST_PROGRAM => { 'nn' => 'blastn', 'np' => 'blastx', 'pn' => 'tblastn', 'pp' => 'blastp' };

use constant DB_NAME => { 'BV-BRC' => 1, 'REFSEQ' => 1, 'Plasmids' => 1, 'Phages' => 1 };

# Insure we're logged in.
my $p3token = P3AuthToken->new();
if (! $p3token->token()) {
    die "You must be logged into BV-BRC to use this script.";
}
# Get a common-specification processor, an uploader, and a reads-processor.
my $commoner = Bio::KBase::AppService::CommonSpec->new();
my $uploader = Bio::KBase::AppService::UploadSpec->new($p3token);

# Get the application service helper.
my $app_service = Bio::KBase::AppService::Client->new();

# Declare the option variables and their defaults.
my $inputType = "aa";
my $dbType = "faa";
my $blastEvalueCutoff = 1e-5;
my $blastMaxHits = 10;
my $blastMinCoverage = 0;
my $inputIdListIn;
my $inputFastaFileIn;
my $dbFastaFileIn;
my $dbGenomeListIn;
my $dbTaxonListIn;
my $dbPrecomputedDatabaseIn;
# Now we parse the options.
GetOptions($commoner->options(),
        'in-type=s' => \$inputType,
        'evalue-cutoff=f' => \$blastEvalueCutoff,
        'max-hits=i' => \$blastMaxHits,
        'min-coverage=i' => \$blastMinCoverage,
        'in-id-list=s' => \$inputIdListIn,
        'in-fasta-file=s' => \$inputFastaFileIn,
        'db-type=s' => \$dbType,
        'db-fasta-file=s' => \$dbFastaFileIn,
        'db-genome-list=s' => \$dbGenomeListIn,
        'db-taxon-list=s' => \$dbTaxonListIn,
        'db-database=s' => \$dbPrecomputedDatabaseIn,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if ($blastEvalueCutoff < 0) {
    die "E-value cutoff must not be negative.";
}
if ($blastMaxHits <= 0) {
    die "Max-hits must be at least 1.";
}
if ($blastMinCoverage < 0 || $blastMinCoverage > 100) {
    die "Minimum coverage must be between 0 and 100.";
}
my $q = INPUT_TYPE->{$inputType};
my $s = DB_TYPE->{$dbType};
if (! $q) {
    die "Invalid input type.";
}
if (! $s) {
    die "Invalid DB type.";
}
my $blastProg = BLAST_PROGRAM->{"$q$s"};
print "Selected BLAST program is $blastProg.\n";
if ($inputIdListIn && $inputFastaFileIn) {
    die "Only one type of query input can be specified.";
}
my $dbCount = scalar grep { $_ } ($dbFastaFileIn, $dbGenomeListIn, $dbTaxonListIn, $dbPrecomputedDatabaseIn);
if ($dbCount > 1) {
    die "Only one type of subject database can be specified.";
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    input_type => $inputType,
    db_type => $dbType,
    blast_program => $blastProg,
    blast_evalue_cutoff => $blastEvalueCutoff,
    blast_max_hits => $blastMaxHits,
    blast_min_coverage => $blastMinCoverage,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Process the input sources.
if ($inputFastaFileIn) {
    $params->{input_fasta_file} = $uploader->fix_file_name($inputFastaFileIn, INPUT_FILE_TYPE->{$inputType});
    $params->{input_source} = 'fasta_file';
} elsif ($inputIdListIn) {
    $params->{input_id_list} = [split /,/, $inputIdListIn];
    $params->{input_source} = 'id_list';
} else {
    die "No input query specified."
}
# Process the database sources.
if ($dbFastaFileIn) {
    $params->{db_fasta_file} = $uploader->fix_file_name($dbFastaFileIn, DB_FILE_TYPE->{$dbType});
    $params->{db_source} = 'fasta_file';
} elsif ($dbGenomeListIn) {
    my $idList = Bio::KBase::AppService::GenomeIdSpec::validate_genomes($dbGenomeListIn);
    if (! $idList) {
        die "Invalid genome ID list specified.";
    } else {
        $params->{db_genome_list} = $idList;
        $params->{db_source} = 'genome_list';
    }
} elsif ($dbTaxonListIn) {
    $params->{db_taxon_list} = [split /,/, $dbTaxonListIn];
    $params->{db_source} = 'taxon_list';
} elsif ($dbPrecomputedDatabaseIn) {
    if (! DB_NAME->{$dbPrecomputedDatabaseIn}) {
        die "Invalid precomputed database name.";
    } else {
        $params->{db_precomputed_database} = $dbPrecomputedDatabaseIn;
        $params->{db_source} = 'precomputed_database';
    }
}
# Submit the job.
$commoner->submit($app_service, $uploader, $params, Homology => 'BLAST');
