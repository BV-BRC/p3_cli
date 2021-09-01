=head1 Submit a Multiple Sequence Alignment Request

This script submits a request to submit an MSA job to BV-BRC.  It accepts as input multiple features and/or feature sequences,
and builds an alignment for display.

=head1 Usage Synopsis

    p3-submit-MSA [options] output-path output-name

Start a multiple sequence alignment, producing output in the specified workspace path, using the specified name for the base filename
of the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Prefix to be put in front of the output path.  This is optional, and is provided for uniformity with other commands.

=item --workspace-upload-path

Name of workspace directory to which local files should be uplaoded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --alphabet

The type of sequences to align-- C<dna> or C<protein>.  The default is C<dna>.

=item --aligner

Alignment tool to use-- C<Muscle>, C<Mafft>, or C<progressiveMauve>.  The default is C<Muscle>.

=item --fasta-file

A FASTA file containing sequences to align.  If a local DNA file is specified, it will be uploaded as C<feature_dna_fasta>.
If a local protein file is specified, it will be uploaded as C<feature_protein_fasta>.  To specify multiple FASTA files,
specify this option multiple times.

=item --feature_group

A workspace feature group file.  This can never be a local file, so a C<ws:> prefix is simply stripped off.  To specify
multiple feature groups, specify this option multiple times.

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

use constant ALPHABET_TYPE => { 'dna' => 'feature_dna_fasta', 'protein' => 'feature_protein_fasta' };

use constant ALIGNER => { 'Muscle' => 1, 'Mafft' => 1, 'progressiveMauve' => 1 };

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
my $aligner = 'Muscle';
my $alphabet = 'dna';
my $fastaFilesIn;
my $featureGroupsIn;
# Now we parse the options.
GetOptions($commoner->options(),
        'aligner=s' => \$aligner,
        'alphabet=s' => \$alphabet,
        'fasta-file=s@' => \$fastaFilesIn,
        'feature-groups=s@' => \$featureGroupsIn,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
my $fileType = ALPHABET_TYPE->{$alphabet};
if (! $fileType) {
    die "Invalid alphabet-- must be 'dna' or 'protein'.";
}
if (! ALIGNER->{$aligner}) {
    die "Unknown aligner name '$aligner'.";
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    alphabet => $alphabet,
    aligner => $aligner,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Get the list of FASTA files.
if ($fastaFilesIn) {
    $params->{fasta_files} = $uploader->fix_file_list($fastaFilesIn, $fileType);
} elsif (! $featureGroupsIn) {
    die "Must specify either --fasta-file or --feature-group.";
}
# Get the list of feature groups.
if ($featureGroupsIn) {
    my @groups;
    for my $featureGroup (@$featureGroupsIn) {
        $featureGroup =~ s/^ws://;
        my $fullName = $uploader->normalize($featureGroup);
        push @groups, $fullName;
    }
    $params->{feature_groups} = \@groups;
}
# Submit the job.
$commoner->submit($app_service, $uploader, $params, MSA => 'multi-sequence alignment');
