=head1 Search for Serology Data

    p3-find-serology-data [options]

This script returns serology data from the BV_BRC database. It supports standard filtering
parameters and the specification of alternate columns if desired.  At least one filtering
parameter MUST be specified.

=head2 Parameters

There are no positional parameters.

The command-line options are those given in L<P3Utils/data_options> plus the following.

=over 4

=item fields

List the names of the available fields.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(),
        ['fields|f', 'show available fields']);
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
if ($opt->fields) {
    my $fieldList = P3Utils::list_object_fields($p3, 'serology');
    print join("\n", @$fieldList, "");
} else {
    # Compute the output columns.
    my ($selectList, $newHeaders) = P3Utils::select_clause($p3, serology => $opt);
    # Compute the filter.
    my $filterList = P3Utils::form_filter($opt);
    if (! @$filterList) {
        die "At least one filtering parameter is requred.";
    }
    # Write the headers.
    P3Utils::print_cols($newHeaders);
    # Process the query.
    my $results = P3Utils::get_data($p3, serology => $filterList, $selectList);
    # Print the results.
    for my $result (@$results) {
        P3Utils::print_cols($result, opt => $opt);
    }
}
