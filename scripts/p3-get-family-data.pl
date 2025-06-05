=head1 Return Data From Protein Families in BV-BRC

    p3-get-family-data [options]

This script returns information about each given family. It supports standard filtering
parameters and the specification of additional columns if desired.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

=over 4

=item fields

Show available fields.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
        ['fields', 'list the available field names'],
);
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
if ($opt->fields) {
    my $fieldList = P3Utils::list_object_fields($p3, 'family');
    print join("\n", @$fieldList, "");
} else {
    # Compute the output columns.
    my ($selectList, $newHeaders) = P3Utils::select_clause($p3, family => $opt);
    # Compute the filter.
    my $filterList = P3Utils::form_filter($p3, $opt);
    # Open the input file.
    my $ih = P3Utils::ih($opt);
    # Read the incoming headers.
    my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
    # Form the full header set and write it out.
    if (! $opt->nohead) {
        push @$outHeaders, @$newHeaders;
        P3Utils::print_cols($outHeaders);
    }
    # Loop through the input.
    while (! eof $ih) {
        my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
        # Get the output rows for these input couplets.
        my $resultList = P3Utils::get_data_batch($p3, family => $filterList, $selectList, $couplets);
        # Print them.
        for my $result (@$resultList) {
            P3Utils::print_cols($result, opt => $opt);
        }
    }
}