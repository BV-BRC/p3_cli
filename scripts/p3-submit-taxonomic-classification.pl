=head1 Submit a Taxonomic Classification Job

This script submits a Taxonomic Classification job to BV-BRC.  It allows input from either read libraries or a FASTA file and uses
the Kraken2 algorithm to determine the taxonomic makeup of the input.

=head1 Usage Synopsis

    p3-submit-taxonomic-classification [options] output-path output-name

Start a taxonomic classification, producing output in the specified workspace path, using the specified name for the base filename
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

The following options modify the classification process.

=over 4

=item --16S

If specified, then the sample is presumed to be a 16S sample instead of a whole-genome sample.

=item --confidence

Confidence interval.  Must be 0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, or 1.  The default
is 0.1.

=item --analysis-type

"pathogen" or "microbiome".  If "microbiome" is specified, an additional analysis step is added that provides useful reports
on microbiome-specific issues such as alpha and beta diversity.  The default is "pathogen".  This parameter is ignored if
B<16s> is specified.

=item --database

Type of database to use.  For a "wgs" sequence, this is "bvbrc" or "standard"; for a "16S" sequence, this is "SILVA" or
"Greengenes".  The default is "bvbrc" for the whole-genome sequences and "SILVA" for 16S.

=item --save-classified

If specified, the classified sequences will be saved in the output folder.

=item --save-unclassified

If specified, the unclassified sequences will be saved in the output folder.

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
use constant DB_16S => { SILVA => 1, Greengenes => 1 };
use constant DB_WGS => { standard => 1, bvbrc => 1 };
use constant AT_WGS => { pathogen => 1, microbiome => 1 };
use constant CONFIDENCE => { '0' => 1, '0.1' => 1, '0.2' => 1, '0.3' => 1, '0.4' => 1, '0.5' => 1, '0.6' => 1,
                             '0.7' => 1, '0.8' => 1, '0.9' => 1, '1' => 1 };


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
my $saveClassified = 0;
my $saveUnclassified = 0;
my $st16s = 0;
my $analysisType;
my $database;
my $sequenceType;
my $confidence = '0.1';
# Now we parse the options.
GetOptions($commoner->options(), $reader->lib_options(),
        '16S' => \$st16s,
        'analysis-type=s' => \$analysisType,
        'database=s' => \$database,
        'save-classified' => \$saveClassified,
        'save-unclassified' => \$saveUnclassified,
        'confidence=s' => \$confidence,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if ($st16s) {
    # Here we have a 16S sample.  The default database is "SILVA" and the analysis type is 16S only.  We allow both "16S" and "16s".
    $sequenceType = "16S";
    $analysisType //= "16S";
    $analysisType = uc $analysisType;
    if ($analysisType ne "16S") {
        die "For a 16S sample the analysis type must be \"16S\".";
    }
    $database //= "SILVA";
    if (! DB_16S->{$database}) {
        die "Invalid database type for 16S samples: must be \"SILVA\" or \"Greengenes\".";
    }
} else {
    $sequenceType = "wgs";
    # Here we have a normal sample.  The default database is "bvbrc" and the analysis type can be "pathogen" or "microbiome".
    $analysisType //= "pathogen";
    if (! AT_WGS->{$analysisType}) {
        die "Invalid analysis type for WGS samples: must be \"pathogen\" or \"microbiome\".";
    }
    $database //= "bvbrc";
    if (! DB_WGS->{$database}) {
        die "Invalid database type for WGS samples: must be \"bvbrc\" or \"standard\".";
    }
}
# Validate the confidence interval.
if (! CONFIDENCE->{$confidence}) {
    die "Invalid confidence interval.  Must be 0, 1, or 0.X where X is a single digit.";
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    analysis_type => $analysisType,
    sequence_type => $sequenceType,
    database => $database,
    confidence => $confidence,
    save_unclassified_sequences => $saveUnclassified,
    save_classified_sequences => $saveClassified,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Submit the job.
$commoner->submit($app_service, $uploader, $params, TaxonomicClassification => 'classification');
