=head1 Identify Clusters in Genomes

    p3-identify-clusters.pl [options] clusterFile <features.tbl

Given an input file of features and locations, this script find occurrences of functional clusters.

The cluster file should contain in its last column a list of the clustered identifiers (usually roles or protein family IDs), separated by
a double colon delimited (C<::>). The first column should contain a cluster ID of some sort. This is the default for the output of
L<p3-generate-clusters.pl>.

The input file must include columns for the genome ID, the identifier used for clustering (again, usually roles or protein family IDs), the
sequence ID, and the location. Features that are close together on the chromosome and belong to the same cluster will be output along with
the sequence ID, start and end locations, and a cluster ID number.

=head2 Parameters

The positional parameter is the name of a tab-delimited file containing the clusters. The clusters must be in the first column,
and consist of multiple clustered identifiers (roles or family IDs) separated by item delimiters (C<::>).

The standard input can be overriddn using the options in L<P3Utils/ih_options>. The standard input must be a tab-delimited file
containing features. By default, the feature ID should be in a column named C<patric_id>, the location in a column named C<location>,
the sequence ID in a column named C<sequence_id>, and the clustered identifier (role or family) should be in the last column.
The clustered identifier is considered the key column.

Additional command-line options are those given in L<P3Utils/delim_options> (to specify the delimiters between identifiers) and
L<P3Utils/col_options> plus the following.

=over 4

=item locCol

Index (1-based) or name of the location column in the input.  The default is C<location>.

=item idCol

Index (1-based) or name of the feature ID column in the input.  The default is C<patric_id>.

=item seqCol

Index (1-based) or name of the sequence ID column in the input. The default is C<sequence_id>.

=item maxGap

The maximum gap between features for them to be considered part of a cluster. The default is C<2000>.

=item minItems

The minimum number of features for a group to be considered a cluster. The default is C<3>.

=item showRoles

If specified, the roles found in the cluster will be displayed in a column of the output.

=item showFids

If specified, the features found in the cluster will be displayed in a column of the output.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('clusterFile', P3Utils::col_options(), P3Utils::ih_options(), P3Utils::delim_options(),
        ['locCol|location|loccol|loc=s', 'index (1-based) or name of column containing location specification', { default => 'location' }],
        ['idCol|id|idcol=s', 'index (1-based) or name of column containing feature ID', { default => 'patric_id' }],
        ['seqCol|sequence|seqcol|seq=s', 'index (1-based) or name of column containing sequence ID', { default => 'sequence_id' }],
        ['maxGap|maxgap|max|gap=i', 'maximum distance between adjacent clustered features', { default => 2000 }],
        ['minItems|minitems|min=i', 'minimum number of features in a cluster', { default => 3 }],
        ['showRoles|showroles|roles', 'display roles found in cluster'],
        ['showFids|showfids|fids', 'display features found in cluster']
        );
# Get the delimiter. We need itas a search pattern for -split-.
my $delimP = P3Utils::undelim($opt);
# Get the options.
my $maxGap = $opt->maxgap;
my $minItems = $opt->minitems;
my $showRoles = $opt->showroles;
my $showFids = $opt->showfids;
# This will hold the title of the cluster ID column.
my $clidColTitle = 'cluster_id';
# This will map roles to cluster IDs.
my %roles;
# Get the cluster information. We start by finding the file and reading in the headers.
my ($clusterFile) = @ARGV;
if (! $clusterFile) {
    die "No cluster file specified.";
} elsif (! -s $clusterFile) {
    die "Cluster file $clusterFile not found, invalid, or empty.";
} elsif (! open(my $ch, '<', $clusterFile)) {
    die "Could not open cluster file $clusterFile: $!";
} else {
    # Process the cluster file headers as keyless. The key column is always the last one.
    my ($clustHeaders) = P3Utils::process_headers($ch, $opt, 1);
    # Get the headers of the ID column.
    if (! $opt->nohead) {
        $clidColTitle = $clustHeaders->[0];
    }
    # Loop through the cluster file.
    while (! eof $ch) {
        my ($id, $cluster) = P3Utils::get_cols($ch, [0, -1]);
        my @roles = split $delimP, $cluster;
        for my $role (@roles) {
            $roles{$role} = $id;
        }
    }
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Get the critical columns for the input file.
my $locCol = P3Utils::find_column($opt->loccol, $outHeaders);
my $idCol = P3Utils::find_column($opt->idcol, $outHeaders);
my $seqCol = P3Utils::find_column($opt->seqcol, $outHeaders);
# Compute the headers and write them out.
if (! $opt->nohead) {
    my @cols = ($clidColTitle, 'genome_id', 'sequence_id', 'start', 'end');
    push @cols, 'features' if $showFids;
    push @cols, 'roles' if $showRoles;
    P3Utils::print_cols(\@cols);
}
# First we sort the features into sequences.
my %sequences;
# Loop through the input.
while (! eof $ih) {
    # Get the next feature's record.
    my ($fid, $sequence, $location, $role) = P3Utils::get_cols($ih, [$idCol, $seqCol, $locCol, $keyCol]);
    # Compute the start and end.
    my ($start, $end) = $location =~ /(\d+)\.\.(\d+)/;
    if (defined $start && defined $end) {
        # Compute the genome.
        my ($genome) = $fid =~ /(\d+\.\d+)/;
        # Only proceed if we found a genome ID. Sometimes bad features sneak in.
        if (defined $genome) {
            # If this role is in a cluster, save it for this sequence.
            my $clusterID = $roles{$role};
            if (defined $clusterID) {
                push @{$sequences{"$genome:$sequence"}}, [$fid, $start, $end, $clusterID, $role];
            }
        }
    }
}
close $ih;
# Loop through the sequences.
for my $sequence (sort keys %sequences) {
    # Parse the sequence name to get the genome and sequence ID.
    my ($genomeID, $sequenceID) = split /:/, $sequence;
    # Get all the features in order by start position.
    my @features = sort { $a->[1] <=> $b->[1] } @{$sequences{$sequence}};
    # Loop through them, forming clusters.
    while (scalar @features) {
        my $feature = shift @features;
        my ($fid, $start, $end, $clusterID) = @$feature;
        # This will hold the cluster.
        my @cluster = $feature;
        # This will hold the skipped features, which we'll want to process again.
        my @skipped;
        # Loop until we run out of features or find a gap that's too big.
        while (scalar @features && $features[0][1] <= $end + $maxGap) {
            # We want to look at this feature. It either goes in the cluster or the skip list.
            $feature = shift @features;
            if ($feature->[3] eq $clusterID) {
                push @cluster, $feature;
                $end = $feature->[2];
            } else {
                push @skipped, $feature;
            }
        }
        # If the cluster is big enough, write it out.
        if (scalar @cluster >= $minItems) {
            my @row = ($clusterID, $genomeID, $sequenceID, $start, $end);
            if ($showRoles) {
                push @row, [map { $_->[4] } @cluster];
            }
            if ($showFids) {
                push @row, [map { $_->[0] } @cluster];
            }
            P3Utils::print_cols(\@row, opt => $opt);
        }
        # Set up for the next pass by pasting the unchecked features to the skipped ones.
        @features = (@skipped, @features);
    }
}
