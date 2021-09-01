=head1 Submit a Comprehensive Genome Analysis Job

This script submits a CGA job to BV-BRC.  It allows input from either read libraries or a FASTA file, annotates the sequences
(after any necessary assembly), and produces a page of useful reports and graphs.

=head1 Usage Synopsis

    p3-submit-CGA [options] output-path output-name

Start a comprehensive genome analysis, producing output in the specified workspace path, using the specified name for the base filename
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

The following options specify the reads from which the genome should be assembled.

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

The following options modify the entire assembly process.

=over 4

=item --min-contig-length

Minimal output contig length (default C<300>).

=item --min-contig-cov

Minimal output contig coverage (Default C<5>).

=item --trim

If specified, the reads should be trimmed before assembly.

=item --pilon-iter

Number of pilon iterations (default C<2>).

=item --racon-iter

Number of racon iterations (default <2>).

=item --recipe

Assembly recipe (C<auto>, C<full_spades>, C<fast>, C<miseq>, C<smart>, or C<kiki>; default C<auto>).

=back

The following option specifies the contigs for the genome.  If this is specified, the above options relating to reads
should not be used.

=over 4

=item --contigs

Input FASTA file of assembled contigs.  (If specified, all options relating to assembly will be ignored.  This is mutually exclusive with
C<--paired-end-libs>, C<--single-end-libs>, C<srr-ids>, and C<interleaved-libs>)

=back

The following options describe the genome for the annotation process.

=over 4

=item --scientific-name

Scientific name of genome to be annotated.

=item --label

Label to add to end of scientific name to form genome name.

=item --taxonomy-id

NCBI taxonomy identifier for the genome.

=item --code

Genetic code (C<4> or C<11>, default C<11>).

=item --domain

Domain of the submitted genome (C<Archaea> or C<Bacteria>, default C<Bacteria>).

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
use Bio::KBase::AppService::ReadSpec;
use Bio::KBase::AppService::UploadSpec;
use Bio::KBase::AppService::GenomeIdSpec;

use constant VALID_RECIPES => { auto => 1,  full_spades => 1, fast => 1, miseq => 1, smart => 1, kiki => 1 };

use constant VALID_DOMAINS => { A => 'Archaea', Archaea => 'Archaea', B => 'Bacteria', Bacteria => 'Bacteria'};

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
my $minContigLength = 300;
my $minContigCov = 5;
my $trim = 0;
my $taxonomyId;
my $scientificName;
my $raconIter = 2;
my $pilonIter = 2;
my $recipe = "auto";
my $contigs;
my $code = 11;
my $domain = "Bacteria";
my $label;
# Now we parse the options.
GetOptions($commoner->options(), $reader->lib_options(),
        'min-contig-length=i' => \$minContigLength,
        'min-contig-cov=f' => \$minContigCov,
        'trim' => \$trim,
        'taxonomy-id|tax-id=i' => \$taxonomyId,
        'scientific-name|name' => \$scientificName,
        'racon-iter|racon=i' => \$raconIter,
        'pilon-iter|pilon=i' => \$pilonIter,
        'recipe=s' => \$recipe,
        'contigs=s' => \$contigs,
        'code|gc=i' => \$code,
        'domain=s' => \$domain,
        'label=s' => \$label
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
# Insure we are compatible with the input type.
my $inputType = "reads";
if ($contigs) {
    $inputType = "contigs";
    if ($reader->check_for_reads()) {
        die "Cannot specify both contigs and FASTQ input.";
    }
} elsif (! $reader->check_for_reads()) {
    die "Must specify either contigs or FASTQ input.";
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Verify the recipe.
if (! VALID_RECIPES->{$recipe}) {
    die "Invalid assembly recipe specified.";
}
# Verify the domain.
my $realDomain = VALID_DOMAINS->{$domain};
if (! $realDomain) {
    die "Invalid domain $domain.";
}
# Insure we have a taxonomy ID and a scientific name.
$scientificName = Bio::KBase::AppService::GenomeIdSpec::process_taxid($taxonomyId, $scientificName);
# Build the parameter structure.
my $params = {
    input_type => $inputType,
    min_contig_length => $minContigLength,
    min_contig_cov => $minContigCov,
    trim => $trim,
    taxonomy_id => $taxonomyId,
    racon_iter => $raconIter,
    pilon_iter => $pilonIter,
    recipe => $recipe,
    code => $code,
    domain => $domain,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Add the optional parameters.
if ($contigs) {
    $params->{contigs} = $uploader->fix_file_name($contigs);
} else {
    $reader->store_libs($params);
}
if ($scientificName) {
    $params->{scientific_name} = $scientificName;
}
# Submit the job.
$commoner->submit($app_service, $uploader, $params, ComprehensiveGenomeAnalysis => 'analysis');
