=head1 Write Data to Standard Output

    p3-echo [options] value1 value2 ... valueN

This script creates a tab-delimited output file containing the values on the command line. If a single header (C<--title> option)
is specified, then the output file is single-column. Otherwise, there is one column per header. So, for example


    p3-echo --title=genome_id 83333.1 100226.1

produces

    genome_id
    83333.1
    100226.1

However, the command

    p3-echo --title=genome_id --title=name 83333.1 "Escherichia coli" 100226.1 "Streptomyces coelicolor"

produces

    genome_id   name
    83333.1     Escherichia coli
    100226.1    Streptomyces coelicolor


=head2 Parameters

The positional parameters are the values to be output.

The command-line options are as follows.

=over 4

=item title

The value to use for the header line. If more than one value is specified, then the output file is multi-column. If
omitted, the single column header C<id> is assumed.

=item nohead

If this option is specified, then no column headers are output. The value is the number of columns desired.

=item data

Specifies a file name. The records in the file will be added to the end of the output. Use this option to put headers
onto a headerless file.

=back

=cut

use strict;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('value1 value2 ... valueN',
        ['title|header|hdr|t=s@', 'header value(s) to use in first output record', { default => ['id'] }],
        ['nohead=i', 'file has no header and the specified number of columns'],
        ['data=s', 'input data file']);
# Get the titles.
my $cols;
if ($opt->nohead) {
    # User does not want a header line.
    $cols = $opt->nohead;
} else {
    my $titles = $opt->title;
    # Compute the column count.
    $cols = scalar @$titles;
    P3Utils::print_cols($titles);
}
my @values = @ARGV;
# We will accumulate the current line in here.
my @line;
for my $value (@values) {
    push @line, $value;
    if (scalar(@line) >= $cols) {
        P3Utils::print_cols(\@line);
        @line = ();
    }
}
if (scalar @line) {
    # Here there is leftover data. Pad the line.
    while (scalar(@line) < $cols) {
        push @line, '';
    }
    P3Utils::print_cols(\@line);
}
if ($opt->data) {
    # Here the user wants data lines from an input file.
    open(my $ih, '<', $opt->data) || die "Could not open data file: $!";
    while (! eof $ih) {
        my $line = <$ih>;
        print $line;
    }
}
