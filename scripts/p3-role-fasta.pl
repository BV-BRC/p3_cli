=head1 Create Fasta File for a Role

    p3-role-fasta.pl [options] roleDesc

This script takes as input a list of genome IDs and outputs a FASTA file containing the features in those
genomes possessing a specified role.

=head2 Parameters

The positional parameter is the name of the role to use.

The standard input can be overridden using the options in L<P3Utils/ih_options>.  It should contain a genome ID in
the key column identified by the L<P3Utils/col_options>.

Additional command-line options are as follows.

=over 4

=item binning

The output file is for a binning database.  The comment will be a genome ID and the name.  Implies both C<--dna> and
C<--nodups>.

=item dna

If specified, the output will be DNA sequences.  The default is protein sequences.

=item verbose

Progress messages will be displayed on STDERR.

=item noDups

If specified, roles that occur multiple times in the same genome will be discarded.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use RoleParse;
use SeedUtils;

# Get the command-line options.
my $opt = P3Utils::script_opts('roleDesc', P3Utils::col_options(), P3Utils::ih_options(),
        ['binning', 'format or use as a binning BLAST database'],
        ['dna', 'output DNA sequences'],
        ['debug|verbose|v', 'display progress on STDERR'],
        ['noDups', 'suppress sequences from genomes with multiple copies of the role'],
        );
# Get the options.
my $debug = $opt->debug;
my $noDups = $opt->nodups;
my $dna = $opt->dna;
my $binning = $opt->binning;
if ($binning) {
    $dna = 1; $noDups = 1;
}
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Determine the FASTA type.
my $seqField = ($dna ? 'na_sequence' : 'aa_sequence');
# Parse the incoming role.
my $checksum;
my ($role) = @ARGV;
if (! $role) {
    die "No role specified."
} else {
    $checksum = RoleParse::Checksum($role);
}
# Clean the role for the query.
my $role2 = P3Utils::clean_value($role);
print STDERR "Query for: $role.\n" if $debug;
# Get all the occurrences of the role.  Note we explicitly ask for genome ID and product.
my $results = P3Utils::get_data($p3, feature => [['eq', 'product', $role2]],
        ['genome_id', 'product', 'patric_id', 'genome_name', $seqField]);
print STDERR scalar(@$results) . " found for $role.\n" if $debug;
# Loop through the results.  We filter by genome (if requested) and by the role checksum, then write the output
# if it passes.
my %triples;
my ($count, $rCount) = (0, 0, 0);
for my $result (@$results) {
    my ($genomeID, $function, $fid, $gName, $seq) = @$result;
    # Reformat the genome name in binning mode.
    if ($binning) {
        $gName = join("\t", $genomeID, $gName);
    }
    # Process all the roles, looking for ours.
    my @foundR = SeedUtils::roles_of_function($function);
    for my $foundR (@foundR) {
        $rCount++;
        my $fcheck = RoleParse::Checksum($foundR);
        if ($fcheck eq $checksum) {
            push @{$triples{$genomeID}}, [$fid, $gName, $seq];
            $count++;
        }
        print STDERR "$count features kept. $rCount roles checked.\n" if $count % 5000 == 0 && $debug;
    }
}
# Now read the genomes.  For each genome, output the sequence.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Get all the genomes.
my $gCount = 0;
my $genomes = P3Utils::get_col($ih, $keyCol);
print STDERR scalar(@$genomes) . " genomes read from input.\n" if $debug;
for my $genome (@$genomes) {
    my $triplets = $triples{$genome};
    if (! $triplets) {
        print STDERR "WARNING: no sequence found for $genome.\n" if $debug;
    } elsif (scalar(@$triplets) > 1 && $noDups) {
        print STDERR "WARNING: duplicate sequences found for $genome.\n" if $debug;
    } else {
        $gCount++;
        for my $triplet (@$triplets) {
            print ">$triplet->[0] $triplet->[1]\n$triplet->[2]\n";
        }
    }
}
print STDERR "$gCount genomes output.\n" if $debug;