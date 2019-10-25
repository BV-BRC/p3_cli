=head1 Profile Sequences by Letter Content

    p3-sequence-profile.pl [options]

This script analyzes DNA or protein sequences in the key column of the incoming file and outputs the number of times
each letter occurs. The output file will contain the letter in the first column and the count in the second, and
will be sorted from most frequent to least. This can lead to very small output files.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/col_options> (to select the column containing the sequences)
plus the following.

=over 4

=item fasta

Input file is a FASTA. In this case, the column specification will be ignored.

=item count

The number of sequences will be output to STDERR.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;


# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(),
        ['fasta', 'input is a FASTA file'],
        ['count|k', 'output the record count']
        );
# Open the input file.
my $ih = P3Utils::ih($opt);
# Determine the record type.
my $fasta = $opt->fasta;
# This will count the records.
my $count = 0;
# This will contain the key column for normal files.
my $keyCol;
if (! $fasta) {
    # Here we have a normal file. Read the incoming headers.
    (undef, $keyCol) = P3Utils::process_headers($ih, $opt);
} else {
    # Here we have a FASTA file. Skip the first sequence header.
    my $line = <$ih>;
    unless ($line =~ /^>/) {
        die "Invalid FASTA file-- first record is not a header.";
    }
}
# Loop through the input.
my %counts;
while (! eof $ih) {
    my $sequence = get_seq($ih, $keyCol);
    for my $char (split '', uc $sequence) {
        if ($char =~ /[A-Z.\-\?]/) {
            $counts{$char}++;
        }
    }
    $count++;
}
# Output the counts.
my @chars = sort { $counts{$b} <=> $counts{$a} } keys %counts;
P3Utils::print_cols(['letter', 'count']);
for my $char (@chars) {
    P3Utils::print_cols([$char, $counts{$char}]);
}
if ($opt->count) {
    print STDERR "$count records processed.\n";
}

# This gets the sequence from the record. Note that we only come in here if EOF is false.
# Also, in FASTA mode, the previous record read is always a header, so we are positioned on
# a sequence record.
sub get_seq {
    my ($ih, $keyCol) = @_;
    my $retVal;
    # If the key column is undefined, we have FASTA. Otherwise, we have normal.
    if (defined $keyCol) {
        ($retVal) = P3Utils::get_cols($ih, [$keyCol]);
    } else {
        # Here we have a FASTA file. Search for EOF or a header.
        my (@seqs, $done);
        while (! $done) {
            my $line = <$ih>;
            if ($line =~ /^>/) {
                $done = 1;
            } else {
                $line =~ s/[\r\n]+$//;
                push @seqs, $line;
                $done = eof $ih;
            }
        }
        # Assemble the sequence fragments.
        $retVal = join("", @seqs);
    }
    return $retVal;
}