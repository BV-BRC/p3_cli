=head1 Submit a Comparative Systems Request

This script submits a request to submit an Comparative Systems Servrice job to BV-BRC.  It accepts as input
up to 500 genomes, specified either via genome groups or genome IDs, and outputs a detailed comparison of
subsystems, pathways, and protein families.

=head1 Usage Synopsis

    p3-submit-comparative-systems [options] output-path output-name

Start a comparative systems job, producing output in the specified workspace path, using the specified name for the base filename
of the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Prefix to be put in front of the output path.  This is optional, and is provided for uniformity with other commands.

=item --workspace-upload-path

Name of workspace directory to which local files should be uplaoded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --genomes

A comma-delimited list of IDs for genomes to process.

=item --genome-group

The path to a genome group containing genomes to process. Multiple groups can be specified by using this option
multiple times.

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

# Declare the input list variables.
my $genomeIdsIn;
my $genomeGroupsIn;
# Now we parse the options.
GetOptions($commoner->options(),
        'genomes=s' => \$genomeIdsIn,
        'genome-group=s@' => \$genomeGroupsIn,
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    output_path => $outputPath,
    output_file => $outputFile,
};
# Get the list of genome IDs.
if (! $genomeIdsIn && ! $genomeGroupsIn) {
    die "Must specify either --genome or --genome-group.";
}
# Get the list of genome groups.
if ($genomeGroupsIn) {
    my @groups;
    for my $genomeGroup (@$genomeGroupsIn) {
        $genomeGroup =~ s/^ws://;
        my $fullName = $uploader->normalize($genomeGroup);
        push @groups, $fullName;
    }
    $params->{genome_groups} = \@groups;
}
# Validate the list of genome IDs.
if ($genomeIdsIn) {
	my $genomes = Bio::KBase::AppService::GenomeIdSpec::validate_genomes($genomeIdsIn);
	if (! $genomes) {
		die "Invalid genome IDs. Submit aborted.";
	}
	$params->{genome_ids} = $genomes;
}
# Submit the job.
$commoner->submit($app_service, $uploader, $params, ComparativeSystems => 'comparative systems service');
