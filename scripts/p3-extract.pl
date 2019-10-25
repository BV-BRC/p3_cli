=head1 Select Columns from an Input File

    p3-extract [options] col1 col2 ... colN

This script extracts the specified columns from a tab-delimited file.

=head2 Parameters

The positional parameters are the numbers or names of the columns to include in the output. The column numbers
are 1-based, and the column names are taken from the header record of the input file.

The standard input may be overridden by the command-line options given in L<P3Utils/ih_options>.

The following additional options are supported.

=over 4

=item all

Output all the columns. This simply copies the file.

=item reverse

Output all the columns not listed, rather than the listed columns.

=item nohead

If specified, the file is presumed to have no headers.

=back

=cut

use strict;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('col1 col2 ... colN', P3Utils::ih_options(), ['nohead', 'file has no headers'],
        ['all', 'output all columns'],
        ['reverse|v', 'output all columns not specified'],
        );
# Open the input file.
my $ih = P3Utils::ih($opt);
# Check for All-mode.
if ($opt->all) {
    # Here we simply echo the file.
    while (! eof $ih) {
        my $line = <$ih>;
        print $line;
    }
} else {
    # Here we are reformatting the file. Get the column identifiers.
    my @cols = @ARGV;
    die "No columns specified." if (! @cols);
    # Process the headers.
    my ($inHeaders) = P3Utils::process_headers($ih, $opt, 'keyless');
    # Compute the column indices.
    my @idxes = map { P3Utils::find_column($_, $inHeaders) } @cols;
    # In reverse mode, eliminate the columns listed rather than keeping only them.
    if ($opt->reverse) {
        my %wrong = map {$_ => 1} @idxes;
        my $n = scalar(@$inHeaders) - 1;
        @idxes = grep { ! $wrong{$_} } 0 .. $n;
    }
    # Compute the output headers.
    if (! $opt->nohead) {
        my @outHeaders = map { $inHeaders->[$_] } @idxes;
        # Write out the headers.
        P3Utils::print_cols(\@outHeaders);
    }
    # Loop through the input.
    while (! eof $ih) {
        my @row =  P3Utils::get_cols($ih, \@idxes);
        P3Utils::print_cols(\@row);
    }
}