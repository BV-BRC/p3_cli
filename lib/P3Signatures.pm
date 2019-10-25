#
# This is a SAS component.
#

#
# Copyright (c) 2003-2015 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#


package P3Signatures;

    use strict;
    use warnings;
    use P3Utils;
    use P3DataAPI;

=head1 Compute Signature Families

This module computes genetic signature families. It takes as input two sets of genomes and searches for
families that are common in the first and uncommon in the second. The output is a hash mapping family IDs
to occurrence counts.

=head2 Public Methods

=head3 Process

    my $familyHash = P3Signatures::Process(\@gs1, \@gs2, $min_in, $max_out, $jobObject, $comment);

Compute the protein families that distinguish genome set 1 from genome set 2.

=over 4

=item gs1

Reference to a list of the IDs of the first genomes. The signature families must occur in most of these genomes.

=item gs2

Reference to a list of the IDs of the second genomes. The signature families must occur in few of these genomes.

=item min_in

The fraction of genomes in set 1 that must contain a signature family. A value of C<1> means all genomes must contain it.

=item max_out

The fraction of genomes in set 2 that may contain a signature family. A value of C<0> means no genomes can contain it.

=item jobObject (optional)

If specified, an object for reporting progress. It must support a I<Progress> method that takes text messages.

=item comment (optional)

Optional comment to add to each progress message.

=item RETURN

Returns a hash mapping the ID of each signature family to a 3-tuple consisting of (0) the number of genomes in set 1 containing
the family, (1) the number of genomes in set 2 containing the family, and (2) the functional role of the family.

=back

=cut

sub Process {
    my ($gs1, $gs2, $min_in, $max_out, $jobObject, $comment) = @_;
    # Prepare the comment.
    $comment = (! $comment ? '' : "  $comment");
    # Get access to PATRIC.
    my $p3 = P3DataAPI->new();
    # Copy both sets of genomes to a hash.
    my %gs1 = map { $_ => 1 } @$gs1;
    my %gs2 = map { $_ => 1 } @$gs2;
    if ($jobObject) {
        $jobObject->Progress(scalar(@$gs1) . " genomes in group 1, " . scalar(@$gs2) . " in group 2.");
    }
    # This hash will count the number of times each family is found in the sets.
    # It is keyed by family ID, and each value is a sub-hash with keys "in" and "out"
    # pointing to counts.
    my %counts;
    # This hash maps families to their annotation product.
    my %families;
    # This tracks our progress.
    my $gCount = 0;
    my $gTotal = (scalar @$gs1) + (scalar @$gs2);
    # This hash maps "in" to a list of all the genomes in the set, and "out" to a list of all
    # the genomes not in the set.
    my %genomes = (in => [keys %gs1], out => [keys %gs2]);
    for my $type (qw(in out)) {
        my $genomeL = $genomes{$type};
        for my $genome (@$genomeL) {
            $gCount++;
            # Get all of the protein families in this genome. A single family may appear multiple times.
            if ($jobObject) {
                $jobObject->Progress("Reading features for $genome ($gCount of $gTotal).$comment");
            }
            my $resultList = P3Utils::get_data($p3, feature => [['eq', 'genome_id', $genome], ['eq', 'pgfam_id', '*']], ['pgfam_id', 'product']);
            # Save the families and count the unique ones.
            my %uniques;
            for my $result (@$resultList) {
                my ($fam, $product) = @$result;
                $families{$fam} = $product;
                if (! $uniques{$fam}) {
                    $counts{$fam}{$type}++;
                    $uniques{$fam} = 1;
                }
            }
        }
    }
    # This will be our return hash.
    my %retVal;
    # Determine which families qualify as signatures.
    my $szI = scalar keys %gs1;
    my $szO = scalar keys %gs2;
    foreach my $fam (keys(%counts)) {
        my $x1 = $counts{$fam}->{in} // 0;
        my $x2 = $counts{$fam}->{out} // 0;
        if ((($x2/$szO) <= $max_out) && (($x1/$szI) >= $min_in)) {
            $retVal{$fam} = [$x1, $x2, $families{$fam}];
        }
    }
    # Return the hash.
    return \%retVal;
}

=head3 PegInfo

    my $pegList = P3Signatures::PegInfo(\@families, \@genomes);

Return the peg information list for a set of families (usually signature families). For each family,
we list all the features in the family belonging to genomes in the list. For each feature, we include
the location information and the functional assignment.

=over 4

=item families

Reference to a list of protein family IDs.

=item batchSize

Batch size for requests to PATRIC.

=item genomes (optional)

Reference to a list of genome IDs. Only features from these genomes will be returned. If omitted, all features
will be returned.

=item RETURN

Returns a reference to a list of 7-tuples. Each tuple consists of (0) a family ID, (1) the
feature's functional assignment, (3) the feature ID, (4) the feature's contig ID,
(5) the starting offset, (6) the ending offset, and (7) the strand (C<+> or C<->).

=back

=cut

sub PegInfo {
    my ($families, $batchSize, $genomes) = @_;
    # This will contain the results.
    my @retVal;
    # Get access to PATRIC.
    my $p3 = P3DataAPI->new();
    # Compute the fields to select.
    my @selectList = qw(product patric_id accession start end strand);
    # This will contain the filter list: either empty or a genome filter.
    my @filterList;
    if ($genomes) {
        # Compute the genome filter.
        my $gFilter = ['in', 'genome_id', '(' . join(',', @$genomes) . ')'];
        push @filterList, $gFilter;
    }
    # Loop through the hash, creating couplets and submitting them in batches for feature data.
    my @couplets;
    for my $fam (@$families) {
        if (scalar(@couplets) > $batchSize) {
            my $batch = P3Utils::get_data_batch($p3, feature => \@filterList, \@selectList, \@couplets, 'pgfam_id');
            push @retVal, @$batch;
            @couplets = ();
        }
        push @couplets, [$fam, [$fam]];
    }
    if (@couplets) {
        my $batch = P3Utils::get_data_batch($p3, feature => \@filterList, \@selectList, \@couplets, 'pgfam_id');
        push @retVal, @$batch;
    }
    # Return the results.
    return \@retVal;
}

=head3 Clusters

    my $pegClusters = P3Signatures::Clusters($pegInfo, $distance);

Compute the clusters from a peg information list. A cluster is a group of pegs in which each
is less than a certain distance from the next on the same contig. The distance is measured midpoint to midpoint.

The normal use of this method is to process the output of L</PegInfo>; however, it can process any list of
feature tuples in which the last 5 elements are a feature ID and the feature's location (contig, start, end,
strand). In this way it can be used to compute clusters in other applications.

=over 4

=item pegInfo

A reference to a list of tuples. Each tuple consists of a constant number of information fields followed by
a feature ID and location information-- contig ID, starting location, ending location, and strand. If the
input is the list produced by L</PegInfo>, then there are two information fields-- family ID and function.

=item distance

The minimum acceptable distance between peg midpoints for them to be considered part of a cluster.

=item RETURN

Returns a reference to a list of clusters. Each cluster is a list of N-tuples, one per feature in the cluster,
consisting of the feature ID and the initial elements from that feature's pegInfo entry. If the input is
the list produced by L</PegInfo>, each feature tuple will be (0) feature ID, (1) family ID, and (2) function.

=back

=cut

sub Clusters {
    my ($pegInfo, $distance) = @_;
    # This hash maps each contig ID to a list of [$pegID,$midpoint,@info] tuples.
    my %contigPegs;
    # Loop through the pegs, filling the hash.
    for my $pegTuple (@$pegInfo) {
        my @pegDatum = @$pegTuple;
        # Extract the information fields.
        my @info;
        while ((scalar @pegDatum) > 5) {
            push @info, shift @pegDatum;
        }
        # Get the peg ID and location.
        my ($peg, $contig, $start, $end, $strand) = @pegDatum;
        # Add the genome ID to the contig ID.
        if ($peg =~ /^fig\|(\d+\.\d+)\./) {
            $contig = "$1:$contig";
        }
        my $midPoint = ($start + $end) / 2;
        push @{$contigPegs{$contig}}, [$midPoint, $peg, @info];
    }
    # We will stuff the clusters in this hash, keyed by cluster length.
    my %clusters;
    # Loop through the contigs, forming clusters.
    for my $contig (keys %contigPegs) {
        my $contigPegList = $contigPegs{$contig};
        my @pegList = sort { $a->[0] <=> $b->[0] } @$contigPegList;
        # Start the first cluster with the first peg.
        my ($point, @info) = @{shift @pegList};
        my @cluster = \@info;
        for my $pegDatum (@pegList) {
            # Get this peg's midpoint.
            my $newPoint = shift @$pegDatum;
            # Are we still in the cluster?
            if ($newPoint - $point > $distance) {
                # No, output the cluster. We only output clusters of 2 or more,
                # and we store a safe copy of the list.
                my $len = scalar @cluster;
                if ($len >= 2) {
                    push @{$clusters{$len}}, [@cluster];
                }
                # Restart the cluster.
                @cluster = ();
            }
            # Add this peg to the current cluster.
            push @cluster, $pegDatum;
            $point = $newPoint;
        }
        # Check for a residual cluster.
        my $len = scalar @cluster;
        if ($len >= 2) {
            push @{$clusters{$len}}, [@cluster];
        }
    }
    # Output the clusters in order.
    my @retVal;
    for my $len (sort { $b <=> $a } keys %clusters) {
        my $clusterList = $clusters{$len};
        push @retVal, @$clusterList;
    }
    # Return the list of clusters.
    return \@retVal;
}


1;
