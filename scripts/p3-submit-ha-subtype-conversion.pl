=head1 Submit an Influenza HA Subtype Numbering Conversion Job

This script submits a request to renumber influenza HA protein sequences accorsing to function rather than position. The proteins
are compared to the selected reference proteins and the numbering is adjusted accordingly.

=head1 Usage Synopsis

    p3-submit-ha-subtype-conversion [options] output-path output-name

Start an influenza HA subtype numbering conversion job, producing output in the specified workspace path, using the specified name
for the folder containing the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Base workspace directory for relative workspace paths.

=item --workspace-upload-path

Name of workspace directory to which local files should be uploaded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --fasta

The name of a FASTA input file. The file must consist of individual protein sequences from HA influenza segments.
If the file name starts with C<ws:>, it is presumed to be a workspace file, and it will be used directly without uploading.

=item --group

The path of a feature group. All the features should be from influenza HA segments. The path will always be a workspace file name,
and must be designated as a feature group.

=item --types

A comma-delimited list of HA protein types. The permissible types are C<H1PR34>, C<H11933>, C<H1post1995>, C<H1N1pdm>, C<H2>, C<H3>, C<H4>, 
C<H5mEAnonGsGD>, C<H5>, C<H5c221>, C<H6>, C<H7N3>, C<H7N7>, C<H8>, C<H9>, C<H10>, C<H11>, C<H12>, C<H13>, C<H14>, C<H15>, C<H16>, C<H17>, 
C<H18>, C<BHongKong>, C<BFlorida>, and C<BBrisbane>. THe default is C<H3,H4>.

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


use constant PROTEIN_NAMES =>
        { H1PR34 => 1, H11933 => 1, H1post1995 => 1, H1N1pdm => 1, H2 => 1, H3 => 1, H4 => 1, H5mEAnonGsGD => 1,
          H5 => 1, H5c221 => 1, H6 => 1, H7N3 => 1, H7N7 => 1, H8 => 1, H9 => 1, H10 => 1, H11 => 1,
          H12 => 1, H13 => 1, H14 => 1, H15 => 1, H16 => 1, H17 => 1, H18 => 1, BHongKong => 1, BFlorida => 1, 
          BBrisbane => 1 };


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
my $group;
my $types = "H3,H4";
# Now we parse the options.
GetOptions($commoner->options(),
    "fasta=s" => \$fasta,
    "group=s" => \$group,
    "types=s" => \$types,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if ($fasta && $group) {
    die "Cannot specify both a FASTA file and a feature group.";
} elsif (! $fasta && ! $group) {
    die "Must specify either a FASTA file or a feature group.";
}

# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);

# Parse the types list.
my @typeList = split(/,/, $types);
foreach my $type (@typeList) {
    if (! PROTEIN_NAMES->{$type}) {
        die "Invalid HA protein type \"$type\". Valid types are: " . join(", ", sort keys %{PROTEIN_NAMES()}) . ".";
    }
}

# Initialize the parameter structure.
my $params = {
    output_path => $outputPath,
    output_file => $outputFile,
    types => \@typeList,
};

# Validate and upload (if necessary) the FASTA input file.

if ($fasta) {
    # Load the FASTA file and fix up the file name if necessary.
    $params->{input_fasta_file} = $uploader->fix_file_name($fasta, 'feature_protein_fasta');
    $params->{input_source} = 'fasta_file';
} else {
    # Validate the group and set the parameter.
    $params->{input_feature_group} = $uploader->normalize($group, 'feature_group');
    $params->{input_source} = 'feature_group';
}


# Submit the job.
$commoner->submit($app_service, $uploader, $params, HASubtypeNumberingConversion => 'influenza HA subtype numbering conversion');