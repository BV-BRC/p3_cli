=head1 Find Protein Features Using Sequence Data

    p3-get-features-by-sequence.pl [options]

This script takes as input a file containing DNA or protein sequences and finds features with those identical sequences. For a DNA sequence, it is
somewhat limited in that it will only find features in organisms with a genetic code of 4 or 11.

The program processes one sequence at a time, so has poor performance for a large input file.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/col_options> (to specify the input column containing the sequence) plus the following
options.

=over 4

=item dna

The input contains DNA sequences. This is the default.

=item protein

The input contains protein sequences. This is mutually exclusive with C<DNA>.

=item fasta

The input file is a FASTA. In this case the output file will be tab-delimited with the columns being (1) the sequence ID, (2) the sequence comment, and (3) the
found feature ID.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use SeedUtils;
use Digest::MD5;
use gjoseqlib;

# Save the genetic codes.
my $xtab4 = SeedUtils::genetic_code(4);
my $xtab11 = SeedUtils::genetic_code(11);

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(),
        ['mode' => hidden => { one_of => [['protein', 'input is protein sequences'],
                                          ['dna', 'input is DNA sequences']],
                                          default => 'dna' }],
        ['fasta', 'input is a FASTA file']
        );
# Save the mode.
my $mode = $opt->mode;
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
# Open the input file.
my $ih = P3Utils::ih($opt);
# The input sequences will be put in here.
my @couplets;
# This will hold the header and key information.
my ($outHeaders, $keyCol);
# Determine the input file format.
if ($opt->fasta) {
    # Here we have FASTA input. Slurp in the sequences and reformat them as couplets.
    my $tuples = gjoseqlib::read_fasta($ih);
    @couplets = map { [$_->[2], [$_->[0], $_->[1]]] } @$tuples;
    # Create the headers.
    $outHeaders = ['fasta.id', 'fasta.comment'];
} else {
    # Normal input. Read the incoming headers.
    ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
    # Slurp in the file.
    while (! eof $ih) {
        my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
        push @couplets, @$couplets;
    }
}
# Form the full header set and write it out.
if (! $opt->nohead) {
    push @$outHeaders, 'sequence.patric_id';
    P3Utils::print_cols($outHeaders);
}
# Loop through the couplets.
for my $couplet (@couplets) {
    my ($seq, $row) = @$couplet;
    # Now we need to find all the features for this sequence.
    my $found;
    if ($mode eq 'protein') {
        # Protein lookup is easy.
        my $md5 = Digest::MD5::md5_hex($seq);
        $found = P3Utils::get_data($p3, feature => [['eq', 'aa_sequence_md5', $md5]], ['patric_id']);
    } else {
        # DNA lookup requires a protein translation step and post-processing to verify the sequence.
        my @seqList = compute_md5s($seq);
        my $seqString = '(' . join(',', @seqList) . ')';
        my $possibles = P3Utils::get_data($p3, feature => [['in', 'aa_sequence_md5', $seqString]], ['patric_id', 'na_sequence']);
        for my $possible (@$possibles) {
            if ($possible->[1] eq $seq) {
                push @$found, $possible->[0];
            }
        }
    }
    # Output these rows.
    for my $id (@$found) {
        P3Utils::print_cols([@$row, $id]);
    }
}


sub compute_md5s {
    my ($seq) = @_;
    my $aa = SeedUtils::translate($seq, $xtab4, 1); $aa =~ s/\*$//;
    my $md5_4 = Digest::MD5::md5_hex($aa);
    $aa = SeedUtils::translate($seq, $xtab11, 1); $aa =~ s/\*$//;
    my $md5_11 = Digest::MD5::md5_hex($aa);
    my @retVal = ($md5_4);
    if ($md5_11 ne $md5_4) {
        push @retVal, $md5_11;
    }
    return @retVal;
}