=head1 Submit a Fastq Utilities Job

This script submits a Fastqutils job to BV-BRC.  It allows input from all supported read libraries, and requests a list
of services to be performed.

=head1 Usage Synopsis

    p3-submit-fastqutils [options] output-path output-name

Start a FASTQ processing job specified workspace path, using the specified name for the output job folder.

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

=item --trim

Trim the sequences.  This operation is performed before quality control.

=item --paired_filter

Perform paired-end filtering.  This operation is always performed first.

=item --fastqc

Run the FASTQ quality control analysis.  This operation is performed after trimming.

=item --reference-genome-id

If specified, the ID of a genome in BV-BRC to which the reads will be aligned.  This operation is always performed last.

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
use Bio::KBase::AppService::GenomeIdSpec;

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
my $trim = 0;
my $pairedFilter = 0;
my $fastqc = 0;
my $align = 0;
my $referenceGenomeId;
# Now we parse the options.
GetOptions($commoner->options(), $reader->lib_options(),
        'trim' => \$trim,
        'paired-filter' => \$pairedFilter,
        'fastqc' => \$fastqc,
        'reference-genome-id|ref|genome=s' => \$referenceGenomeId
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# We will build the recipe list here.
my $recipes = [];
if ($pairedFilter) { push @$recipes, 'paired_filter'; }
if ($trim) { push @$recipes, 'trim'; }
if ($fastqc) { push @$recipes, 'fastqc' }
if ($referenceGenomeId) {
    if (! Bio::KBase::AppService::GenomeIdSpec::validate_genome('--reference-genome-id' => $referenceGenomeId)) {
        die "Invalid reference genome ID.";
    }
    push @$recipes, 'align';
}
if (! @$recipes) {
    die "No service specified.";
}
# Build the parameter structure.
my $params = {
    recipe => $recipes,
    output_path => $outputPath,
    output_file => $outputFile
};
if (! $reader->check_for_reads()) {
    die "You must specify a FASTQ source.";
}
# Add the input FASTQ files.
$reader->store_libs($params);
# Add the reference genome ID, if needed.
if ($referenceGenomeId) {
    $params->{reference_genome_id} = $referenceGenomeId;
}

# Submit the job.
$commoner->submit($app_service, $uploader, $params, FastqUtils => 'fastq utilities');
