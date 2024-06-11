=head1 Submit a Wastewater Analysis Job

This script submits a Wastewater Analysis job to BV-BRC.  It allows input from various types of read libraries.

=head1 Usage Synopsis

    p3-submit-wastewater-analysis [options] output-path output-name

Start a wastewater analysis, producing output in the specified workspace path, using the specified name for the base filename
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

The following options specify the reads to be classified.

=over 4

=item --paired-end-lib

Two paired-end libraries containing reads.  These are coded with a single invocation, e.g. C<--paired-end-lib left.fastq right.fastq>.  The
libraries must be paired FASTQ files.  A prefix of C<ws:> indicates a file is in the BV-BRC workspace; otherwise they are uploaded
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

=item strategy

Analysis strategy to use.  Currently the only option is C<onecodex>.

=back

These options modify the way the reads are analyzed, and should precede any library specifications
to which they apply.  For example,

    --date 01/12/2024 --primers midnight,V1 --paired-end-lib S1.fq S2.fq --primers ARTIC,V5.3.2 --single-end-lib ERR12345.fq  --srr-id SRR54321

means that the local files C<S1.fq> and C<S2.fq> used V1 of the midnight primers, but the single-end library C<ERR12345.fq> and
the NCBI library SRR54321 use the ARTIC V5.3.2 primers.  All of the samples are dated 01/12/2024.

=over 4

=item date

Date of the subsequent samples, in I<MM/DD/YYYY> format.

=item primers

Name and version of the primer set used, separated by a comma.  The default is C<ARTIC,V5.3.2>.  Note that the C<V> is required in the version.

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
use File::Basename;
use Bio::KBase::AppService::CommonSpec;
use Bio::KBase::AppService::ReadSpec;
use Bio::KBase::AppService::UploadSpec;
use constant RECIPES => { onecodex => 1 };

# Insure we're logged in.
my $p3token = P3AuthToken->new();
if (! $p3token->token()) {
    die "You must be logged into BV-BRC to use this script.";
}
# Get a common-specification processor, an uploader, and a reads-processor.
my $commoner = Bio::KBase::AppService::CommonSpec->new();
my $uploader = Bio::KBase::AppService::UploadSpec->new($p3token);
my $reader = Bio::KBase::AppService::ReadSpec->new($uploader, assembly => 1, samples => 1, analysis => 1);

# Get the application service helper.
my $app_service = Bio::KBase::AppService::Client->new();

# Declare the option variables and their defaults.
my $strat = 'onecodex';
# Now we parse the options.
GetOptions($commoner->options(), $reader->lib_options(),
        'strategy' => \$strat
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if (! RECIPES->{$strat}) {
    die "Invalid strategy specified.";
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Validate the read libraries.
if (! $reader->check_for_reads()) {
    die "Must specify at least one source of reads.";
}
# Build the parameter structure.
my $params = {
    output_path => $outputPath,
    output_file => $outputFile,
    strategy => $strat,
    primers => 'ARTIC'
};
# Store the read libraries.
$reader->store_libs($params);
# Submit the job.
$commoner->submit($app_service, $uploader, $params, SARS2Wastewater => 'SARS2 Wastewater Analysis');
