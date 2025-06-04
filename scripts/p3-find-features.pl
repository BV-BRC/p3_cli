=head1 Find Features By Filtering on a Field

    p3-find-features.pl [options] keyName

This script finds features based on the value in one of several feature-identifying fields (other than C<patric_id>).
It provides standard filtering parameters to otherwise limit the output. (So, for example, you can require that the
features output belong only to a specific genome using C<--eq genome_id>.)

=head2 Parameters

The positional parameter is the name of the field used to match the incoming keys. The following fields are permitted.

=over 4

=item refseq_locus_tag

The locus tag from REFSEQ

=item protein_id

The REFSEQ protein ID.

=item gene

The common gene name (e.g. C<rpoA>).

=item gene_id

The standard gene number.

=item aa_sequence_md5

The protein sequence MD5 code.

=item product

The functional assignment of the feature. A standard SOLR-type substring match is used.

=back

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

=over 4

=item keyNames

Rather than processing the input, list the valid key names.

=back

=head3 Example

    This command is shown in the tutorial p3_common_tasks.html

    p3-echo coaA | p3-find-features --attr patric_id,product --eq genome_id,210007.7 gene

    p3-echo coaA | p3-find-features --attr patric_id,product gene
    id  feature.patric_id   feature.product
    coaA    fig|996634.5.peg.916    Pantothenate kinase (EC 2.7.1.33)
    coaA    fig|944560.4.peg.377    Pantothenate kinase (EC 2.7.1.33)
    coaA    fig|992133.3.peg.4201   Pantothenate kinase (EC 2.7.1.33)
    coaA    fig|992141.3.peg.4166   Pantothenate kinase (EC 2.7.1.33)
    ...

=cut

use strict;
use P3DataAPI;
use P3Utils;

# unCommon keys are type 2, common type 1. This influences batching.
use constant KEYS => { gene => 2, gene_id => 1, refseq_locus_tag => 1, protein_id => 2, aa_sequence_md5 => 2, product => 2 };

# Get the command-line options.
my $opt = P3Utils::script_opts('keyName', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
        ['keyNames|keynames|keys', 'list key field names']
        );
if ($opt->keynames) {
    # Here the user just wants a key name list.
    print map { "$_\n" } keys %{KEYS()};
} else {
    # Validate the field name.
    my ($keyName) = @ARGV;
    if (! $keyName) {
        die "No key field name specified.";
    } elsif (! KEYS->{$keyName}) {
        die "Key field $keyName not supported.";
    }
    # Get access to BV-BRC.
    my $p3 = P3DataAPI->new();
    # Compute the output columns.
    my ($selectList, $newHeaders) = P3Utils::select_clause($p3, feature => $opt);
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
        my $resultsL;
        # Process according to whether the key is common (2) or uncommon (1).
        if (KEYS->{$keyName} == 2) {
            $resultsL = P3Utils::get_data($p3, feature => $filterList, $selectList, $keyName, $couplets);
        } else {
            $resultsL = P3Utils::get_data_batch($p3, feature => $filterList, $selectList, $couplets, $keyName);
        }
        for my $result (@$resultsL) {
            P3Utils::print_cols($result);
        }
    }
}
