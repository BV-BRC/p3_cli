=head1 Compute Co-Occurrences of Proteins

    p3-co-occur.pl [options] catFile

This script will compute the number of co-occurrences of specified protein categories. The most common category is role (product), but it is also
possible to specify protein families.

=head2 Parameters

The positional parameter is the name of the file containing the category names. The file should be tab-delimited with the names in the first column.
If no file is specified, all recognizable category values will be counted. This can be problematic if the categories are roles.

The standard input can be overridden using the options in L<P3Utils/ih_options>. The standard input will contain the genome IDs. The options in
L<P3Utils/col_options> can be used to configure headers and the column containing the genome IDs. In addition, the following options are
supported.

=over 4

=item gap

The maximum gap distance for two proteins to be considered physically close. The default is C<2000>.

=item type

The type of category-- currently C<role>, C<ecnum>, or C<family>. The default is C<role>.

=item verbose

If specified, status messages will be written to the standard error output.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use Category;
use Stats;
use Math::Round;
use Category::Role;
use Category::Family;
use Category::EC;

$| = 1;
my $stats = Stats->new();
# Get the command-line options.
my $opt = P3Utils::script_opts('catFile', P3Utils::col_options(), P3Utils::ih_options(),
        ['gap|g=i', 'maximum gap distance', { default => 2000 }],
        ['type|t=s', 'type of category for clustering', { default => 'role' }],
        ['verbose|v', 'write status messages on STDERR']
        );
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Get the options.
my $gap = $opt->gap;
my $type = $opt->type;
my $nohead = $opt->nohead;
my $debug = $opt->verbose;
print STDERR "Using gap $gap for category $type.\n" if $debug;
# Check the category file.
my ($catFile) = @ARGV;
if (! $catFile) {
    $catFile = '*';
    print STDERR "All categories will be counted.\n" if $debug;
} elsif (! -s $catFile) {
    die "Category file $catFile is missing or empty.";
}
# Create the category object.
print STDERR "Initializing category definitions.\n" if $debug;
my $catHelper = Category->new($p3, $type, $catFile, $nohead);
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Write out the new headers.
if (! $opt->nohead) {
    P3Utils::print_cols(['Cat1', 'Cat2', 'Count', 'Percent']);
}
# These hashes will count the number of close occurrences and total occurrences for each category pair.
my (%close, %total);
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    $stats->Add(batchIn => 1);
    for my $genome (map { $_->[0] } @$couplets) {
        print STDERR "Processing $genome.\n" if $debug;
        # Get all the singly-occurring category features. For each feature, the hash will return
        # the location, keyed by category.
        my $catH = $catHelper->get_cats($genome);
        # Sort the categories so that each pair always appears in lexical order.
        my @cats = sort keys %$catH;
        # We loop through each possible pair, which is a quadratic operation on the number of categories.
        while (@cats) {
            my $cat1 = shift @cats;
            my $loc1 = $catH->{$cat1};
            $stats->Add(genomeCat => 1);
            for my $cat2 (@cats) {
                my $pairID = "$cat1\t$cat2";
                my $loc2 = $catH->{$cat2};
                $total{$pairID}++;
                $stats->Add(pairCat => 1);
                my $dist = $loc1->Distance($loc2);
                if (defined $dist && $dist <= $gap) {
                    $stats->Add(closeCat => 1);
                    $close{$pairID}++;
                }
            }
        }
    }
}
# Now we have everything. It is time to form output.
print STDERR "Sorting output.\n" if $debug;
my @pairs = sort { $close{$b} <=> $close{$a} } keys %close;
print STDERR scalar(@pairs) . " co-occurring pairs found.\n" if $debug;
for my $pair (@pairs) {
    my ($cat1, $cat2) = map { $catHelper->id_to_name($_) } split /\t/, $pair;
    my $count = $close{$pair};
    my $pct = Math::Round::nearest(0.1, $count * 100 / $total{$pair});
    P3Utils::print_cols([$cat1, $cat2, $count, $pct]);
    $stats->Add(pairOut => 1);
}
print STDERR "All done.\n" . $stats->Show() if $debug;
