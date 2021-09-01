=head1 Return AMR Data For Genomes in BV-BRC

    p3-get-genome-drugs [options]

This script returns the anti-microbial resistance data about the genomes identified in the standard
input. It supports standard filtering parameters and the specification of additional columns if desired.

=head2 Parameters

There are no positional parameters.

The standard input can be overriddn using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

=over 4

=item fields

List the fields of the table.

=item resistant

Filter for drugs to which the genome is resistant.

=item susceptible

Filter for drugs to which the genome is susceptible.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
    ['resistant|resist|strong', 'filter for drugs to which the genome is resistant'],
    ['susceptible|suscept|weak', 'filter for drugs to which the genome is susceptible'],
    ['fields|f', 'Show available fields']);

# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
my $fields = ($opt->fields ? 1 : 0);
if ($fields) {
    print_usage();
    exit();
}
# Compute the output columns.
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, genome_drug => $opt);
# Compute the filter.
my $filterList = P3Utils::form_filter($opt);
# Add the special filters.
if ($opt->resistant) {
    push @$filterList, ['eq', 'resistant_phenotype', 'resistant'];
}
if ($opt->susceptible) {
    push @$filterList, ['eq', 'resistant_phenotype', 'susceptible'];
}
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
    my $resultList = P3Utils::get_data($p3, genome_drug => $filterList, $selectList, genome_id => $couplets);
    # Print them.
    for my $result (@$resultList) {
        P3Utils::print_cols($result, opt => $opt);
    }
}

sub print_usage {
    my $fieldList = P3Utils::list_object_fields($p3, 'genome_drug');
    print join("\n", @$fieldList, "");
}
