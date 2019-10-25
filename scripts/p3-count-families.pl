=head1 Count Protein Families in Genomes

    p3-count-families.pl [options]

This script will count the number of occurrences of each protein family found in the specified genomes. The output will contain the family
ID, the associated product, the number of total occurrences, and the number of genomes containing the family.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>, and is used to specify the genomes of interest.
The column containing the genome ID can be specified using the options in L<P3Utils/col_options>. The following additional command-line
options are supported.

=over 4

=item singly

If specified, only single-occurrence families will be counted.

=item type

The type of protein family-- C<local>, C<global>, or C<figfam>. The default is C<global>.

=item verbose

Write status messages to STDERR.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use Stats;

use constant FAMILY_FIELD => { local => 'plfam_id', global => 'pgfam_id', figfam => 'figfam_id' };

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(),
        ['singly|s', 'only count singly-occurring family instances'],
        ['type=s', 'type of protein family (local, global, figfam)', { default => 'global' }],
        ['verbose|v', 'write status messages to STDERR']
        );
my $stats = Stats->new();
my $debug = $opt->verbose;
my $strict = $opt->singly;
if ($debug) {
    if ($strict) {
        print STDERR "Strict mode used.\n";
    } else {
        print STDERR "Normal mode used.\n";
    }
}
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Write the output headers.
if (! $opt->nohead) {
    P3Utils::print_cols(['family', 'product', 'proteins', 'genomes']);
}
# Compute the family ID field.
my $type = $opt->type;
my $fieldName = FAMILY_FIELD->{$type};
if (! $fieldName) {
    die "Invalid family type $type.";
}
print STDERR "Selecting family type $type with field $fieldName.\n" if $debug;
# This will track the protein counts for each family.
my %pCount;
# This will track the genome counts for each family.
my %gCount;
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    $stats->Add(batchIn => 1);
    for my $genome (map { $_->[0] } @$couplets) {
        $stats->Add(genomeIn => 1);
        # Get all the families for this genome.
        print STDERR "Processing $genome.\n" if $debug;
        my $resultList = P3Utils::get_data($p3, feature => [['eq', 'genome_id', $genome]], ['patric_id', $fieldName]);
        my %count;
        for my $result (@$resultList) {
            my ($fid, $family) = @$result;
            if (! $family) {
                $stats->Add(noFamily => 1);
            } else {
                $count{$family}++;
                $stats->Add(featureFound => 1);
            }
        }
        # Count the families.
        for my $family (keys %count) {
            my $k = $count{$family};
            if ($strict && $k > 1) {
                $stats->Add(notSingle => 1);
            } else {
                $gCount{$family}++;
                $pCount{$family} += $k;
                $stats->Add(familyCounted => 1);
            }
        }
    }
}
# Now we've counted all the genomes. Get the family products.
my $fCount = scalar keys %pCount;
print STDERR "Computing products for $fCount families.\n" if $debug;
my $productList = P3Utils::get_data_keyed($p3, family => [], ['family_id', 'family_product'], [keys %pCount]);
my %product;
for my $productItem (@$productList) {
    my ($family, $product) = @$productItem;
    if ($product) {
        $product{$family} = $product;
        $stats->Add(productFound => 1);
    }
}
# Sort the counts and write the output.
print STDERR "Sorting output.\n" if $debug;
my @sorted = sort { $pCount{$b} <=> $pCount{$a} } keys %pCount;
print STDERR "Printing output.\n" if $debug;
for my $family (@sorted) {
    my $product = $product{$family} // '<unknown>';
    P3Utils::print_cols([$family, $product, $pCount{$family}, $gCount{$family}]);
    $stats->Add(familyOut => 1);
}
print STDERR "All done.\n" . $stats->Show() if $debug;