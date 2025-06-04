=head1 Find Genomes By Filtering on a Field

    p3-find-genomes.pl [options] keyName

This script finds features based on the value in one of several genome-identifying fields (other than C<genome_id>).
It provides standard filtering parameters to otherwise limit the output. (So, for example, you can require that the
genomes output belong only to a specific genus using C<--eq genus>.)

=head2 Parameters

The positional parameter is the name of the field used to match the incoming keys. The following fields are permitted.

=over 4

=item genome_name

The genome name.

=item genbank_accessions

The genbank accession number.

=item sra_accession

The SRA accession number.

=item assembly_accession

The assembly accession number.

=back

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

=over 4

=item keyNames

Rather than processing the input, list the valid key names.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Common keys are type 2, uncommon type 1. This influences batching.
use constant KEYS => { genome_name => 1, genbank_accessions => 1, assembly_accession => 1, sra_accession => 1 };

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
        my $resultsL;
        # Process according to whether the key is common (2) or uncommon (1).
        if (KEYS->{$keyName} == 2) {
            $resultsL = P3Utils::get_data($p3, genome => $filterList, $selectList, $keyName, $couplets);
        } else {
            $resultsL = P3Utils::get_data_batch($p3, genome => $filterList, $selectList, $couplets, $keyName);
        }
        for my $result (@$resultsL) {
            P3Utils::print_cols($result);
        }
    }
}
