use strict;
use warnings;
use P3Utils;
use P3DataAPI;

=head1 Format Raw Data for Conversion to HTML.

     p3-format-results -d DataDirectory > condensed Output

This tool takes as input an Output Directory created by p3-related-by-clusters.
It produces a condensed text for of the computed clusters.

These text-forms can be run through p3-aggregates-to-html to get versions
that can be perused by a biologist.

The input directory contains a list of protein family pairs in a file called C<related.signature.families>.  Each
record consists of three tab-delimited columns-- (0) first family ID, (1) second family ID, and (2) count.

For each pair, we want to create an output group that shows the pairing (and the intervening features) for
each genome.  Each such group consists of the following.

=over 4

=item coupling_header

A header consisting of the string C<////>.

=item count

Immediately after the header, a tab-delimited line containing (0) the first family ID, (1) the second family ID, and
(2) the occurrence count.

=item genome_header

Following the count, there are one or more genome groups.  Each starts with a header containing C<###>, a tab, and the
genome name.

=item feature

Inside the genome group there are one or more feature records. The feature record is tab-delimited, and consists of (0)
a feature ID, (1) a protein family ID, and (2) a functional assignment.

=back

The B<count> records are taken directly from C<related.signature.families>.  The B<feature> records are taken from
the iteration files in the data directory.  These files are found in the subdirectory <CS>, and each genome group
is separated by a C<//> line.

Our strategy will be to read in all the genome groups and track the genome and the protein family set for each.
When we process a protein family pairing, we will output all of the genome groups that have both protein families
present.

=head2 Parameters

There are no positional parameters.

Standard input is not used.

The additional command-line options are as follows.

=over 4

=item d DataDirectory

=back

=cut

my ($opt, $helper) = P3Utils::script_opts('',["d=s","a directory created by p3-related-by-clusters", { required => 1 }]);
my $inD = $opt->d;
# Connect to PATRIC.
my $p3 = P3DataAPI->new();
# We start by reading in the genome clusters.  This hash contains the genome IDs found.
my %genomes;
# This list contains all the clusters.  Each will be identified by its position in this list.  The cluster will be
# represented by its genome ID and then the list of detail records.
my @clusters;
my @clusterGenomes;
# This hash maps each protein family ID to a list of cluster numbers.
my %families;
# The genome cluster files are in the CS directory.
opendir(my $dh, "$inD/CS") || die "Could not open cluster directory for $inD: $!";
my @clusterFiles = grep { -s "$inD/CS/$_" } readdir $dh;
closedir $dh;
for my $clusterFile (@clusterFiles) {
    open(my $ih, '<', "$inD/CS/$clusterFile") || die "Could not open cluster file $clusterFile: $!";
    while (! eof $ih) {
        my ($cluster, $genome, $families) = readCluster($ih);
        # Save the genome ID.
        $genomes{$genome} = "Unknown genome $genome";
        # Attach the cluster to the families.  "scalar @clusterFiles" is the index the cluster will have in the list.
        for my $family (@$families) {
            push @{$families{$family}}, scalar @clusters;
        }
        # Finally, save the cluster in the list.
        push @clusters, $cluster;
        push @clusterGenomes, $genome;
    }
    close $ih;
}
# Next, we get the genome names from PATRIC.
read_names(\%genomes);
# Now we have all our support structures. We read through the related-families file to build the output.
open(my $ih, '<', "$inD/related.signature.families") || die "Could not open related-families file: $!";
while (! eof $ih) {
    # Get the next pairing.
    my $line = <$ih>;
    chomp $line;
    my ($fam1, $fam2, $count) = split /\t/, $line;
    # Get the intersection of the cluster lists for the families.
    my %f2List = map { $_ => 1 } @{$families{$fam2}};
    my @matching = grep { $f2List{$_} } @{$families{$fam1}};
    if (scalar @matching) {
        # We have clusters to show, so start an output group.
        print "////\n";
        print "$line\n";
        for my $clusterIdx (@matching) {
            # Get the cluster and its genome ID.
            my $cluster = $clusters[$clusterIdx];
            my $genome = $clusterGenomes[$clusterIdx];
            # Output the group.
            print "###\t$genomes{$genome}\n";
            for my $line (@$cluster) {
                print $line;
            }
        }
    }
}


##
## Read a cluster from the input file.  The input file handle is the parameter.  The output is the cluster list,
## the genome ID, and a list of the family IDs found.
sub readCluster {
    my ($ih) = @_;
    # These will be the return values.
    my $genomeID;
    my @cluster;
    my %families;
    # We get the first line to parse out the genome ID.
    my $line = <$ih>;
    if ($line =~ /(\d+\.\d+)/) {
        $genomeID = $1;
    }
    # We will loop until we hit a marker or EOF.
    while (defined $line && substr($line, 0, 2) ne '//') {
        my ($fid, $family, $function) = split /\t/, $line;
        $families{$family} = 1;
        push @cluster, $line;
        $line = <$ih>;
    }
    return (\@cluster, $genomeID, [keys %families]);
}

##
## Read the genome names from PATRIC.  The parameter is the genome hash.  We will replace the placeholders in there
## with the real names.
##
sub read_names {
    my ($genomesH) = @_;
    my $results = P3Utils::get_data_keyed($p3, genome => [], ['genome_id', 'genome_name'], [keys %$genomesH]);
    for my $result (@$results) {
        my ($genomeID, $genomeName) = @$result;
        $genomesH->{$genomeID} = $genomeName;
    }
}
