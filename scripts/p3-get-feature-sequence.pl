=head1 Create A FASTA File of Feature Sequences

    p3-get-feature-sequence [options] < feature-ids

This script takes as input a table of feature IDs and outputs a FASTA file of the feature sequences. The FASTA comment will be the
feature annotation (product).

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

The command-line options are those in L<P3Utils/col_options> (to choose the input column) plus the following.

=over 4

=item protein

Output amino acid sequences (the default).

=item dna

Output DNA sequences (mutually exclusive with C<protein>).

=back

=cut


use strict;
use P3Utils;
use Data::Dumper;
use P3DataAPI;
use gjoseqlib;

my $opt = P3Utils::script_opts('', P3Utils::ih_options(), P3Utils::col_options(),
        ['mode' => hidden => { one_of => [['protein', 'feature protein FASTA'],
                                          ['dna', 'feature DNA FASTA']],
                                          default => 'protein' }],
                              );
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Compute the field list.
my $selectList = ['patric_id', 'product', ($opt->mode eq 'dna' ? 'na_sequence' : 'aa_sequence')];
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    # Get the output rows for these input couplets.
    my $keys = [map { $_->[0] } @$couplets];
    my $resultList = P3Utils::get_data_keyed($p3, feature => [], $selectList, $keys, 'patric_id');
    # Print them.
    for my $result (@$resultList) {
        my ($id, $comment, $seq) = @$result;
        if ($seq) {
            $seq = uc $seq;
            print ">$id $comment\n$seq\n";
        }
    }
}
