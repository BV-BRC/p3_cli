=head1 Filter a File Against Contents of a Second File

    p3-file-filter.pl [options] filterFile filterCol1 filterCol2 ...

Filter the standard input using the contents of a file. The output will contain only those rows in the input file whose key value
matches a value from the specified column of the specified filter file. To have the output contain only those rows in the input
file that do NOT match, use the C<--reverse> option. This is similar to L<p3-merge.pl>, except that script operates on whole
lines instead of a set of key fields.

=head2 Parameters

The positional parameters are the name of the filter file and the indices (1-based) or names of the key columns in the filter file.
If the latter parameter is absent, the value of the C<--col> parameter will be used (same name or index as the input file).

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are the following.

=over 4

=item reverse

Instead of only keeping input records that match a filter record, only keep records that do NOT match.

=item col

The name or index of the key column in the input file. If more than one value is specified, the columns are matched one-for-one
with the corresponding filter file columns.

=back

=head3 Example

This command is shown in the tutorial p3-common-tasks.html;

p3-file-filter --reverse --col=feature.role aRoles.tbl feature.role &lt;cRoles.tbl

feature.role    count
2,3-dihydroxybenzoate-AMP ligase (EC 2.7.7.58) of siderophore biosynthesis  33
2-octaprenyl-3-methyl-6-methoxy-1,4-benzoquinol hydroxylase (EC 1.14.13.-)  1
2-pyrone-4,6-dicarboxylic acid hydrolase (EC 3.1.1.57)  14
23S ribosomal RNA rRNA prediction is too short  1
...

=cut

use strict;
use P3Utils;


# Get the command-line options.
my $opt = P3Utils::script_opts('filterFile filterCol1 filterCol2 ... filterColN', P3Utils::ih_options(),
        ['reverse|invert|v', 'only keep non-matching records'],
        ['nohead', 'file has no headers'],
        ['col|c=s@', 'input file key columns', { default => [0] }]
        );
# Get the filter parameters.
my ($filterFile, @filterCol) = @ARGV;
# Compute the columns.
my $inCols = $opt->col;
if (! scalar @filterCol) {
    @filterCol = @$inCols;
}
if (! $filterFile) {
    die "No filter file specified.";
} elsif (! -f $filterFile) {
    die "Filter file $filterFile invalid or not found.";
} elsif (scalar @$inCols ne scalar @filterCol) {
    die "Filter column count does not match key column count.";
}
# Open the filter file.
open(my $fh, '<', $filterFile) || die "Could not open filter file: $!";
# Read its headers and compute the key columns.
my ($filterHeaders, $filterCols);
if ($opt->nohead) {
    $filterCols = [ map { $_ - 1 } @filterCol ];
} else {
    ($filterHeaders, $filterCols) = P3Utils::find_headers($fh, filterFile => @filterCol);
}
# Create a hash of the acceptable field values.
my %filter;
while (! eof $fh) {
    my $key = join("\t", P3Utils::get_cols($fh, $filterCols));
    $filter{$key} = 1;
}
# Release the memory for the filter file stuff.
close $fh;
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCols);
if ($opt->nohead) {
    $keyCols = [map { $_ - 1 } @$inCols];
} else {
    ($outHeaders, $keyCols) = P3Utils::find_headers($ih, inputFile => @$inCols);
}
# Write the output headers.
if (! $opt->nohead) {
    P3Utils::print_cols($outHeaders);
}
# Determine the mode.
my $reverse = $opt->reverse;
# Loop through the input.
while (! eof $ih) {
    my $line = <$ih>;
    my @fields = P3Utils::get_fields($line);
    my $key = join("\t", P3Utils::get_cols(\@fields, $keyCols));
    if ($filter{$key} xor $reverse) {
        print $line;
    }
}
