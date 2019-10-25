=head1 Identify Clusters Containing Input Features

    p3-find-in-clusters.pl [options] realClusterFile

This script takes as input a list of features and compares it to a list of physical clusters (the output of L<p3-identify-clusters.pl>).
If a features is within the bounds of a cluster, or within the gap distance of either end, it will be output with the cluster ID appended.

=head2 Parameters

The positional parameter is the name of the file containing the cluster information. This must be a tab-delimited file with the following
columns-- (1) cluster ID, (2) genome ID, (3) sequence ID, (4) start location, and (5) end location. This is the output format from
L<p3-identify-clusters.pl>.

The standard input can be overriddn using the options in L<P3Utils/ih_options>. The standard input should contain feature IDs in the
key column (specified using the options in L<P3Utils/col_options>) plus the feature location and the ID of the containing sequence.
The following additional options are supported.

=over 4

=item maxGap

The maximum number of base pairs allowed between two features in the same cluster. The default is C<2000>.

=item location

In index (1-based) or name of the column containing the feature location. The default is C<location>.

=item sequence

The index (1-based) or name of the column containing the sequence ID. The defahult is C<sequence_id>.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('realClusterFile', P3Utils::col_options(), P3Utils::ih_options(),
        ['maxGap|maxgap|maxG|maxg|g=i', 'maximum feature gap', { default => 2000 }],
        ['location|loc|l=s', 'index (1-based) or name of column containing feature location', { default => 'location' }],
        ['sequence|seq|s=s', 'index (1-based) or name of column containing the ID of the contig containing the feature', { default => 'sequence_id' }]
        );
# Compute the gap.
my $maxGap = $opt->maxgap;
# For each sequence (keyed on genomeID:sequenceID), this hash will contain a list of [clusterID, start, end] tuples. The start and end
# will be extended by the gap distance.
my %sequences;
# Get the cluster file.
my $clHeaders;
my ($realClusterFile) = @ARGV;
if (! $realClusterFile) {
    die "No cluster file specified.";
} elsif (! -s $realClusterFile) {
    die "Cluster file $realClusterFile missing, invalid, or empty.";
} else {
    open(my $ch, '<', $realClusterFile) || die "Could not open $realClusterFile: $!";
    # Process the header line. We don't look for a key column.
    ($clHeaders) = P3Utils::process_headers($ch, $opt, 1);
    my $line = <$ch>;
    # Loop through the cluster data.
    while (! eof $ch) {
        my $line = <$ch>;
        my @fields = P3Utils::get_fields($line);
        my ($clusterID, $genomeID, $sequenceID, $start, $end) = @fields;
        push @{$sequences{"$genomeID:$sequenceID"}}, [\@fields, $start - $maxGap, $end + $maxGap];
    }
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Locate the location and sequence columns.
my $locCol = P3Utils::find_column($opt->location, $outHeaders);
my $seqCol = P3Utils::find_column($opt->sequence, $outHeaders);
# Form the full header set and write it out.
if (! $opt->nohead) {
    push @$outHeaders, @$clHeaders;
    P3Utils::print_cols($outHeaders);
}
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    # Loop through the couplets.
    for my $couplet (@$couplets) {
        my ($fid, $line) = @$couplet;
        if ($fid =~ /(\d+\.\d+)/) {
            my $genome = $1;
            my $location = $line->[$locCol];
            if ($location =~ /(\d+)\.\.(\d+)/) {
                my ($start, $end) = ($1, $2);
                my $sequenceID = join(':', $genome, $line->[$seqCol]);
                # Get the sequence's clusters and look for a match.
                my $clusters = $sequences{$sequenceID};
                if ($clusters) {
                    for my $cluster (@$clusters) {
                        # Determine if this feature is in this cluster.
                        my ($clData, $clStart, $clEnd) = @$cluster;
                        if ($start < $clEnd && $end > $clStart) {
                            # Yes, it is!
                            push @$line, @$clData;
                            P3Utils::print_cols($line);
                        }
                    }
                }
            }
        }
    }
}