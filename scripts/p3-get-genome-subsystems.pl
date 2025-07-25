=head1 Return Subsystem Data for Genomes

    p3-get-genome-subsystems [options]

This script returns data about the subsystem rows for the genomes identified in the standard input. It supports standard filtering
parameters and the specification of additional columns if desired.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

=over 4

=item fields

Display the available field names.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
    ['fields|f', 'Show available fields']);

# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
my $fields = ($opt->fields ? 1 : 0);
if ($fields) {
    print_usage();
    exit();
}
# Compute the output columns.
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, subsystemItem => $opt);
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
    my $resultList = P3Utils::get_data($p3, subsystemItem => $filterList, $selectList, genome_id => $couplets);
    # Print them.
    for my $result (@$resultList) {
        P3Utils::print_cols($result);
    }
}

sub print_usage {
    my $fieldList = P3Utils::list_object_fields($p3, 'subsystemItem');
    print join("\n", @$fieldList, "");
}
