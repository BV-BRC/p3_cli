=head1 Genus/Species List

    p3-genus-species.pl [options]

This script produces a two-column table listing each genus/species pair in the BV-BRC database along with how many genomes in each.
Pseudo-species (those that are numbers, or begin with C<sp.>) are not included. Candidatus genera are also skipped. The idea is to
produce an orthodox list suitable for an exhaustive species-by-species analysis of some sort.

=head2 Parameters

There are no positional parameters.

=cut

use strict;
use P3DataAPI;
use P3Utils;


# Get the command-line options.
my $opt = P3Utils::script_opts('');
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
# Form the full header set and write it out.
P3Utils::print_cols(['genus', 'species', 'count']);
# This two-dimensional hash will accumulate all the genus/species data.
my %counts;
# Get all of the genomes.
my $results = P3Utils::get_data($p3, genome => [['eq', 'genome_id', '*'], ['eq', 'public', 1]], ['genome_name', 'genome_id']);
print STDERR "Genomes retrieved.\n";
my $count = 0;
# Loop through them.
for my $result (@$results) {
    my ($genome_name) = @$result;
    if (++$count % 1000 == 0) {
        print STDERR "$count genomes processed.\n";
    }
    if ($genome_name) {
        my ($genus, $species) = split ' ', $genome_name;
        # Remove punctuation from the genus.
        $genus =~ s/\W//g;
        # Insure this is a real one.
        if (! ($genus =~ /^[a-z]/ || $genus =~ /Candidatus/ || $genus =~ /^SAR/)) {
            # Insure this is a real species.
            if (! ($species =~ /sp\./)) {
                $counts{$genus}{$species}++;
            }
        }
    }
}
# Output the results.
for my $genus (sort keys %counts) {
    my $countsH = $counts{$genus};
    for my $species (sort keys %$countsH) {
        P3Utils::print_cols([$genus, $species, $countsH->{$species}]);
    }
}