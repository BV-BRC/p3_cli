=head1 Return All Taxonomic Groupings in BV-BRC

    p3-all-genomes [options]

This script returns the IDs of all the taxonomic groupings in the BV-BRC database. It supports standard filtering
parameters and the specification of additional columns if desired.

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
    my $fieldList = P3Utils::list_object_fields($p3, 'taxonomy');
    print join("\n", @$fieldList, "");
} else {
    # Compute the output columns. Note we configure this as an ID-centric method.
    my ($selectList, $newHeaders) = P3Utils::select_clause($p3, taxonomy => $opt, 1);
    # Compute the filter.
    my $filterList = P3Utils::form_filter($p3, $opt);
    if (! @$filterList) {
        # We must always have a filter, so add a dummy here.
        push @$filterList, ['ne', 'taxon_id', 0];
    }
    # Write the headers.
    P3Utils::print_cols($newHeaders);
    # Process the query.
    my $results = P3Utils::get_data($p3, taxonomy => $filterList, $selectList);
    # Print the results.
    for my $result (@$results) {
        P3Utils::print_cols($result, opt => $opt);
    }
}
