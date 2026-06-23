=head1 Submit a Whole-Genome SNP Analysis Job

This script submits a request for SNP analysis between genomes to BV-BRC.  It accepts as input a genome group, and finds single-nucleotide polymorphisms
(SNPs) between the genomes in the group.

=head1 Usage Synopsis

    p3-submit-whole-genome-SNP-analysis [options] output-path output-name

Start a whole-genome SNP analysis, producing output in the specified workspace path, using the specified name for the base filename
of the output files. The output identifies Majority SNPs (see C<--threshold>), Core SNPs (present in all genomes), and other SNPs.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Prefix to be put in front of the output path.  This is optional, and is provided for uniformity with other commands.

=item --workspace-upload-path

Name of workspace directory to which local files should be uploaded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --group

A workspace genome group file.  This can never be a local file, so a C<ws:> prefix is simply stripped off.

=item --threshold

The fraction of genomes in the group that must contain the SNP in order for it to be considered a Majority SNP. The default is C<0.5>,
meaning that a SNP must be present in more than half the genomes to be considered a Majority SNP.

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
use Bio::KBase::AppService::UploadSpec;

use constant THRESHOLDS => [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0];

# Insure we're logged in.
my $p3token = P3AuthToken->new();
if (! $p3token->token()) {
    die "You must be logged into BV-BRC to use this script.";
}
# Get a common-specification processor and an uploader.
my $commoner = Bio::KBase::AppService::CommonSpec->new();
my $uploader = Bio::KBase::AppService::UploadSpec->new($p3token);

# Get the application service helper.
my $app_service = Bio::KBase::AppService::Client->new();

# Declare the option variables and their defaults.
my $threshold = 0.5;
my $genomeGroup;
# Now we parse the options.
GetOptions($commoner->options(),
        'threshold=f' => \$threshold,
        'group=s' => \$genomeGroup,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if (!grep { $_ == $threshold } @{THRESHOLDS()}) {
    die "Invalid threshold value: $threshold.  Must be one of: " . join(', ', @{THRESHOLDS()});
}
# Fix up the genome group name.
my $realGenomeGroup = $uploader->normalize($genomeGroup);
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    input_genome_type => 'genome_group',
    input_genome_group => $realGenomeGroup,
    'majority-threshold' => $threshold,
    analysis_type => 'Whole Genome SNP Analysis',
    output_path => $outputPath,
    output_file => $outputFile,
};
# Submit the job.
$commoner->submit($app_service, $uploader, $params, WholeGenomeSNPAnalysis => 'Whole Genome SNP Analysis');
