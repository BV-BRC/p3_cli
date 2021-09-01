=head1 Return Features From Genomes in BV-BRC

    p3-get-genome-features [options]

This script returns data for all the features in one or more genomes from the BV-BRC database. It supports standard filtering
parameters and the specification of additional columns if desired.

=head2 Parameters

There are no positional parameters.

The standard input can be overriddn using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

=over 4

=item fields

List the available fields.

=item selective

If specified, the number of features per genome is expected to be small, so a faster algorithm can be used.

=back

=head3 Example

This command is shown in the tutorial p3_CLI.html

    p3-all-genomes --eq genus,Methylobacillus | p3-get-genome-features --attr patric_id --attr product
    genome.genome_id        feature.patric_id       feature.product
    265072.11       fig|265072.11.rna.17    tRNA-Arg-CCG
    265072.11       fig|265072.11.rna.18    tRNA-Lys-TTT
    265072.11       fig|265072.11.rna.19    tRNA-Arg-ACG
    265072.11       fig|265072.11.rna.20    tRNA-Ser-GCT
    265072.11       fig|265072.11.rna.37    tRNA-Gly-GCC
    ...

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.

my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
    ['fields|f', 'Show available fields'], ['selective', 'Use batch query (only for small number of features per genome)']);
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
my $fields = ($opt->fields ? 1 : 0);
if ($fields) {
        print_usage();
            exit();
}

# Compute the output columns.
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, feature => $opt);
# Compute the filter.
my $filterList = P3Utils::form_filter($opt);
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
    my $resultList;
    if ($opt->selective) {
        $resultList = P3Utils::get_data_batch($p3, feature => $filterList, $selectList, $couplets, 'genome_id');
    } else {
        $resultList = P3Utils::get_data($p3, feature => $filterList, $selectList, genome_id => $couplets);
    }

    # Print them.
    for my $result (@$resultList) {
        P3Utils::print_cols($result, opt => $opt);
    }
}
sub print_usage {
    my $fieldList = P3Utils::list_object_fields($p3, 'feature');
    print join("\n", @$fieldList, "");
}
