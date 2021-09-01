=head1 Submit a Gene Phylogeny Tree Request

This script submits a request to build a phylogenetic tree of protein sequences.  It accepts as input a group of FASTA files,
and forms them into a tree using various criteria and methods.

=head1 Usage Synopsis

    p3-submit-gene-tree [options] output-path output-name

Start a gene phylogeny job, producing output in the specified workspace path, using the specified name for the base filename
of the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Base workspace directory for relative workspace paths.

=item --workspace-upload-path

Name of workspace directory to which local files should be uplaoded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --sequences

Main list of FASTA input files.  These can be protein fasta files or DNA fasta files.  For multiple files, specify the
option multiple times.

=item --trim-threshold

Alignment end-trimming threshold.

=item --gap-threshold

Threshold for deleting alignments with large gaps.

=item --dna

If specified, the inputs are assumed to be DNA sequences.  The default is protein sequences.

=item --substitution-model

Substitution model to use.  The options are C<HKY85>, C<JC69>, C<K80>, C<F81>, C<F84>, C<TN93>, C<GTR>,
C<LG>, C<WAG>, C<JTT>, C<MtREV>, C<Dayhoff>, C<DCMut>, C<RtREV>, C<CpREV>, C<VT>, C<AB>, C<Blosum62>,
C<MtMam>, C<MtArt>, C<HIVw>, or C<HIVb>.

=item --recipe

Recipe for building the tree.  The options are C<RAxML>, C<PhyML>, or C<FastTree>.  The default is C<RAxML>.

=back

The following options are used for assistance and debugging.

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
use Bio::KBase::AppService::GenomeIdSpec;
use Bio::KBase::AppService::UploadSpec;
use List::Util;

use constant SUB_MODELS => { "HKY85" => 1, "JC69" => 1, "K80" => 1, "F81" => 1, "F84" => 1, "TN93" => 1, "GTR" => 1, "LG" => 1,
        "WAG" => 1, "JTT" => 1, "MtREV" => 1, "Dayhoff" => 1, "DCMut" => 1, "RtREV" => 1, "CpREV" => 1, "VT" => 1,
        "AB" => 1, "Blosum62" => 1, "MtMam" => 1, "MtArt" => 1, "HIVw" => 1, "HIVb" => 1 };

use constant RECIPES => { "RAxML" => 1, "PhyML" => 1, "FastTree" => 1 };

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
my $sequences;
my $trimThreshold;
my $gapThreshold;
my $dnaFlag;
my $substitutionModel;
my $recipe = 'RAxML';
# Now we parse the options.
GetOptions($commoner->options(),
        'sequences=s@' => \$sequences,
        'trim-threshold=f' => \$trimThreshold,
        'gap-threshold=f' => \$gapThreshold,
        'dna' => \$dnaFlag,
        'substitution-model=s' => \$substitutionModel,
        'recipe=s' => \$recipe
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
# Validate the tuning parameters.
if (! RECIPES->{$recipe}) {
    die "Invalid recipe specified.";
}
if ($substitutionModel && ! SUB_MODELS->{$substitutionModel}) {
    die "Invalid substitution model.";
}
# Get the user sequence files.
my $type = ($dnaFlag ? 'feature_dna_fasta' : 'feature_protein_fasta');
my $sequenceFiles = $uploader->fix_file_list($sequences, $type);
# Add the type to each sequence file.
$sequenceFiles = [ map { { filename => $_, type => 'FASTA' } } @$sequenceFiles ];
# Compute the alphabet.
my $alphabet = ($dnaFlag ? "DNA" : "Protein");
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    sequences => $sequenceFiles,
    alphabet => $alphabet,
    recipe => $recipe,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Add the optionals.
if (defined $gapThreshold) {
    $params->{gap_threshold} = $gapThreshold;
}
if (defined $trimThreshold) {
    $params->{trim_threshold} = $trimThreshold;
}
if ($substitutionModel) {
    $params->{substitution_model} = $substitutionModel;
}
# Submit the job.
$commoner->submit($app_service, $uploader, $params, GeneTree => 'gene phylogeny');
