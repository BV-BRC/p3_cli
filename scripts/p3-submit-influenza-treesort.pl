=head1 Submit an Influenza Reassortment Analysis Job

This script submits a request to build a reassortment of influenza virus segments. The reassortment uses the phylogenetic
tree of a reference segment to infer which other segments belong with it.

=head1 Usage Synopsis

    p3-submit-influenza-treesort [options] output-path output-name

Start an influenza reassortment analysis job, producing output in the specified workspace path, using the specified name
for the base filenameof the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Base workspace directory for relative workspace paths.

=item --workspace-upload-path

Name of workspace directory to which local files should be uploaded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --fasta

The name of a FASTA input file. The file must consist of whole segments with specifically formatted headers. This format
is described below in the L</FASTA Input Format> section. The file is presumed to be on your local drive, in which case it
will be uploaded to your BV-BRC workspace (or the workspace specified by C<--workspace-upload-path>) and then used as input to the service. 
If the file name starts with C<ws:>, it is presumed to be a workspace file, and it will be used directly without uploading.

=item --ref

The name of the reference segment. This must be one of the segments included in the FASTA file. The default is C<HA>.

=item --names

A comma-delimited list of segment names. I<The names must correspond to the segments included in the FASTA file.> The
web interface calculates them automatically, but this script does not always have access to the file, so you must
specify them manually. The permissible segment names are: PB2, PB1, PA, HA, NP, NA, MP, NS. The default is C<HA,NA>. 
If the reference segment name is not included, it will be added automatically.

=item --method

The method to use for tree building. The options are C<local> and C<mincut>. The default is C<local>.

=item --inf
Inference method to use. The options are C<FastTree> and C<IQ-Tree>. The default is C<FastTree>.

=item --max-dev

The maximum deviation allowed from the standard substitution rate. The default is 2.0, which means that the maximum rate can be twice as high or
twice as low as the standard rate.

=item --cutoff

The cutoff p-value for the reassortment tests. The default is 0.001 (1 percent).

=item --clades-file

The name for an optional output file where clades with evidence of reassortment will be stored. The file will be stored in the workspace
output directory.

=item --clock

Estimate molecular clock rates for difference segments, assuming equal rates. This is a boolean parameter that defaults to false.

=item --no-collapse

By default, TreeSort collapses near zero-length branches into multifurcations. Specify this flag to disable that behavior.

=back

The following options are used for assistance and debugging.

=over 4

=item --help

Display the command-line usage and exit.

=item --dry-run

Display the JSON submission string and exit without invoking the service or uploading files.

=back

=head2 FASTA Input Format

The reassortment service (internal name TreeSort) B<only> works with influenza nucleotide sequences.

The segment name must be surrounded by C<|> characters and can be followed by a date in the format YYYYC<->MMC<->DD.
For example:

    >A/swine/Michigan/A02635726/2021|1B.2.1|1998B|TTTPPT|HA|2021-04-23

where the segment is C<HA> and the date is C<2021-04-23> (April 23, 2021).

TreeSort can accept 3 different strain name formats within a FASTA header:

=over 4

=item *

The strain name is everything that remains after the segment name is removed.

=item *

The strain name starts with "EPI_ISL_" followed by a numeric (integer) value.

=item *

A strain name starts with A, B, C, or D followed by 3 to 5 spans of text inside C</> characters. 
For example: 

    A/swine/Iowa/A02635718/2021. 
    
Note that C<|> characters are not allowed in the strain name.

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
use List::Util;

use constant SEGMENT_NAMES => { "PB2" => 1, "PB1" => 1, "PA" => 1, "HA" => 1, "NP" => 1, "NA" => 1, "MP" => 1, "NS" => 1 };

use constant METHOD_NAMES => { local => 1, mincut => 1 };

use constant INF_NAMES => { FastTree => 1, "IQTree" => 1 };

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
my $fasta;
my $ref = "HA";
my $names = "HA,NA";
my $method = "local";
my $inf = "FastTree";
my $maxDev = 2.0;
my $cutoff = 0.001;
my $cladesFile = "";
my $clock;
my $noCollapse;
# Now we parse the options.
GetOptions($commoner->options(),
    "fasta=s" => \$fasta,
    "ref=s" => \$ref,
    "names=s" => \$names,
    "method=s" => \$method,
    "inf=s" => \$inf,
    "max-dev=f" => \$maxDev,
    "cutoff=f" => \$cutoff,
    "clades-file=s" => \$cladesFile,
    "clock" => \$clock,
    "no-collapse" => \$noCollapse,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
# Fix the clock parameter.
$clock = $clock ? 1 : 0;
# Fix the no-collapse parameter.
$noCollapse = $noCollapse ? 1 : 0;
# Validate the segment names.
my %segments = map { $_ => 1 } split(/,/, $names);
$segments{$ref} = 1;
for my $seg (keys %segments) {
    if (! SEGMENT_NAMES->{$seg}) {
        die "Invalid segment name specified: $seg";
    }
}
# Format the segment names for the service.
my $formattedNames = join(",", sort { $a cmp $b } keys %segments);

# Validate the tuning parameters.

if (! METHOD_NAMES->{$method}) {
    die "Invalid method specified.";
}
if (! INF_NAMES->{$inf}) {
    die "Invalid inference method specified.";
}
if ($maxDev <= 1.0) {
    die "Invalid max deviation specified-- must be greater than 1.0.";
}
if ($cutoff <= 0.0 || $cutoff > 1.0) {
    die "Invalid cutoff specified-- must be between 0 and 1.";
}

# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);

# Validate and upload (if necessary)the FASTA input file.
if (! $fasta) {
    die "A FASTA file must be specified.";
}
my $realFastaFileName = $uploader->fix_file_name($fasta, 'contigs');

# Build the parameter structure.
my $params = {
    segments => $formattedNames,
    ref_segment => $ref,
    inference_method => $method,
    ref_tree_inference => $inf,
    deviation => $maxDev,
    p_value => $cutoff,
    clades_path => $cladesFile,
    output_path => $outputPath,
    output_file => $outputFile,
    input_fasta_file_id => $realFastaFileName,
    equal_rates => $clock,
    no_collapse => $noCollapse,
    match_regex => undef,
    input_fasta_data => undef,
    input_fasta_existing_dataset => undef,
    input_fasta_group_id => undef,
    match_regex => undef
};

# Submit the job.
$commoner->submit($app_service, $uploader, $params, TreeSort => 'influenza tree sort');