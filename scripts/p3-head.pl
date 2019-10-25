=head1 Return First Few Lines of the Input File

    p3-head.pl [options]

This script returns the header line plus the first few data lines of the standard input stream. It is similar to the Unix B<head>
command, but works on Windows.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are as follows.

=over 4

=item nohead

The file has no headers.

=item lines

The number of data lines to display. If there is a header line, it is not counted in this number. The default is C<10>.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;


# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::ih_options(),
        ['nohead', 'file has no headers'],
        ['lines|n=i', 'number of data lines to display', { default => 10 }]
        );
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders) = P3Utils::process_headers($ih, $opt, 1);
# Echo the headers.
if (! $opt->nohead) {
    P3Utils::print_cols($outHeaders);
}
# Compute the number of lines to print.
my $count = $opt->lines;
# Loop through the input.
while (! eof $ih && $count) {
    my $line = <$ih>;
    $count--;
    print $line;
}