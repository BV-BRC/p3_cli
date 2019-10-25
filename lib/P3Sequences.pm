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


package P3Sequences;

    use strict;
    use warnings;
    use P3Utils;
    use SeedUtils;

=head1 Utilities for Managing PATRIC DNA Sequences

This object manages a list of PATRIC DNA sequences.  The main data structure is a hash mapping sequence IDs to DNA sequences.
The sequence will be the forward strand, and the regions containing features will be in upper case; the rest in lower case.

The fields in this object are as follows.

=over 4

=item p3

The <P3DataAPI> object for accessing the PATRIC database.

=item seqH

Reference to a hash mapping each sequence ID to its annotated DNA sequence.

=item seqL

Reference to a hash mapping each sequence ID to its length.

=back

=head2 Special Methods

=head3 new

    my $p3seqs = P3Sequences->new($p3);

Create a new, blank P3 sequences object.

=over 4

=item p3

The L<P3DataAPI> object for accessing the PATRIC database.

=back

=cut

sub new {
    my ($class, $p3) = @_;
    # Create the object.
    my $retVal = { p3 => $p3, seqH => {}, seqL => {} };
    # Bless and return it.
    bless $retVal, $class;
    return $retVal;
}


=head2 Public Manipulation Methods

=head3 GetSequence

    my $dna = $p3seqs->GetSequence($seqID);

Return the DNA for a specified sequence.  The sequence itself will be stored in the internal hash.  Regions containing features will be
in upper case, the rest in lower case.

=over 4

=item seqID

The ID of the sequence to return.

=item RETURN

Returns the requested DNA sequence, for the requested strand, with the feature-containing regions in upper case.  If the sequence does
not exist, it will return C<undef>.

=back

=cut

sub GetSequence {
    my ($self, $seqID) = @_;
    # Get the sequence hash.
    my $seqH = $self->{seqH};
    # Insure we have the sequence in it.
    $self->_verify_seq($seqID);
    # Return the sequence.
    my $retVal = $seqH->{$seqID};
    return $retVal;
}

=head3 SeqLen

    my $length = $p3seqs->SeqLen($seqID);

Return the length of the specified sequence.  The sequence itself will be stored in the internal hash and prepared for later use.

=over 4

=item seqID

The ID of the sequence whose length is desired.

=item RETURN

Returns the length of the sequence in base pairs.  If the sequence does not exist, will return C<undef>.

=back

=cut

sub SeqLen {
    my ($self, $seqID) = @_;
    # Get the length hash.
    my $seqL = $self->{seqL};
    # Insure we have the sequence in it.
    $self->_verify_seq($seqID);
    # Return the sequence length.
    my $retVal = $seqL->{$seqID};
    return $retVal;
}

=head3 FeatureLocations

    my $fidHash = $p3seqs->FeatureLocations(\@fids);

Return a hash mapping each feature to its location in its genome.

=over 4

=item fids

Reference to a list of feature IDs.

=item RETURN

Returns a reference to a hash mapping each feature ID to a 4-tuple [sequence-id, start, end, strand].  The start is always to the
left of the end, and the values are positions (1-based), not offsets.

=back

=cut

sub FeatureLocations {
    my ($self, $fids) = @_;
    # Get the PATRIC API object.
    my $p3 = $self->{p3};
    # Get the sequence ID, start, end, and strand for each incoming feature.
    my $fidList = P3Utils::get_data_keyed($p3, feature => [], ['patric_id', 'sequence_id', 'start', 'end', 'strand'], $fids);
    # Form the result into a hash.
    my %retVal = map { $_->[0] => [ @{$_}[1..4] ] } @$fidList;
    return \%retVal;
}

=head3 FeatureRegions

    my $fidHash = $p3seqs->FeatureRegions(\@fids, %options);

Return the regions containing the specified features.  For each feature, we will return the DNA for the feature plus the surrounding area, with
occupied portions in upper case and intergenic regions in lower case.

=over 4

=item fids

Reference to a list of a the IDs for the features whose regions are desired.

=item options

A hash containing zero or more of the following keys.

=over 8

=item distance

The distance to display to either side of each feature.  The default is C<100>.

=back

=item RETURN

Returns a reference to a hash mapping each incoming feature ID to its region sequence.

=back

=cut

sub FeatureRegions {
    my ($self, $fids, %options) = @_;
    my $p3 = $self->{p3};
    # Get the options.
    my $distance = $options{distance} // 100;
    # This will be the return hash.
    my %retVal;
    # Get the feature locations.
    my $fidHash = $self->FeatureLocations($fids);
    # Compute the regions for each sequence.
    my $regionHash = $self->_seq_regions($fidHash, %options);
    # Loop through the sequences, storing the regions in the output hash.
    for my $seqID (keys %$regionHash) {
        # Get the feature region hash.
        my $seqFidHash = $regionHash->{$seqID};
        # Loop through the features in this sequence.
        for my $fid (keys %$seqFidHash) {
            # Get the specs for this region.  Start and end are in the sub-hash, while strand is in fidHash.
            my $strand = $fidHash->{$fid}[3];
            my ($start, $end) = @{$seqFidHash->{$fid}};
            # Compute the actual region sequence.
            my $region = $self->_get_region($seqID, $start, $end, $strand);
            # Store the result.
            $retVal{$fid} = $region;
        }
    }
    # Return the hash of sequence data.
    return \%retVal;
}


=head3 FeatureConsolidatedRegions

    my $fidHash = $p3seqs->FeatureConsolidatedRegions(\@fids, \%map, %options);

Return consolidated regions containing the specified features.  Under the rules for consolidation, two overlapping regions are
combined into a single sequence.  If features are on the same strand, this may result in the same sequence being returned for
different features.

In addition to returning the sequences, a map is provided of the features found in the region returned.  For each feature, there
is a 3-tuple I<[fid, start, len]>, where I<fid> is the feature ID, I<start> is the starting position (1-based) in the sequence
returned, and I<len> is the length.

=over 4

=item fids

Reference to a list of feature IDs.

=item map

Reference to an output hash.  The hash will be keyed on feature ID, each of which will be mapped to a list of 3-tuples, one for each
feature found in the consolidated sequence.  The 3-tuples will consist of (0) the feature ID, (1) the starting position of the feature's
DNA (1-based) and (2) ending position of the feature's DNA (1-based).

=item options

A hash containing zero or more of the following keys.

=over 8

=item distance

The distance to display to either side of each feature.  The default is C<100>.

=back

=item RETURN

Returns a hash mapping each incoming feature ID to the output consolidated DNA sequence.

=back

=cut

sub FeatureConsolidatedRegions {
    my ($self, $fids, $map, %options) = @_;
    # First, we get the feature locations.
    my $fidLocs = $self->FeatureLocations($fids);
    # Now compute the sequence regions.
    my $regionHash = $self->_seq_regions($fidLocs, %options);
    # Finally, we consolidate the regions into a master list.
    my $regionList = $self->_consolidate($regionHash);
    # We loop through the regions, producing an output sequence for each feature in each region.
    my %retVal;
    for my $region (@$regionList) {
        my ($seqID, $start, $end, @fids) = @$region;
        # Process each feature to create the mapping for this region.
        my @mapping;
        for my $fid (@fids) {
            # Get this feature's location data.
            my $start1 = $fidLocs->{$fid}[1];
            my $end1 = $fidLocs->{$fid}[2];
            # Compute the map entry.
            my $start0 = $start1 - $start + 1;
            my $end0 = $end1 - $start + 1;
            push @mapping, [$fid, $start0, $end0];
        }
        # Sort the map.
        @mapping = sort { $a->[1] <=> $b->[1] } @mapping;
        # Now output the features.
        for my $fid (@fids) {
            my ($seqID, undef, undef, $strand) = @{$fidLocs->{$fid}};
            my $sequence = $self->_get_region($seqID, $start, $end, $strand);
            $retVal{$fid} = $sequence;
            if ($strand eq '+') {
                $map->{$fid} = \@mapping;
            } else {
                # We are on the - strand, so we have to flip the mapping.
                my $len = length $sequence;
                my @negMapping = map { [$_->[0], $len - $_->[2], $len - $_->[1]] } @mapping;
                $map->{$fid} = \@negMapping;
            }
        }
    }
    # Return the output hash.
    return \%retVal;
}


=head2 Internal Utilities

=head3 _get_region

    my $dna = $p3seqs->_get_region($seqID, $start, $end, $strand);

Return the DNA in the requested region on the requested strand.

=over 4

=item seqID

ID of the sequence containing the region.

=item start

The start position of the region (1-based).

=item end

The end position of the region (1-based).  This is the ending base pair, not a pointer past the end.

=item strand

C<+> for the forward strand, C<-> for the backward strand.

=item RETURN

Returns the DNA sequence for the specified region on the specified strand of the specified sequence.

=back

=cut

sub _get_region {
    my ($self, $seqID, $start, $end, $strand) = @_;
    # Get the sequence itself.
    my $sequence = $self->GetSequence($seqID);
    # Extract the region.  Note that here we must convert from positions to offsets.
    my $retVal = substr($sequence, $start - 1, $end - $start + 1);
    # Adjust for strand.
    if ($strand eq '-') {
        SeedUtils::rev_comp(\$retVal);
    }
    # Return the sequence.
    return $retVal;
}

=head3 _seq_regions

    my $regionHash = $p3seqs->_seq_regions(\%fidLocs, %options);

Return a hash describing the distribution of the desired feature regions in each sequence.  The result will be
organized by sequence.  For each feature in the sequence, the start and end positions of the region will be
mapped from the feature ID.  The start and end will already be constrained to lie inside the sequence boundaries,
but they will still be positions, not offsets.  This is the first step in isolating DNA regions for output.

=over 4

=item fidLocs

Reference to a hash mapping each feature to its location, output from L</FeatureLocations>.

=item options

A hash containing zero or more of the following keys.

=over 8

=item distance

The distance to display to either side of each feature.  The default is C<100>.

=back

=item RETURN

Returns a reference to a two-level hash keyed by sequence ID and then feature ID.  Each sequence ID will map to a
sub-hash keyed by the IDs of the features in that sequence.  This sub-hash in turn will map each feature ID to the
2-tuple [start, end], indicating the start and end positions of the feature's region.

=back

=cut

sub _seq_regions {
    my ($self, $fidLocs, %options) = @_;
    # We will need the sequence lengths.
    my $seqL = $self->{seqL};
    # Get the options.
    my $distance = $options{distance} // 100;
    # This will be the return hash.
    my %retVal;
    # Loop through the features, creating the regions.
    for my $fid (keys %$fidLocs) {
        my $locData = $fidLocs->{$fid};
        my ($seqID, $start, $end) = @$locData;
        # Now we have to expand this feature's region.  Get the sequence length.
        my $seqLen = $self->SeqLen($seqID);
        # Expand the region and constrain it.  Note the first position is 1, not 0.
        $start -= $distance;
        if ($start < 1) {
            $start = 1;
        }
        $end += $distance;
        if ($end >= $seqLen) {
            $end = $seqLen - 1;
        }
        # Store the region in the output hash.
        $retVal{$seqID}{$fid} = [$start, $end];
    }
    # Return the output hash.
    return \%retVal;
}

=head3 _verify_seq

    $p3seqs->_verify_seq($seqID);

Insure the specified sequence is in memory.  This loads the sequence into the internal hashes but does not return anything.

=over 4

=item seqID

The ID of the desired sequence.

=back

=cut

sub _verify_seq {
    my ($self, $seqID) = @_;
    # Get the sequence hash.
    my $seqH = $self->{seqH};
    my $seqL = $self->{seqL};
    # Do we need to load this sequence?
    if (! $seqH->{$seqID}) {
        # Yes, we do.  Read the DNA first.
        my $p3 = $self->{p3};
        my $seqList = P3Utils::get_data($p3, contig => [['eq', 'sequence_id', $seqID]], ['sequence_id', 'genome_id', 'sequence']);
        my $seqData = $seqList->[0];
        if ($seqData) {
            my ($id, $genome, $sequence) = @$seqData;
            # Here we have the sequence.  Get the locations of the features in this sequence.  In PATRIC, the start is always on
            # the left and the end on the right.  We don't need the strand for this.
            my $flocList = P3Utils::get_data($p3, feature => [['eq', 'sequence_id', $seqID], ['eq', 'feature_type', 'CDS']], ['patric_id', 'start', 'end']);
            # Start in lower case.
            $sequence = lc $sequence;
            # Loop through the features, converting them to upper case.  Note we need to adjust the start, since it is a position,
            # not an offset.
            for my $floc (@$flocList) {
                my ($fid, $start, $end) = @$floc;
                $start--;
                my $len = $end  - $start;
                my $newVal = uc substr($sequence, $start, $len);
                substr($sequence, $start, $len) = $newVal;
            }
            # Store the result back.
            $seqH->{$seqID} = $sequence;
            $seqL->{$seqID} = length $sequence;
        }
    }
}

=head3 _consolidate

    my $regionList = $p3seqs->_consolidate(\%seqRegions);

Return a list of the consolidated regions.  Regions are consolidated by forming the union of existing regions that overlap.
The region itself is described by the start, the end, and a list of the features included.  The start and end are both positions
(1-based) rather than offsets.

=over 4

=item seqRegions

Reference to a two-level hash mapping sequences to feature IDs and feature IDs to regions.  This is the output of L</_seq_regions>.

=item RETURN

Returns a reference to a list of region descriptors. Each region descriptor is a reference to a list consisting of (0) the sequence ID,
(1) the start position of the region, (2) the end position of the region, and (3) one or more feature IDs indicating the features in
the region.  The return list will be sorted by sequence ID.

=back

=cut

sub _consolidate {
    my ($self, $seqRegions) = @_;
    # This will be our output list.
    my @retVal;
    # We process the sequences one at a time.  For each sequence, we need to partition the features based on overlap.
    for my $seqID (keys %$seqRegions) {
        my $fidRegions = $seqRegions->{$seqID};
        # This is our initial region list for this sequence.  It starts with one feature per region, sorted by start position.
        my @residual = sort { $a->[1] <=> $b->[1] }
                map { [$seqID, $fidRegions->{$_}[0], $fidRegions->{$_}[1], $_] } keys %$fidRegions;
        # Loop until all the regions are final.
        while (my $nextRegion = shift @residual) {
            # $nextRegion is now the leftmost region that has not been combined with others.  No region can have space to the left
            # of it.  Any region that overlaps must have a start before its end.  As we merge, we will update the current ending.
            # The first time we find a start after the current ending, we have a gap and can stop.
            while (@residual && $residual[0][1] <= $nextRegion->[2]) {
                my $newRegion = shift @residual;
                my (undef, undef, $end, @fids) = @$newRegion;
                # Add the new region's features to this region.
                push @$nextRegion, @fids;
                # Update the end position.
                $nextRegion->[2] = $end;
            }
            # Save the region we just created.
            push @retVal, $nextRegion;
        }
    }
    # Return the final region list.
    return \@retVal;
}
1;