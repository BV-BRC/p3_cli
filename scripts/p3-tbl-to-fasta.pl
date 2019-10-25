=head1 Convert a Tab-Delimited File to FASTA

    p3-tbl-to-fasta.pl [options] idCol seqCol

This script will convert a tab-delimited file containing sequence data to a FASTA file. The tab-delimited file is taken from
the standard input; the FASTA file will be the standard output.

=head2 Parameters

The positional parameters are the index (1-based) or name of the column containing the sequence IDs and the index or name of the column
containing the sequences.

The standard input can be overriddn using the options in L<P3Utils/ih_options>.

The following additional command-line options are supported.

=over 4

=item comment

The index (1-based) or name of the column containing comment text. If omitted, no comment text is included in the output. If multiple
comment columns are specified (using multiple instancs of the option), they will be concatenated with a tab.

=item nohead

If specified, the standard input will be presumed to have no headers.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('idCol seqCol', P3Utils::ih_options(),
        ['nohead', 'input has no headers'],
        ['comment|k=s@', 'index (1-based) or name of the comment column']
        );
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders) = P3Utils::process_headers($ih, $opt, 1);
# Compute the input columns.
my ($idCol, $seqCol) = @ARGV;
if (! defined $idCol) {
    die "No column specifiers found.";
} elsif (! defined $seqCol) {
    die "No sequence column specified.";
}
$idCol = P3Utils::find_column($idCol, $outHeaders);
$seqCol = P3Utils::find_column($seqCol, $outHeaders);
my @commentCols;
if ($opt->comment) {
    my @cols = @{$opt->comment};
    for my $commentCol (@cols) {
        push @commentCols, P3Utils::find_column($commentCol, $outHeaders);
    }
}
my @columns = ($idCol, $seqCol, @commentCols);
# Loop through the input, creating FASTA output.
while (! eof $ih) {
    # Get the columns we need.
    my ($id, $seq, @comments) = P3Utils::get_cols($ih, \@columns);
    # Insure the comment is a string.
    my $comment = join("\t", @comments);
    # Output the sequence data.
    my @chunks = ($seq =~ /(.{1,60})/g);
    print ">$id $comment\n";
    print join("\n", @chunks, "");
}