=head1 Select Rows from an Input File

    p3-match [options] value

This script extracts rows from a tab-delimited file based on the value in a specified column. Optionally,
it can create a second output file containing the rejected rows.

=head2 Parameters

The single positional parameter is the value on which to match. If the value is numeric, the match will be
exact. If it is non-numeric, then the match will be case-insensitive, and a record will match if any subsequence of
the words in the key column match the words in the input value.

The standard input may be overridden by the command-line options given in L<P3Utils/ih_options>.

The command-line options are those in L<P3Utils/col_options> (for selection of the key column) plus the
following.

=over 4

=item reverse

If specified, only rows that do not match will be output.

=item discards

If specified, the name of a file to contain the records that do not match.

=item exact

If specified, even a non-numeric match will be exact.

=item nonblank

If specified, all non-blank column values match and the positional parameter is ignored.

=back

=cut

use strict;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('match-value', P3Utils::ih_options(), P3Utils::col_options(),
        ['reverse|invert|v', 'output non-matching records'],
        ['discards=s', 'name of file to contain discarded records'],
        ['nonblank', 'match all nonblank column values'],
        ['exact', 'always match exactly, case-sensitive']
        );
# Get the reverse-flag.
my $reverse = ($opt->reverse ? 1 : 0);
# Get the match options.
my $nonblank = $opt->nonblank;
my $exact = $opt->exact // 0;
# Get the match pattern.
my ($pattern) = @ARGV;
if ($nonblank) {
    $pattern = undef;
} elsif (! defined $pattern) {
    die "No match pattern specified.";
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Process the headers and compute the key column index.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Check for a discard file.
my $dh;
if ($opt->discards) {
    open($dh, '>', $opt->discards) || die "Could not open discard file: $!";
    P3Utils::print_cols($outHeaders, oh => $dh);
}
# Write out the headers.
if (! $opt->nohead) {
    P3Utils::print_cols($outHeaders);
}
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    # Loop through the couplets.
    for my $couplet (@$couplets) {
        my ($key, $row) = @$couplet;
        # Perform a match. If we have a match and are NOT reversing, or we do NOT have a match and are reversing, we output
        # (XOR condition).
        if (P3Utils::match($pattern, $key, exact => $exact) ^ $reverse) {
            P3Utils::print_cols($row);
        } elsif ($dh) {
            P3Utils::print_cols($row, oh => $dh);
        }
    }
}