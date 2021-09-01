=head1 Submit a Metagenome Binning Job

This script submits a Metagenome Binning job to BV-BRC.  It allows input from either read libraries or a FASTA file and
organizes contigs into individual genomes.

=head1 Usage Synopsis

    p3-submit-metagenome-binning [options] output-path output-name

Start metagenome binning, producing output in the specified workspace path, using the specified name for the output folder.

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

The following options specify the reads to be binned.  These are assembled internally.

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

If contigs are being binned, specify the following parameter.  All the above parameters relating to reads should not be used
if contigs are specified.

=over 4

=item --contigs

Input FASTA file of assembled contigs.  (If specified, all options relating to assembly will be ignored.  This is mutually exclusive with
C<--paired-end-libs>, C<--single-end-libs>, C<srr-ids>, and C<interleaved-libs>)

=back

The following options modify the binning process.

=over 4

=item --genome-group

Group name to be assigned to the output genomes (optional).

=item --skip-indexing

If specified, the genomes created will NOT be added to the BV-BRC database.

=back

These options are provided for user assistance and debugging.

=over 4

=item --recipe

Name of a non-standard annotation recipe to use.

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

# Insure we're logged in.
my $p3token = P3AuthToken->new();
if (! $p3token->token()) {
    die "You must be logged into BV-BRC to use this script.";
}
# Get a common-specification processor, an uploader, and a reads-processor.
my $commoner = Bio::KBase::AppService::CommonSpec->new();
my $uploader = Bio::KBase::AppService::UploadSpec->new($p3token);
my $reader = Bio::KBase::AppService::ReadSpec->new($uploader);

# Get the application service helper.
my $app_service = Bio::KBase::AppService::Client->new();

# Declare the option variables and their defaults.
my $genomeGroup;
my $recipe;
my $skipIndexing;
my $contigs;
# Now we parse the options.
GetOptions($commoner->options(), $reader->lib_options(),
        'contigs=s' => \$contigs,
        'genome-group=s' => \$genomeGroup,
        'skip-indexing' => \$skipIndexing
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
# Insure we have only one input type.
if ($contigs) {
    if ($reader->check_for_reads()) {
        die "Cannot specify both contigs and FASTQ input.";
    }
} elsif (! $reader->check_for_reads()) {
    die "Must specify either contigs or FASTQ input.";
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    skip_indexing => ($skipIndexing ? "true" : "false"),
    output_path => $outputPath,
    output_file => $outputFile,
};
# Add the optional parameters.
if ($contigs) {
    $params->{contigs} = $uploader->fix_file_name($contigs, 'contigs');
} else {
    $reader->store_libs($params);
}
if ($recipe) {
    $params->{recipe} = $recipe;
}
if ($genomeGroup) {
    $params->{genome_group} = $genomeGroup;
}
# Submit the job.
$commoner->submit($app_service, $uploader, $params, MetagenomeBinning => 'binning');
