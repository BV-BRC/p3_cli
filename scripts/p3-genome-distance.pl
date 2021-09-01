=head1 Compute the Distance Between a Specified Genome and Genomes in a File

    p3-genome-distance.pl [options] baseGenome

This script uses protein families to compute genome distance.  A single genome is chosen as the I<base genome>.  We run
through all the protein families and compute the kmers in common for each family member in the other genomes.  The
I<similarity score> is the total number of kmers in common.  The higher the similarity score, the closer the genome is
to the base.  The number produced is not scaled, so it can only be used for relative comparison.

=head2 Parameters

The positional parameter is the ID of the base genome.

The standard input should contain the IDs of the genomes to compare.  The standard input can be overridden using the options in L<P3Utils/ih_options>
and the options in L<P3Utils/col_options> can be used to specify the column containing the genome IDs.  If the base genome is
found in the input, it will be ignored.

The standard output will contain the genome IDs and their distances.  The following additional options are supported.

=over 4

=item dna

Use DNA kmers instead of protein kmers.

=item kmer

The kmer size to use.  The default is C<8> for proteins and C<16> for DNA.

=item verbose

If specified, progress messages will be displayed on the standard error output.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use RepGenome;
use Stats;

# Get the command-line options.
my $opt = P3Utils::script_opts('baseGenome', P3Utils::col_options(), P3Utils::ih_options(),
        ['dna', 'use DNA kmers'],
        ['kmer|kmerSize|K|k=i', 'kmer size'],
        ['verbose|debug|v', 'show progress on STDERR']
        );
my $stats = Stats->new();
# Compute the main options.
my $debug = $opt->verbose;
my $kmer = $opt->kmer || ($opt->dna ? 15 : 8);
# Determine the input field to use for the sequences.
my $mode = ($opt->dna ? 'na_sequence' : 'aa_sequence');
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
# Get the base genome ID.
my ($baseGenome) = @ARGV;
if (! $baseGenome) {
    die "No base genome ID specified.";
} elsif (! ($baseGenome =~ /^\d+\.\d+$/)) {
    die "Invalid base genome ID $baseGenome.";
}
# Open the input file.
print STDERR "Reading input file.\n" if $debug;
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Form the full header set and write it out.
if (! $opt->nohead) {
    P3Utils::print_cols(['id', 'name', 'kmer_similarity', 'protein_similarity']);
}
# Read the genome IDs.
my $genomes = P3Utils::get_col($ih, $keyCol);
my @others = grep { $_ ne $baseGenome } @$genomes;
my @allGenomes = ($baseGenome, @others);
print STDERR scalar(@others) . " genomes read from input.\n" if $debug;
# Get the genome names.
print STDERR "Reading genome names from BV-BRC.\n" if $debug;
my $gList = P3Utils::get_data_keyed($p3, genome => [], ['genome_id', 'genome_name'], \@allGenomes, 'genome_id');
# Now we create our result hash.  For each genome, it will map the id to [id, name, score, famCount].  The score for the base will be
# the total number of possible kmers in the genome.
my %gMap;
for my $gEntry (@$gList) {
    my ($genome, $name) = @$gEntry;
    $gMap{$genome} = [$genome, $name, 0, 0];
}
# Verify we found everything.
my @errors;
for my $genome (@allGenomes) {
    if (! $gMap{$genome}) {
        push @errors, $genome;
    }
}
if (@errors) {
    die "Missing genomes in BV-BRC: " . join(", ", @errors);
}
# Now we get the proteins for the base genome.  The return hash maps each protein family ID to a single sequence.  For a family with
# multiple sequences, the longest one is kept.
my $name = $gMap{$baseGenome}[1];
print STDERR "Reading proteins for base genome $baseGenome: $name.\n" if $debug;
my $protMap = get_genome_proteins($baseGenome, $p3, $stats, $mode);
# Loop through the base genome proteins, creating the RepGenome objects.
print STDERR "Analyzing protein families for base genome $baseGenome.\n" if $debug;
my ($score, $fams) = (0, 0);
my %baseProts;
for my $prot (keys %$protMap) {
    $stats->Add(baseFamily => 1);
    my $seq = $protMap->{$prot};
    my $kHash = RepGenome->new($baseGenome, prot => $seq, K => $kmer);
    $baseProts{$prot} = $kHash;
    # Add the number of kmers found to the score.
    $score += $kHash->kCount;
    $fams++;
}
# Store the score in the output hash.
$stats->Add(baseKmers => $score);
$stats->Add(baseFams => $fams);
$gMap{$baseGenome} = [$baseGenome, $name, $score, $fams];
print STDERR "$score kmers and $fams families found in base genome.\n";
# Now we process each remaining genome.
for my $genome (@others) {
    # Get the proteins for this new genome.
    $name = $gMap{$genome}[1];
    print STDERR "Reading proteins for $genome: $name.\n" if $debug;
    $protMap = get_genome_proteins($genome, $p3, $stats, $mode);
    print STDERR "Analyzing protein families for $genome.\n" if $debug;
    # Loop through the base protein families, scoring.
    ($score, $fams) = (0, 0);
    for my $prot (keys %$protMap) {
        my $kHash = $baseProts{$prot};
        if ($kHash) {
            # Here the family exists in the base genome.
            $fams++;
            $score += $kHash->check_genome($protMap->{$prot});
        }
    }
    # Store the score in the output hash.
    $stats->Add(otherScore => $score);
    $stats->Add(otherFams => $fams);
    $gMap{$genome} = [$genome, $name, $score, $fams];
}
# Now we produce the output.
print STDERR "Sorting results.\n";
@allGenomes = sort { $gMap{$b}[2] <=> $gMap{$a}[2] } keys %gMap;
for my $genome (@allGenomes) {
    P3Utils::print_cols($gMap{$genome});
}
print STDERR "All done.\n" . $stats->Show() if $debug;

## Protein reader subroutine.
sub get_genome_proteins {
    my ($genome, $p3, $stats, $sCol) = @_;
    # This hash maps each protein family ID to its longest sequence.
    my %retVal;
    # Ask for all the proteins in this genome.  We return the family ID and the sequence (the type of which is determined by
    # the $sCol parameter).
    my $resultList = P3Utils::get_data($p3, feature => [['eq', 'genome_id', $genome]], ['patric_id', 'pgfam_id', $sCol]);
    for my $result (@$resultList) {
        my (undef, $fam, $seq) = @$result;
        $stats->Add(protRead => 1);
        if (! $retVal{$fam} || length($retVal{$fam}) < length($seq)) {
            $retVal{$fam} = $seq;
            $stats->Add(protKept => 1);
        }
    }
    # Return the result hash.
    return \%retVal;
}