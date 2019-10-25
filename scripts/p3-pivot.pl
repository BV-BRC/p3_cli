=head1 Create a Pivot Analysis of Two Columns

    p3-pivot.pl [options] col1 col2

This script analyzes the frequency distribution of the values in one column compared to the values in the
other.  Unlike L<p3-compare-cols.pl>, it can be used when the number of possible values for the second
column is very high.  Instead of a matrix, the output is in the form of a five-column table: (0) the value in
the first column, (1) the value in the second column, (2) the number of times the pair occured, (3) the
percent of rows containing the first column's value that had the second column's value, and (4) the percent
of rows containing the second column's value that had the first column's value.

=head2 Parameters

The positional parameters are the column indices (1-based) or names of the two columns.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

=cut

use strict;
use Math::Round;
use P3Utils;


# Get the command-line options.
my $opt = P3Utils::script_opts('col1 col2', P3Utils::ih_options(),
        );
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers and find the columns of interest.
my ($col1, $col2) = @ARGV;
die "Insufficient input parameters.  Two columns required." if ! defined $col2;
my ($inHeaders, $keyCols) = P3Utils::find_headers($ih, input => $col1, $col2);
# This 2D hash matrix will contain the counts.
my %counts;
# This counts the column-2 values.
my %values;
# This counts the column-1 values
my %keys;
# Loop through the input.
while (! eof $ih) {
    my $line = <$ih>;
    my ($val1, $val2) = P3Utils::get_cols($line, $keyCols);
    $counts{$val1}{$val2}++;
    $values{$val2}++;
    $keys{$val1}++
}
P3Utils::print_cols([$col1, $col2, 'count', "%$col1", "%$col2"]);
for my $key (sort keys %counts) {
    my $subCounts = $counts{$key};
    for my $value (sort keys %$subCounts) {
    	my $count = $subCounts->{$value};
    	my $pct = $count * 100;
    	my $pct2 = Math::Round::nearest(0.01, $pct / $values{$value});
    	my $pct1 = Math::Round::nearest(0.01, $pct / $keys{$key});
    	P3Utils::print_cols([$key, $value, $count, $pct1, $pct2]);
    }
}
