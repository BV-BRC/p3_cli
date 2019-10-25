=head1 Compute Gap Between Feature Pairs

    p3-feature-gap [options] <featurePairFile

This script reads in a list of feature pairs and computes the gap between the features. If the features are on different
contigs or belong to different genomes, the gap will be listed as 2 billion. This behavior can be overridden with a
command-line option.

=head2 Parameters

There are no positional parameters.

The standard input can be specified using L<P3Utils/ih_options>. The input column can be specified using L<P3Utils/col_options>.
The following additional command-line options can be specified.

=over 4

=item inf

Value to return for an infinite gap (different contigs or genomes). The default is C<2000000000>.

=item col2

Name or index of the column containing the ID of the second feature. The default is C<-1>, which is the second-to-last column.

=back

=head3 Example

p3-echo -t f1.patric_id -t f2.patric_id "fig|1302.21.peg.966" "fig|1302.21.peg.1019" | p3-feature-gap

f1.patric_id    f2.patric_id    gap
fig|1302.21.peg.966 fig|1302.21.peg.1019    55253

=cut

    use strict;
    use P3DataAPI;
    use P3Utils;
    use BasicLocation;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(),
    ['inf=i', 'infinite-gap value', { default => 2000000000 }],
    ['col2|C=s', 'name or index of column containing second feature ID', { default => -1 }],
 );
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Get the standard input.
my $ih = P3Utils::ih($opt);
# Read the header line and compute the key column (feature 1).
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Get the second key column (feature 2).
my $k2Col = P3Utils::find_column($opt->col2, $outHeaders);
if (! $opt->nohead) {
    # Add a header for the gap output.
    push @$outHeaders, 'gap';
    # Print the header line.
    P3Utils::print_cols($outHeaders);
}
# Now we pull in the feature pairs.
while (! eof $ih) {
    my $line = <$ih>;
    my @fields = P3Utils::get_fields($line);
    my @fids = @fields[$keyCol, $k2Col];
    my $fidString = '(' . join(",", @fids) . ')';
    # Get the location data for this feature pair.
    my $resultList = P3Utils::get_data($p3, feature => [['in', 'patric_id', $fidString]], ['genome_id', 'sequence_id', 'start', 'end']);
    # If we can't compute a gap, we use the infinite value.
    my $gap = $opt->inf;
    if (scalar @$resultList >= 2) {
        # We have the two features. Get their data.
        my ($g1, $s1, $l1, $r1) = @{$resultList->[0]};
        my ($g2, $s2, $l2, $r2) = @{$resultList->[1]};
        # Verify the contigs.
        if ($g1 eq $g2 && $s1 eq $s2) {
            # Here we are on the same contig.
            if ($l1 <= $l2) {
                # Here feature 1 is to the left.
                if ($r1 >= $l2) {
                    # This is an overlap situation.
                    $gap = 0;
                } else {
                    # Here the features are distinct.
                    $gap = $l2 - $r1;
                }
            } elsif ($l1 >= $r2) {
                # Here feature 1 is to the right.
                $gap = $l1 - $r2;
            } else {
                # Here the features overlap.
                $gap = 0;
            }
        }
    }
    # Append the gap to the output row.
    push @fields, $gap;
    P3Utils::print_cols(\@fields);
}