=head1 Submit a Phylogenetic Tree Mapping Request

This script submits a request to build a codon tree to BV-BRC.  This is a slow process and the job can take more than one day, depending on the
number of genoems.  It takes a list of BV-BRC genome IDs as input and accepts a few additional parameters.

=head1 Usage Synopsis

    p3-submit-codon-tree [options] output-path output-name

Start a phylogenetic tree mapping job, producing output in the specified workspace path, using the specified name for the base filename
of the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Prefix to be put in front of the output path.  This is optional, and is provided for uniformity with other commands.

=item --genome-ids

Main list of genome IDs, comma-delimited.  Alternatively, this can be a local file name.  If specified, the file must be tab-delimited,
with a header line, containing the genome IDs in the first column.  The genome IDs in this file can optionally be enclosed in quotes,
allowing a text file download of a BV-BRC genome group or genome display to be used.

=item --optional-genome-ids

Additional list of genome IDs, comma-delimited.  These genomes are not penalized for missing or duplicated genes.  As with C<--genome-ids>,
this can also be the name of a file containing the genome IDs.

=item --number-of-genes

Number of marker genes to use for building the tree (default 100).

=item --max-genomes-missing

The maximum number of genomes that can be missing from any PGFam before the family is disqualified.

=item --max-allowed-dups

The maximum number of genoems that can have multiple proteins from a PGFam before the family is disqualified.

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
use Bio::KBase::AppService::GenomeIdSpec;
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

# Get the application service helper.
my $app_service = Bio::KBase::AppService::Client->new();

# Declare the option variables and their defaults.
my $numberOfGenes = 100;
my $maxGenomesMissing = 0;
my $maxAllowedDups = 0;
my $genomeIds;
my $optionalGenomeIds;
# Now we parse the options.
GetOptions($commoner->options(),
        'genome-ids=s' => \$genomeIds,
        'optional-genome-ids=s' => \$optionalGenomeIds,
        'number-of-genes=i' => \$numberOfGenes,
        'max-genomes-missing=i' => \$maxGenomesMissing,
        'max-allowed-dups=i' => \$maxAllowedDups
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if ($numberOfGenes < 10) {
    die "Number of genes must be at least 10.";
}
if ($maxGenomesMissing < 0 or $maxGenomesMissing > 10) {
    die "max-genomes-missing must be between 0 and 10."
}
if ($maxAllowedDups < 0 or $maxAllowedDups > 10) {
    die "max-allowed-dups must be between 0 and 10."
}
# Validate the genome lists.
my $genomeList = Bio::KBase::AppService::GenomeIdSpec::validate_genomes($genomeIds);
if (! $genomeList) {
    die "Error processing genome-ids.";
}
my $optionalGenomeList = [];
if ($optionalGenomeIds) {
    $optionalGenomeList = Bio::KBase::AppService::GenomeIdSpec::validate_genomes($optionalGenomeIds);
    if (! $optionalGenomeList) {
        die "Error processing optional-genome-ids.";
    }
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    genome_ids => $genomeList,
    optional_genome_ids => $optionalGenomeList,
    number_of_genes => $numberOfGenes,
    bootstraps => 100,
    max_genomes_missing => $maxGenomesMissing,
    max_allowed_dups => $maxAllowedDups,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Submit the job.
$commoner->submit($app_service, $uploader, $params, CodonTree => 'phylogenetic-mapping');
