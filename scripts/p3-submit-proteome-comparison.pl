=head1 Submit a Proteome Comparison Request

This script submits a request to compare proteins against a reference genome.  In addition to the reference genome ID, it
takes as input one or more protein feature sets.  These can be feature groups, protein FASTA files, or other genomes.

=head1 Usage Synopsis

    p3-submit-proteome-comparison [options] output-path output-name

Start a proteome comparison job, producing output in the specified workspace path, using the specified name for the base filename
of the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Base workspace directory for relative workspace paths.

=item --workspace-upload-path

Name of workspace directory to which local files should be uplaoded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --genome-ids

Main list of genome IDs, comma-delimited.  Alternatively, this can be a local file name.  If specified, the file must be tab-delimited,
with a header line, containing the genome IDs in the first column.  The genome IDs in this file can optionally be enclosed in quotes,
allowing a text file download of a BV-BRC genome group or genome display to be used.

=item --protein-fasta

List of protein fasta files.  These operate as virtual genomes containing the proteins in the FASTA file.  (They may, in fact, be
the protein fasta files of real genomes.)  For multiple values, specify the option multiple times.

=item --user-feature-group

List of BV-BRC feature group names.  These are specified as workspace files, so they are modified by the workspace path prefix,
but they should not have the C<ws:> prefix.  Each group is treated as a virtual genome containing the proteins in the group.  For
multiple groups, specify the option multiple times.

=item --reference-genome-id

ID of the reference genome.  If omitted, the first genome in the C<--genome-ids> list will be used.

=back

The following parameters determine whether a match between two proteins is acceptable.  The matches are performed by BLASTP,
so most of these correspond to BLAST parameters.

=over 4

=item --min-seq-cov

The minimum coverage of the sequences for the match to be accepted.  The default is 0.30 (30%).

=item --max-e-val

The maximum e-value of the sequence match for the match to be accepted.  The default is 1e-5.

=item --min-ident

The minimum fraction identity for a match to be accepted.  The default is 0.1 (10%).

=item --min-positive

The minimum fraction for positive-scording positions in a match. The default is 0.2 (20%).

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
use Bio::KBase::AppService::GroupSpec;
use List::Util;

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
my $genomeIds;
my $proteinFastas;
my $userFeatureGroups;
my $referenceGenomeId;
my $minSeqCov = 0.30;
my $maxEVal = 1e-5;
my $minIdent = 0.1;
my $minPositives = 0.2;
# Now we parse the options.
GetOptions($commoner->options(),
        'genome-ids=s' => \$genomeIds,
        'protein-fasta=s@' => \$proteinFastas,
        'user-feature-group=s@' => \$userFeatureGroups,
        'reference-genome-id=s' => \$referenceGenomeId,
        'min-seq-cov=f' => \$minSeqCov,
        'max-e-val=f' => \$maxEVal,
        'min-ident=f' => \$minIdent,
        'min-positives=f' => \$minPositives
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if ($minSeqCov < 0 || $minSeqCov > 1.0) {
    die "Minimum sequence coverage must be between 0 and 1.";
}
if ($minIdent < 0 || $minIdent > 1.0) {
    die "Minimum identity must be between 0 and 1.";
}
if ($minPositives < 0 || $minPositives > 1.0) {
    die "Minimum positives must be between 0 and 1.";
}
# Validate the reference genome ID.
if (! $referenceGenomeId) {
    die "reference-genome-id is required."
} elsif ($referenceGenomeId !~ /^\d+\.\d+$/) {
    die "Invalid reference genome ID.";
}
my $refId = Bio::KBase::AppService::GenomeIdSpec::validate_genome('--reference-genome-id' => $referenceGenomeId);
if (! $refId) {
    die "Reference genome ID not valid.";
}
# Validate the genome lists.
my $genomeList = Bio::KBase::AppService::GenomeIdSpec::validate_genomes($genomeIds);
if (! $genomeList) {
    die "Error processing genome-ids.";
}
# Now we need to map the reference genome ID into this list.
my $referenceGenomeIndex = List::Util::first { $_ eq $refId } @$genomeList;
if (! defined $referenceGenomeIndex) {
    # Add the ref ID to the front of the list.
    unshift @$genomeList, $refId;
    $referenceGenomeIndex = 1;
} else {
    # Convert from 0-based to 1-based.
    $referenceGenomeIndex++;
}
# Get the user genomes.  These are protein fasta files.
my $userGenomes = $uploader->fix_file_list($proteinFastas, 'feature_protein_fasta');
# Check the feature groups.
if (! $userFeatureGroups) {
    $userFeatureGroups = [];
} else {
    $userFeatureGroups = Bio::KBase::AppService::GroupSpec::validate_groups($userFeatureGroups, $uploader->get_prefix());
}
# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);
# Build the parameter structure.
my $params = {
    genome_ids => $genomeList,
    user_feature_groups => $userFeatureGroups,
    user_genomes => $userGenomes,
    reference_genome_index => $referenceGenomeIndex,
    min_seq_cov => $minSeqCov,
    min_ident => $minIdent,
    min_positives => $minPositives,
    max_e_val => $maxEVal,
    output_path => $outputPath,
    output_file => $outputFile,
};
# Submit the job.
$commoner->submit($app_service, $uploader, $params, GenomeComparison => 'proteome comparison');
