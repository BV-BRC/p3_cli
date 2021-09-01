=head1 SARS-COV-2 Genome Assembly and Annotation

This script submits a SARS-COV-2 Assembly and Annotation job to BV-BRC.  It takes input from read libraries and uses
VIGOR to annotate the assembled contigs.

=head1 Usage Synopsis

    p3-submit-sars2-assembly [options] output-path output-name

Start a SARS-COV-2 assembly and annotation run, producing output in the specified workspace path, using the specified
folder for the output files.

=head2 Command-Line Options

The following options are used to assist in the specification of files.  Files specified in the options that are in the workspace
should have a C<>ws:> prefix.  All others are assumed to be local.

=over 4

=item --workspace-path-prefix

Base workspace directory for relative workspace paths.

=item --workspace-upload-path

Name of workspace directory to which local files should be uplaoded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=back

The following options specify the reads to be classified.

=over 4

=item --paired-end-lib

Two paired-end libraries containing reads.  These are coded with a single invocation, e.g. C<--paired-end-lib left.fa right.fa>.  The
libraries must be paired FASTQ files.  A prefix of C<ws:> indicates a file is in the BV-BRC workspace; otherwise they are uploaded
from the local file system.  This parameter may be specified multiple times.

=item --interleaved-lib

A single library of paired-end reads in interleaved format.  This must be a FASTQ file with paired reads mixed together, the forward read
always preceding the reverse read.  A prefix of C<ws:> indicates a file is in the BV-BRC workspace; otherwise they are uploaded
from the local file system.  This parameter may be specified multiple times.

=item --single-end-lib

A library of single reads.  This must be a FASTQ file.  A prefix of C<ws:> indicates a file is in the BV-BRC workspace; otherwise they are
uploaded from the local file system.  This parameter may be specified multiple times.

=item --srr-id

A run ID from the NCBI sequence read archive.  The run will be downloaded from the NCBI for processing.  This parameter may be specified
multiple times.

=back

These options modify the way reads are processed during assembly, so they should precede any library specifications to which they apply.
For example,

    --platform illumina --paired-end-lib S1.fq S2.fq --platform pacbio --single-end-lib ERR12345.fq  --srr-id SRR54321

means that the local files C<S1.fq> and C<S2.fq> are from the illumina platform, but the single-end library C<ERR12345.fq> comes
from the pacbio platform.  These options B<only> apply to FASTQ libraries, and not to libraries accessed via na NBCI ID.  Thus
C<SRR54321> above will use the default mode of having its platform inferred from the data.

=over 4

=item --platform

The sequencing platform for the subsequent read library or libraries.  Valid values are C<infer>, C<illumina>, C<pacbio>, or <nanopore>.
The default is C<infer>.

=item --insert-size-mean

The average size of an insert in all subsequent read libraries, used for optimization.

=item --insert-size-stdev

The standard deviation of the insert sizes in all subsequent read libraries, used for optimization.

=item --read-orientation-inward

Indicates that all subsequent read libraries have the standard read orientation, with the paired ends facing inward.  This is the default.

=item --read-orientation-outward

Indicates that all subseqyent read libraries have reverse read orientation, with the paired ends facing outward.

=back

The following options modify the annotation process.

=over 4

=item --recipe

The assembly strategy to use-- C<auto>, C<onecodex>, C<cdc-illumina>, C<cdc-nanopore>, or C<artic-nanopore>.  The
default is C<auto>.

=item --taxonomy-name

The taxonomic name to use-- the default is computed from the taxonomy ID.

=item --taxonomy-id

The taxonomic ID to use-- the default is C<2697049>.

=item --label

The user label to suffix to the taxonomy name to form the organism scientific name.  The default is none.

=back

These options are provided for user assistance and debugging.

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
use Bio::KBase::AppService::ReadSpec;
use Bio::KBase::AppService::UploadSpec;
use Bio::KBase::AppService::GenomeIdSpec;

use constant RECIPES => { auto => 1, onecodex => 1, 'cdc-illumina' => 1, 'cdc-nanopore' => 1, 'artic-nanopore' => 1 };

# Insure we're logged in.
my $p3token = P3AuthToken->new();
if (! $p3token->token()) {
    die "You must be logged into BV-BRC to use this script.";
}
# Get a common-specification processor, an uploader, and a reads-processor.
my $commoner = Bio::KBase::AppService::CommonSpec->new();
my $uploader = Bio::KBase::AppService::UploadSpec->new($p3token);
my $reader = Bio::KBase::AppService::ReadSpec->new($uploader, assembling => 1);

# Get the application service helper.
my $app_service = Bio::KBase::AppService::Client->new();

# Declare the option variables and their defaults.
my $taxonomyId = 2697049;
my $taxonomyName;
my $recipe = 'auto';
my $label;
# Now we parse the options.
GetOptions($commoner->options(), $reader->lib_options(),
        'taxonomy-id=i' => \$taxonomyId,
        'taxonomy-name=s' => \$taxonomyName,
        'recipe=s' => \$recipe,
        'label=s' => \$label
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
# Insure we have reads.
if (! $reader->check_for_reads()) {
    die "Must specify some type of FASTQ input.";
}
# Validate the recipe.
if (! RECIPES->{$recipe}) {
    die "Invalid recipe specified."
}
# Compute the scientific name.
my $scientificName = Bio::KBase::AppService::GenomeIdSpec::process_taxid($taxonomyId, $taxonomyName);
if ($label) {
    $scientificName .= ' ' . $label;
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    domain => 'Viruses',
    input_type => 'reads',
    recipe => $recipe,
    keep_intermediates => 0,
    code => 1,
    taxonomy_id => $taxonomyId,
    scientific_name => $scientificName,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Store the read libraries.
$reader->store_libs($params);
# Submit the job.
$commoner->submit($app_service, $uploader, $params, ComprehensiveSARS2Analysis => 'SARS-COV-2 assembly');
