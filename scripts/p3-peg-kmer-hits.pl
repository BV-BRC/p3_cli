=head1 Count KMER Hits in Proteins

    p3-peg-kmer-hits.pl [options] kmerDB

This script takes as input a list of genome IDs and outputs the best group for each protein feature in each genome.  The output
file will be tab-delimited, with the genomeID, the feature ID, the group ID, the group name, and the kmer hit count.  The kmer
database must specify protein kmers.

=head2 Parameters

The positional parameter is the file name of the kmer database.  This is a json-format L<KmerDb> object.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/col_options> (to choose the genome ID column) plus the following
options.

=over 4

=item verbose

If specified, progress messages will be written to STDERR.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use KmerDb;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('kmerDB', P3Utils::col_options(), P3Utils::ih_options(),
        ['verbose|debug|v', 'print progress to STDERR'],
        );
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Open the input file.
my $ih = P3Utils::ih($opt);
# Get the options.
my $debug = $opt->verbose;
# Get the kmer database.
my ($kmerDBfile) = @ARGV;
if (! $kmerDBfile) {
    die "No KmerDb file specified.";
}
print STDERR "Loading kmers from $kmerDBfile.\n" if $debug;
my $kmerDB = KmerDb->new(json => $kmerDBfile);
# Format the output headers and fill in the group hash.  We also set the query parameters here.
my ($object, $fields);
my @headers = qw(genome_id peg_id group_id group_name score hits);
P3Utils::print_cols(\@headers);
# Read the incoming headers and get the genome ID key column.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Read in the genome IDs.
my $genomes = P3Utils::get_col($ih, $keyCol);
print STDERR scalar(@$genomes) . " genomes found.\n" if $debug;
# Loop through the input.
for my $genome (@$genomes) {
    print STDERR "Processing $genome.\n" if $debug;
    # Get the sequences for this genome.
    my $seqList = P3Utils::get_data($p3, feature => [['eq','genome_id',$genome]], ['patric_id', 'aa_sequence']);
    print STDERR scalar(@$seqList) . " proteins found in genome.\n" if $debug;
    # Loop through the sequences.
    for my $seqData (@$seqList) {
        my %counts;
        my ($id, $seq) = @$seqData;
        my ($group, $score, $hits) = $kmerDB->best_group($seq);
        if ($group) {
            P3Utils::print_cols([$genome, $id, $group, $kmerDB->name($group), $score, $hits]);
        }
    }
}
