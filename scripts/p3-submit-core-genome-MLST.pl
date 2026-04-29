=head1 Submit a Whole-Genome SNP Analysis Job

This script submits a request for MultiLocus Sequence Typing job to BV-BRC.  It accepts as input a genome group, and selects core and
accessory functions based on the selected species. It then analyzes the genomes for how they differ from each other regarding those 
functions.

=head1 Usage Synopsis

    p3-submit-core-genome-MLST [options] output-path output-name

Start a core genome MultiLocus Sequence Typing (MLST) analysis, producing output in the specified workspace path, using the specified 
name for the base filename of the output files.

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

=item --species

The species for which the core genome MultiLocus Sequence Typing (MLST) analysis should be performed. There is a specific list of supported
species names, and the submitted job will produce no output if an unsupported name is used. This parameter is required.

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
my $species;
my $genomeGroup;
# Now we parse the options.
GetOptions($commoner->options(),
        'species=s' => \$species,
        'group=s' => \$genomeGroup,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}

if (! $species) {
    die "A species must be specified with --species.";
}

# Fix the species name. The user can use spaces, but we want underscores in the service call.
my $realSpecies = $species;
$realSpecies =~ s/\s+/_/g;

# Fix up the genome group name.
my $realGenomeGroup = $uploader->normalize($genomeGroup);
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    input_genome_type => 'genome_group',
    input_genome_group => $realGenomeGroup,
    input_schema_selection => $realSpecies,
    analysis_type => 'chewbbaca',
    output_path => $outputPath,
    output_file => $outputFile,
};
# Submit the job.
$commoner->submit($app_service, $uploader, $params, CoreGenomeMLST => 'Core Genome MLST');
