=head1 Submit a Metagenomic Read Mapping Job

This script submits a Metagenomic Read-Mapping job to BV-BRC.  It takes input from read libraries and uses either the CARD or VFDB database
to identify the nature of the incoming reads.

=head1 Usage Synopsis

    p3-submit-metagenomic-read-mapping [options] output-path output-name

Start a metagenomic read mapping, producing output in the specified workspace path, using the specified name for the base filename
of the output files.

=head2 Command-Line Options

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

=item --gene-set-name

The gene set name-- C<CARD> or C<VFDB>.  The default is C<CARD>.

=item --workspace-path-prefix

Base workspace directory for relative workspace paths.

=item --workspace-upload-path

Name of workspace directory to which local files should be uplaoded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

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

use constant GENE_SET_NAMES => { 'VFDB' => 1, 'CARD' => 1 };

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
my $minContigLength = 300;
my $minContigCov = 5;
my $geneSetName = 'CARD';
# Now we parse the options.
GetOptions($commoner->options(), $reader->lib_options(),
        'gene-set-name=s' => \$geneSetName,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if (! $reader->check_for_reads()) {
    die "Must specify some type of FASTQ input.";
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    gene_set_type => 'predefined_list',
    gene_set_fasta => '',
    gene_set_name => $geneSetName,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Add the read input specifier.
$reader->store_libs($params);
# Submit the job.
$commoner->submit($app_service, $uploader, $params, MetagenomicReadMapping => 'read-mapping');
