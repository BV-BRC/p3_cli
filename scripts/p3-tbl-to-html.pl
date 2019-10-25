=head1 Convert a Tab-Delimited File to an HTML Table

    p3-tbl-to-html.pl [options]

This script simply converts a P3 tab-delimited file to an HTML table. The header row is converted into an actual table header row.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are the following.

=over 4

=item nohead

If specified, it is presumed there are no headers, so there will be no header row.

=item class

If specified, style class to give to the table.

=item border

If specified, border definition to give to the table.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use CGI;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::ih_options(),
        ['nohead', 'file does not have headers'],
        ['class=s', 'if specified, style for the table'],
        ['border=s', 'if specified, border style for the table']
        );
# Open the input file.
my $ih = P3Utils::ih($opt);
# Start the table.
my %opts;
if ($opt->class) {
    $opts{class} = $opt->class;
}
if ($opt->border) {
    $opts{border} = $opt->border;
}
print CGI::start_html() . "\n";
print CGI::start_body() . "\n";
print CGI::start_table(\%opts) . "\n";
# Read the incoming headers.
if (! $opt->nohead) {
    my $line = <$ih>;
    my @cols = P3Utils::get_fields($line);
    print CGI::Tr( CGI::th(\@cols)) . "\n";
}
# Loop through the input.
while (! eof $ih) {
    my $line = <$ih>;
    my @cols = P3Utils::get_fields($line);
    print CGI::Tr( CGI::td(\@cols)) . "\n";
}
# Finish the table.
print CGI::end_table() . "\n";
print CGI::end_body() . "\n";
print CGI::end_html() . "\n";
