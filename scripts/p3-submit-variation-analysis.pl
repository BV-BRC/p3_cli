=head1 Submit a Variation Analysis Job

This script submits a Variation Analysis job to BV-BRC.  It takes input from read libraries and looks for small differences
against a reference genome.

=head1 Usage Synopsis

    p3-submit-variation-analysis [options] output-path output-name

Start a variation analysis, producing output in the specified workspace path, using the specified name for the base filename
of the output files.

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

The following options specify the reads to be analyzed.

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

The following options modify the analysis process.

=over 4

=item --reference-genome-id

The ID of the genome in BV-BRC to be used as a reference.

=item --mapper

Mapping utility to use-- C<BWA-mem>, C<BWA-mem-strict>, C<Bowtie2>, or C<LAST>.  Default is C<BWA-mem>.

=item --caller

SNP-calling utility to use-- C<FreeBayes> or C<SAMtools>.  Default is C<FreeBayes>.

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

use constant CALLERS => { 'FreeBayes' => 1, 'SAMtools' => 1};
use constant MAPPERS => { 'BWA-mem' => 1, 'BWA-mem-strict' => 1, 'Bowtie2' => 1, 'LAST' => 1 };

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
my $referenceGenomeId;
my $mapper = "BWA-mem";
my $caller = "FreeBayes";
# Now we parse the options.
GetOptions($commoner->options(), $reader->lib_options(),
        'reference-genome-id=s' => \$referenceGenomeId,
        'mapper=s' => \$mapper,
        'caller=s' => \$caller,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if (! $reader->check_for_reads()) {
    die "Must specify at least one FASTQ source.";
}
# Validate the reference genome ID.
if (! $referenceGenomeId) {
    die "Reference genome ID is required.";
}
my $refId = Bio::KBase::AppService::GenomeIdSpec::validate_genome('--reference-genome-id' => $referenceGenomeId);
if (! $refId) {
    die "Invalid reference genome ID.";
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    reference_genome_id => $refId,
    mapper => $mapper,
    'caller' => $caller,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Add the read sources.
$reader->store_libs($params);
# Submit the job.
$commoner->submit($app_service, $uploader, $params, Variation => 'variation analysis');
