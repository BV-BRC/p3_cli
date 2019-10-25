=head1 Small File Multi-Column Sort

    p3-sort.pl [options] col1 col2 ... colN

This is a sort script variant that sorts a single small file in memory with the ability to specify multiple columns.
It assumes the file has a header, and the columns are tab-delimited. If no columns are specified, it sorts by the
first column only.

=head2 Parameters

The positional parameters are the indices (1-based) or names of the key columns. Columns to be sorted numerically
are indicated by a slash-n (C</n>) at the end of the column index or name. So,

    p3-sort genome.genome_id feature.start/n

Would indicate two key columns, the second of which is to be sorted numerically.

Use C</p> to sort in PEG order, which means the column contains FIG feature IDs.

To sort in reverse, add C</r> for reverse string sort and C</nr> for reverse numeric sort.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

The following additional options are suppported.

=over 4

=item count

If specified, the output will consist only of the key fields with a count column added.

=item nonblank

If specified, records with at least one empty key field will be discarded.

=item unique

Only include one output line for each key value.  This option is mutually exclusive with C<--dups>.

=item dups

Only include lines with duplicate keys in the output.  This option is mutually exclusive with C<--unique>.

=item nohead

If specified, the input file has no headers.

=item verbose

Write progress messages to STDERR.

=back

=cut

use strict;
use P3Utils;
use SeedUtils qw(by_fig_id);

# Get the command-line options.
my $opt = P3Utils::script_opts('col1 col2 ... colN', P3Utils::ih_options(),
        ['count|K', 'count instead of sorting'],
        ['nonblank|V', 'discard records with empty keys'],
        ['unique|u', 'discard records with duplicate keys'],
        ['dups|D', 'only output records with duplicate keys'],
        ['nohead', 'input file has no headers'],
        ['verbose|debug|v', 'write progress messages to STDERR']
        );
# Verify the parameters. We need to separate the column names from the sort types.
my @sortCols;
my @sortTypes;
if (! @ARGV) {
    # No sort key. Sort by first column.
    @sortCols = 1;
    @sortTypes = 0;
} else {
    for my $sortCol (@ARGV) {
        if ($sortCol =~ /^(.+)\/(r|n|nr|p|pr)$/) {
            push @sortCols, $1;
            push @sortTypes, $2;
        } else {
            push @sortCols, $sortCol;
            push @sortTypes, '';
        }
    }
}
# Get the options.
my $count = $opt->count;
my $valued = $opt->nonblank;
my $unique = $opt->unique;
my $dupsOnly = $opt->dups;
my $nohead = $opt->nohead;
my $debug = $opt->verbose;
if ($unique && $dupsOnly) {
    die "Cannot specify both --unique and --dups.";
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers and compute the key columns.
my ($headers, $cols);
if ($nohead) {
    $cols = [map { $_ - 1 } @sortCols];
} else {
    ($headers, $cols) = P3Utils::find_headers($ih, 'sort input' => @sortCols);
    # Write out the headers.
    if ($count) {
        my @sortHeaders = P3Utils::get_cols($headers, $cols);
        P3Utils::print_cols([@sortHeaders, 'count']);
    } else {
        P3Utils::print_cols($headers);
    }
}
# We will use this hash to facilitate the sort. It is keyed on the first column.
my %sorter;
# Loop through the input.
my $progress = 0;
while (! eof $ih) {
    my $line = <$ih>;
    $progress++;
    print STDERR "$progress records read.\n" if $debug && $progress % 10000 == 0;
    my @fields = P3Utils::get_fields($line);
    # Form the key.
    my @key = map { $fields[$_] } @$cols;
    if (! $valued || ! scalar grep { $_ eq '' } @key) {
        my $key1 = join("\t", @key);
        push @{$sorter{$key1}}, $line;
    }
}
# Now process each group.
$progress = 0;
print STDERR "Sorting keys.\n" if $debug;
for my $key (sort { tab_cmp($a, $b) } keys %sorter) {
    $progress++;
    print STDERR "$progress keys processed.\n" if $debug && $progress % 10000 == 0;
    # Sort the items.
    my $subList = $sorter{$key};
    my $counter = scalar @$subList;
    if (! $count) {
        # Print the sorted items.
        if ($unique) {
            print $subList->[0];
        } elsif ($dupsOnly) {
            if ($counter > 1) {
                print @$subList;
            }
        } else {
            print @$subList;
        }
    } else {
        # Count the items for each key combination and print them.
        print "$key\t$counter\n";
    }
}

# Compare two lists.
sub tab_cmp {
    my ($a, $b) = @_;
    my @a = split /\t/, $a;
    my @b = split /\t/, $b;
    my $n = scalar @a;
    my $retVal = 0;
    for (my $i = 0; $i < $n && ! $retVal; $i++) {
        if ($sortTypes[$i] eq 'n') {
            $retVal = $a[$i] <=> $b[$i];
        } elsif ($sortTypes[$i] eq 'nr') {
            $retVal = $b[$i] <=> $a[$i];
        } elsif ($sortTypes[$i] eq 'r') {
            $retVal = $b[$i] cmp $a[$i];
        } elsif ($sortTypes[$i] eq 'p') {
            $retVal = by_fig_id($a[$i], $b[$i]);
        } elsif ($sortTypes[$i] eq 'pr') {
            $retVal = by_fig_id($b[$i], $a[$i]);
        } else {
            $retVal = $a[$i] cmp $b[$i];
        }
    }
    return $retVal;
}
