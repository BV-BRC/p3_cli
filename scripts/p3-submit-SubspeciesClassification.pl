=head1 Submit a Subspecies Classification Request

This script submits a request to classify the contigs in a viral FASTA file.  The user specifies a virus type and the
input sequence is placed in the appropriate taxonomic tree. Use the C<--show-names> option to get the list of valid
virus type codes.

=head1 Usage Synopsis

    p3-submit-SubspeciesClassification [options] output-path output-name

Start a subspecies classification job, producing output in the specified workspace path, using the specified name for the
base filename of the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Prefix to be put in front of the output path.  This is optional, and is provided for uniformity with other commands.

=item --workspace-upload-path

Name of workspace directory to which local files should be uplaoded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --fasta-file

A FASTA file containing the DNA for the virus to analyze.

=item --virus-type

A code specifying the species believed to contain the input virus.

=item --help

Display the command-line usage and exit.

=item --dry-run

Display the JSON submission string and exit without invoking the service or uploading files.

=item --show-names

Display the valid virus types and their associated names.

=back

=cut

use strict;
use Getopt::Long;
use Bio::KBase::AppService::Client;
use P3AuthToken;
use Data::Dumper;
use Bio::KBase::AppService::CommonSpec;
use Bio::KBase::AppService::UploadSpec;

# Map of virus type codes to virus names.
use constant VIRUS_TYPE => {
		BOVDIARRHEA1 => 'Flaviviridae - Bovine viral diarrhea virus',
		DENGUE => 'Flaviviridae - Dengue virus',
		HCV => 'Flaviviridae - Hepatitis C virus',
		INFLUENZAH5 => 'Orthomyxoviridae - Influenza A H5',
		JAPANENCEPH => 'Flaviviridae - Japanese encephalitis virus',
		MASTADENOA => 'Adenoviridae - Human mastadenovirus A',
		MASTADENOB => 'Adenoviridae - Human mastadenovirus B',
		MASTADENOC => 'Adenoviridae - Human mastadenovirus C',
		MASTADENOE => 'Adenoviridae - Human mastadenovirus E',
		MASTADENOF => 'Adenoviridae - Human mastadenovirus F',
		MEASLES => 'Paramyxoviridae - Measles morbilivirus',
		MPOX => 'Poxviridae - Monkeypox virus',
		MUMPS => 'Paramyxoviridae - Mumps orthorubulavirus',
		MURRAY => 'Flaviviridae - Murray Valley encephalitis virus',
		NOROORF1 => 'Caliciviridae - Norovirus [VP1]',
		NOROORF2 => 'Caliciviridae - Norovirus [VP2]',
		ROTAA => 'Reoviridae - Rotavirus A',
		STLOUIS => 'Flaviviridae - St. Louis encephalitis virus',
		SWINEH1 => 'Orthomyxoviridae - Swine influenza H1 (global)',
		SWINEH1US => 'Orthomyxoviridae - Swine influenza H1 (US)',
		SWINEH3 => 'Orthomyxoviridae - Swine influenza H3 (global)',
		TKBENCEPH => 'Flaviviridae - Tick-borne encephalitis virus',
		WESTNILE => 'Flaviviridae - West Nile virus',
		YELLOWFEVER => 'Flaviviridae - Yellow fever',
		ZIKA => 'Flaviviridae - Zika virus',
		};

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
my $virusType = "INFLUENZAH5";
my $fastaFileIn;
my $showFlag;
# Now we parse the options.
GetOptions($commoner->options(),
        'virus-type=s' => \$virusType,
        'fasta-file=s' => \$fastaFileIn,
        'show-names' => \$showFlag,
        );
if ($showFlag) {
	# This is a short-circuit option. We display some help text and exit.
	print STDERR sprintf("%-20s %s\n", "virus_type", "name");
	for my $type (sort keys %{VIRUS_TYPE()}) {
		print STDERR sprintf("%-20s %s\n", $type, VIRUS_TYPE->{$type});
	}
	exit(0);
}
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Verify the virus type.
if (! exists VIRUS_TYPE->{$virusType}) {
	die "Invalid virus type. Use --show-names to get a list of valid types.";
}
# Build the parameter structure.
my $params = {
    virus_type => $virusType,
    input_source => 'fasta_file',
    output_path => $outputPath,
    output_file => $outputFile,
};
# Get the input FASTA file.
if (! $fastaFileIn) {
	die "You must specify an input FASTA file.";
} else {
    my $file = $uploader->fix_file_name($fastaFileIn, 'contigs');
    $params->{input_fasta_file} = $file;
}
# Submit the job.
$commoner->submit($app_service, $uploader, $params, SubspeciesClassification => 'subspecies classification');
