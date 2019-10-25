use Data::Dumper;
use strict;
use warnings;
use P3DataAPI;
use P3Utils;
use P3Signatures;
use File::Copy::Recursive;

=head1 Compute Related Protein Families Based on Clusters

     p3-related-by-clusters --gs1 Genome_set_1
                            --gs2 Genome_set_2
                            --sz1 Sample_size_for_gs1
                            --sz2 Sample_size_for_gs2
                            --iterations Number_random_sample_iterations
                            --family fam_type
                            --Output Directory

This tool takes as input two genome sets.  These will often be

    gs1    genomes for a specific species (e.g., Streptococcus pyogenes)
    gs2    genomes from the same genus, but different species

The tool picks random subsets of gs1 and gs2, computes signature families for
each pair of picks, then computes clusters of these families for each pick.

It does a set of iterations, saving the signature clusters for each iteration.

After running the set of iterations, it computes the number of times each pair
of signature families were in signature clusters.

It outputs the pairs of co-ocurring signature families, along with the
signature clusters computed for each iteration.

The output goes to a created directory.  Within that directory, the subdirectory

    CS

will contain the cluster signatures for each iteraion, and

    related.signature.families

is set to the predicted functionally-coupled pairs of families:

    [occurrence-count,family1,family2] sorted into descending order based on count.

Each CS/n file contains entries of the form

          famId1 peg1 func1
          famId2 peg2 func2
          .
          .
          .
          //

=head2 Parameters

There are no positional parameters.

Standard input is not used.

The additional command-line options are as follows.

=over 4

=item gs1

Genome set 1: a file containing genome ids in the first column
These genomes will be the onces containing signature families and clusters.

=item gs2

Genome set 2: a file containing genome ids in the first column

=item sz1

For each iteration pick a sample of sz1 genomes from gs1

=item sz2

For each iteration pick a sample of sz2 genomes from gs2

=item iterations

run this many iterations of random subsets of gs1 and gs2

=item output

a created directory that will contain the output

=item family

Type of protein family-- local, global, or figfam.

=back

=cut

my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
                                          ["gs1=s","a file containing genome set 1", { required => 1 }],
                                          ["gs2=s","a file containing genome set 2", { required => 1 }],
                                          ["sz1=i","size of sample from gs1", { default => 20 }],
                                          ["sz2=i","size of sample from gs2", { default => 20 }],
                                          ["min=f","min fraction of gs1 to be signature family", { default => 1 }],
                                          ["max=f","max fraction of gs2 to be signature family", { default => 0 }],
                                          ["iterations|n=i", "number of iterations to run", { default => 10 }],
                                          ["output|o=s","output directory", { required => 1 }]);
my $gs1 = $opt->gs1;
my $gs2 = $opt->gs2;
my $sz1 = $opt->sz1;
my $sz2 = $opt->sz2;
my $min = $opt->min;
my $max = $opt->max;
my $iterations = $opt->iterations;
my $outD = $opt->output;
if (! -d $outD) {
    File::Copy::Recursive::pathmk($outD);
}
my $csDir = "$outD/CS";
if (! -d $csDir) {
    File::Copy::Recursive::pathmk($csDir);
}
File::Copy::Recursive::pathempty($csDir);
# Get the two genome sets.
my $ih;
open($ih, "<$gs1") || die "Could not open $gs1: $!";
my (undef, $keycol1) = P3Utils::process_headers($ih, $opt);
my $genomes1 = P3Utils::get_col($ih, $keycol1);
close $ih; undef $ih;
open($ih, "<$gs2") || die "Could not open $gs2: $!";
my (undef, $keycol2) = P3Utils::process_headers($ih, $opt);
my $genomes2 = P3Utils::get_col($ih, $keycol2);
my %pairCounts;
my $i;

#
# Filter genome groups to remove genomes that do not appear in PATRIC.
#

my $api = P3DataAPI->new();
my $names = $api->genome_name($genomes1);
my $ids = [];
for my $gid (@$genomes1)
{
    if ($names->{$gid})
    {
        push(@$ids, $gid);
    }
    else
    {
        warn "Genome $gid does not appear in PATRIC\n";
    }
}
$genomes1 = $ids;
$ids = [];
$names = $api->genome_name($genomes2);
for my $gid (@$genomes2)
{
    if ($names->{$gid})
    {
        push(@$ids, $gid);
    }
    else
    {
        warn "Genome $gid does not appear in PATRIC\n";
    }
}
$genomes2 = $ids;

for ($i=0; ($i < $iterations); $i++)
{
    print "Processing iteration $i.\n";
    # Choose random items from each genome list.
    my $subset1 = PickGenomes($genomes1, $sz1);
    my $subset2 = PickGenomes($genomes2, $sz2);
    # Get the family signatures.
    my $familyHash = P3Signatures::Process($subset1, $subset2, $min, $max);
    # Compute the peg info.
    my $families = [keys %$familyHash];
    print scalar(@$families) . " families found.\n";
    undef $familyHash;
    my $pegList = P3Signatures::PegInfo($families, 200, $subset1);
    undef $families;
    # Compute the clusters.
    my $clusterSets = P3Signatures::Clusters($pegList, 2000);
    # Process and output the clusters.
    open(my $oh, ">$csDir/$i") || die "Could not open cluster $i output file: $!";
    for my $cluster (@$clusterSets) {
        # Separate the families.
        my @familyCluster = map { $_->[1] } @$cluster;
        # Write the cluster.
        for my $tuple (@$cluster) {
            print $oh join("\t", @$tuple) . "\n";
        }
        print $oh "//\n";
        # Count the pairs.
        my $n = (scalar @familyCluster);
        # Loop through the families, processing pairs.
        for (my $i = 0; $i < $n; $i++) {
            my $family = $familyCluster[$i];
            # Process the pairs.
            for (my $j = $i + 1; $j < $n; $j++) {
                my $family2 = $familyCluster[$j];
                if ($family2 ne $family) {
                    my $pair = join("\t", sort($family, $family2));
                    $pairCounts{$pair}++;
                }
            }
        }
    }
}
print "Processing pair counts.\n";
# Write out the pair counts.
my @pairs = sort { $pairCounts{$b} <=> $pairCounts{$a} } keys %pairCounts;
open(my $ph, ">$outD/related.signature.families") || die "Could not open main output file: $!";
for my $pair (@pairs) {
    print $ph "$pair\t$pairCounts{$pair}\n";
}
close $ph;

# Choose random genomes from a list.
sub PickGenomes {
    my ($genomeList, $count) = @_;
    # Get a safe copy of the list.
    my @copy = @$genomeList;
    # Loop through it, shuffling.
    my $n = scalar @copy;
    if ($count > $n) {
        $count = $n;
    }
    for (my $i = 0; $i < $count; $i++) {
        my $j = int(rand($n));
        ($copy[$i], $copy[$j]) = ($copy[$j], $copy[$i]);
    }
    splice @copy, $count;
    return \@copy;
}
