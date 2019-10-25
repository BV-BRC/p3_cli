=head1 Return a FASTA file for a Genome

    p3-genome-fasta [options] genomeID

This script returns a FASTA file for a specified genome. You can specify feature proteins, feature DNA, or contig DNA.

=head2 Parameters

The positional parameter is the desired genome ID.

The command-line options are as follows. All three are mutually exclusive.

=over 4

=item protein

If specified, the output will be a protein FASTA file.

=item feature

If specified, the output will be a feature DNA FASTA file.

=item contig

If specified, the output will be a contig DNA FASTA file. this is the default.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('genomeID',
        ['mode' => hidden => { one_of => [['protein', 'feature protein FASTA'],
                                          ['feature', 'feature DNA FASTA'],
                                          ['contig', 'contig DNA FASTA']],
                               default => 'contig' }],
        );
# Get the genome ID.
my ($genomeID) = @ARGV;
if (! $genomeID) {
    die "No genome ID specified.";
} elsif (! ($genomeID =~ /^\d+\.\d+$/)) {
    die "Invalid genome ID $genomeID.";
}
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# We will put our results in here.
my $fastaLines;
# Create the genome filter.
my $filter = [['eq', 'genome_id', $genomeID]];
# Determine the output format.
my $mode = $opt->mode;
if ($mode eq 'contig') {
    # In contig mode, we want the query to return [contig-id, sequence].
    $fastaLines = P3Utils::get_data($p3, 'contig', $filter, ['sequence_id', 'sequence_type', 'sequence']);
} else {
    # Here we are getting all features for a genome.
    my $sequenceField = ($mode eq 'protein' ? 'aa_sequence' : 'na_sequence');
    $fastaLines = P3Utils::get_data($p3, 'feature', $filter, ['patric_id', 'product', $sequenceField]);
}
if (! @$fastaLines) {
    die "Genome $genomeID not found or empty.";
}
# $fastaLines is now a list of triples. Write out the triples as a FASTA file.
for my $fastaLine (@$fastaLines) {
    my ($id, $comment, $seq) = @$fastaLine;
    if ($seq) {
        my @chunks = ($seq =~ /(.{1,60})/g);
        print ">$id $comment\n";
        print join("\n", @chunks, "");
    }
}
