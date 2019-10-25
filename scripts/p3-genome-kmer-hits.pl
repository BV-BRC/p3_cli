=head1 Count KMER Hits in Genomes

    p3-genome-kmer-hits.pl [options] kmerDB

This script takes as input a list of genome IDs and outputs a table of the number of kmer hits by group in each genome.  The output
file will be tab-delimited, with the genomeID, the sequence ID, the group ID, the group name, and the kmer hit count.

=head2 Parameters

The positional parameter is the file name of the kmer database.  This is a json-format L<KmerDb> object.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/col_options> (to choose the genome ID column) plus the following
options.

=over 4

=item prot

If specified, the kmers are assumed to be protein kmers.

=item pegs

If specified, the kmer hits will be counted against the genome's proteins, not the genome itself.  This implies
C<--prot>.

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
        ['prot', 'kmer database contains proteins'],
        ['verbose|debug|v', 'print progress to STDERR'],
        ['pegs', 'count hits against protein features, not whole genomes']
        );
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Open the input file.
my $ih = P3Utils::ih($opt);
# Get the options.
my $pegFlag = $opt->pegs;
my $geneticCode = ($opt->prot && ! $pegFlag ? 11 : undef);
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
my @headers = qw(genome_id);
if ($pegFlag) {
    push @headers, 'peg_id';
    $object = 'feature';
    $fields = ['patric_id', 'aa_sequence'];
} else {
    push @headers, 'contig_id';
    $object = 'contig';
    $fields = ['sequence_id', 'sequence'];
}
push @headers, qw(group_id group_name hits);
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
    my $seqList = P3Utils::get_data($p3, $object => [['eq','genome_id',$genome]], $fields);
    print STDERR scalar(@$seqList) . " sequences found in genome.\n" if $debug;
    # Loop through the sequences.
    for my $seqData (@$seqList) {
        my %counts;
        my ($id, $seq) = @$seqData;
        $kmerDB->count_hits($seq, \%counts, $geneticCode);
        for my $group (sort keys %counts) {
            P3Utils::print_cols([$genome, $id, $group, $kmerDB->name($group), $counts{$group}]);
        }
    }
}
