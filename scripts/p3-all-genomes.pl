=head1 Return All Genomes in PATRIC

    p3-all-genomes [options]

This script returns the IDs of all the genomes in the PATRIC database. It supports standard filtering
parameters and the specification of additional columns if desired.

=head2 Parameters

There are no positional parameters.

The command-line options are those given in L<P3Utils/data_options> plus the following.

=over 4

=item fields

List the names of the available fields.

=item public

Only include public genomes. If this option is NOT specified and you are logged in (via L<p3-login.pl>), your own private
genomes will also be included in the output.

=item private

Only include private genomes. If this option is specified and you are not logged in, there will be no output. It is mutually
exclusive with public.

=back

You can peruse

     https://github.com/PATRIC3/patric_solr/blob/master/genome/conf/schema.xml

to gain access to all of the supported fields.  There are quite a

few, so do not panic.  You can use something like

    p3-all-genomes -a genome_name -a genome_length -a contigs -a genome_status

to get some commonly sought fields.

=head3 Example

This command is used in several tutorials, see p3_CLI.html for example;

    p3-all-genomes --eq genome_name,Streptomyces --attr genome_id --attr genome_name

This example retrieves the id and genome name for all genomes having Streptomyces in their name.

    genome.genome_id    genome.genome_name
    284037.4    Streptomyces sporocinereus strain OsiSh-2
    67257.17    Streptomyces albus subsp. albus strain NRRL F-4371
    68042.5 Streptomyces hygroscopicus subsp. hygroscopicus strain NBRC 16556
    68042.6 Streptomyces hygroscopicus subsp. hygroscopicus strain NBRC 13472
    1395572.3   Streptomyces albulus PD-1
    ...

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(),
        ['fields|f', 'show available fields'],
        ['public', 'only include public genomes'],
        ['private', 'only include private genomes']);
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
if ($opt->fields) {
    my $fieldList = P3Utils::list_object_fields($p3, 'genome');
    print join("\n", @$fieldList, "");
} else {
    # Compute the output columns. Note we configure this as an ID-centric method.
    my ($selectList, $newHeaders) = P3Utils::select_clause($p3, genome => $opt, 1);
    # Compute the filter.
    my $filterList = P3Utils::form_filter($opt);
    # Check for public-only and private-only.
    if ($opt->public) {
        push @$filterList, ['eq', 'public', 1];
    } elsif ($opt->private) {
        push @$filterList, ['eq', 'public', 0];
    } elsif (! @$filterList) {
        # We must always have a filter, so add a dummy here.
        push @$filterList, ['ne', 'genome_id', 0];
    }
    # Write the headers.
    P3Utils::print_cols($newHeaders);
    # Process the query.
    my $results = P3Utils::get_data($p3, genome => $filterList, $selectList);
    # Print the results.
    for my $result (@$results) {
        P3Utils::print_cols($result, opt => $opt);
    }
}
