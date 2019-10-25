=head1 Choose Random Rows from an Input File

    p3-pick [options] count

This script randomly selects the specified number of rows from the input and copies
them to the output.

=head2 Parameters

The single positional parameter is the number of rows to pick.

The standard input may be overridden by the command-line options given in L<P3Utils/ih_options>. The following additional
options may be specified.

=over 4

=item nohead

Input file has no headers.

=back

=cut

use strict;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('count', P3Utils::ih_options(),
        ['nohead', 'file has no headers']);
# Get the desired row count.
my ($count) = @ARGV;
if (! defined $count) {
    die "No count specified.";
} elsif ($count =~ /\D/) {
    die "Count not numeric.";
} elsif (! $count) {
    die "Count cannot be zero.";
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Copy the header line.
my $line;
if (! $opt->nohead) {
    my $line = <$ih>;
    print $line;
}
# Read in all the data lines.
my @lines = <$ih>;
# Compute the number of lines from which we are selecting.
my $nlines = scalar @lines;
# Only proceed if we need to remove lines.
if ($nlines > $count) {
    # Create a list of array indices.
    my @index = 0 .. ($nlines - 1);
    # Shuffle the list.
    for (my $i = 0; $i < $count; $i++) {
        my $j = int(rand($nlines));
        ($index[$i], $index[$j]) = ($index[$j], $index[$i]);
    }
    # Truncate the list to the desired length and sort it.
    splice @index, $count;
    @index = sort { $a <=> $b } @index;
    # Create an output list.
    my @output = map { $lines[$_] } @index;
    # Copy it back over the original so we write it out.
    @lines = @output;
}
# Output the lines.
for my $line (@lines) {
    print $line;
}
