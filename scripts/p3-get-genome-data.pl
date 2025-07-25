=head1 Return Data From Genomes in BV-BRC

    p3-get-genome-data [options]

This script returns data about the genomes identified in the standard input. It supports standard filtering
parameters and the specification of additional columns if desired.

=head2 Parameters

There are no positional parameters.

The standard input can be overriddn using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

=over 4

=item fields

List the available field names.

=back


=head3 Example

This command is shown in the tutorial p3_CLI.html

p3-all-genomes --eq genome_name,Streptomyces | p3-get-genome-data --attr genome_name --attr contigs --attr genome_length

    genome.genome_id    genome.genome_name  genome.contigs  genome.genome_length
    284037.4    Streptomyces sporocinereus strain OsiSh-2   125 10242506
    67257.17    Streptomyces albus subsp. albus strain NRRL F-4371  307 9246299
    68042.5 Streptomyces hygroscopicus subsp. hygroscopicus strain NBRC 16556   133 10141569
    68042.6 Streptomyces hygroscopicus subsp. hygroscopicus strain NBRC 13472   680 9464604
    1395572.3   Streptomyces albulus PD-1   425 9340057
    ...

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
    ['fields|f', 'Show available fields'], ['keyField=s', 'Use the given field as a lookup key']);

# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
my $fields = ($opt->fields ? 1 : 0);
if ($fields) {
    print_usage();
    exit();
}
# Compute the output columns.
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, genome => $opt);
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
    my $resultList = P3Utils::get_data_batch($p3, genome => $filterList, $selectList, $couplets, $opt->keyField);
    # Print them.
    for my $result (@$resultList) {
        P3Utils::print_cols($result, opt => $opt);
    }
}

sub print_usage {
    my $fieldList = P3Utils::list_object_fields($p3, 'genome');
    print join("\n", @$fieldList, "");
}
