=head1 Statistically Analyze Numerical Values

    p3-stats.pl [options] statCol

This script divides the input into groups by the key column and analyzes the values found in a second column (specified by the
parameter). It outputs the mean, standard deviation, minimum, maximum, and count.

=head2 Parameters

The positional parameter is the name of the column to be analyzed. It must contain only numbers.

The standard input can be overriddn using the options in L<P3Utils/ih_options>.

Additional command-line options are the following.

=over 4

=item col

The index (1-based) or name of the key column used to divide the file into groups.  The default is C<0>, indicating the
last column.  If C<none> is specified, then all of the rows are put into a single group.

=item nohead

If specified, then it is assumed there are no headers.

=cut

use strict;
use P3DataAPI;
use P3Utils;


# Get the command-line options.
my $opt = P3Utils::script_opts('statCol', P3Utils::ih_options(),
        ['col|c=s', 'grouping column (or "none")', { default => 0 }],
        ['nohead', 'input has no headers']
        );
# Open the input file.
my $ih = P3Utils::ih($opt);
# Get the target column spec.
my ($statCol) = @ARGV;
if (! defined $statCol) {
    die "No target column specified."
}
# Read the incoming headers and find the key and target columns.
my $colName = 'key';
my ($keyCol, $targetCol);
if ($opt->nohead) {
    # Here there is no header line.
    $targetCol = $statCol - 1;
    if ($opt->col ne 'none') {
        $keyCol = $opt->col - 1;
    }
} else {
    my $line = <$ih>;
    my @headers = P3Utils::get_fields($line);
    $targetCol = P3Utils::find_column($statCol, \@headers);
    if ($opt->col ne 'none') {
        $keyCol = P3Utils::find_column($opt->col, \@headers);
        $colName = $headers[$keyCol];
    }
    # Form the full header set and write it out.
    my @outHeaders = ($colName, qw(count average min max stdev));
    P3Utils::print_cols(\@outHeaders);
}
# This is our tally hash. For each key value, it will contain [count, sum, min, max, square-sum].
my %tally;
# Loop through the input.
while (! eof $ih) {
    my $line = <$ih>;
    my @fields = P3Utils::get_fields($line);
    my $value = $fields[$targetCol];
    my $key = (defined $keyCol ? $fields[$keyCol] : 'all');
    if (! exists $tally{$key}) {
        $tally{$key} = [1, $value, $value, $value, $value*$value];
    } else {
        my $tallyL = $tally{$key};
        $tallyL->[0]++;
        $tallyL->[1] += $value;
        if ($value < $tallyL->[2]) {
            $tallyL->[2] = $value;
        }
        if ($value > $tallyL->[3]) {
            $tallyL->[3] = $value;
        }
        $tallyL->[4] += $value * $value;
    }
}
# Now loop through the tally hash, producing output.
for my $key (sort keys %tally) {
    my ($count, $sum, $min, $max, $sqrs) = @{$tally{$key}};
    my $avg = $sum / $count;
    my $stdev = sqrt($sqrs/$count - $avg*$avg);
    P3Utils::print_cols([$key, $count, $avg, $min, $max, $stdev]);
}
