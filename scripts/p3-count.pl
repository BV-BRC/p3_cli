=head1 Count Distinct Values

    p3-count.pl [options]

This simple script outputs the number of distinct values in the specified input column.

=head2 Parameters

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/col_options> to specify the column to count.

=cut

use strict;
use P3DataAPI;
use P3Utils;


# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(),
        );
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Form the full header set and write it out.
if (! $opt->nohead) {
    P3Utils::print_cols(['count']);
}
# The keys will be counted in here.
my %keys;
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    for my $couplets (@$couplets) {
        my ($key) = $couplets->[0];
        $keys{$key} = 1;
    }
}
my $count = scalar keys %keys;
P3Utils::print_cols([$count]);
