=head1 Build a Kmer Database from a Table of Sequences

    p3-build-kmer-db.pl [options] idCol outFile

This script creates a kmer database. The basic model of the database is that we have groups of incoming sequences, each with an ID and a name. So, for
example, a group could be a whole genome with each sequence a contig, or a group could be a specific protein with only one sequence per group-- the
protein itself and the name the protein's role. Names are entirely optional.

The database will map each kmer to a list of the groups to which it belongs. Command-line options allow you to specify that common kmers be eliminated
or that the kmers be discriminating (that is, unique to only one group). The kmer database can then be used as input to various other scripts (such as
L<p3-closest-seqs.pl>).

=head2 Parameters

The positional parameters are the column identifier for the column containing the group ID and the name of the output file into which the
kmer database is to be stored. The constant string C<fasta> can be used for the group ID column if a FASTA file is input. In that case, the sequence ID
is the group ID and the comment is the group name.

The standard input can be overriddn using the options in L<P3Utils/ih_options>.

The options in L<P3Utils/col_options> can be used to specify the input column containing the sequence text. The default is the last input column.

Additional command-line options are the following.

=over 4

=item kmerSize

The size of a kmer. The default is C<15>.

=item max

The maximum number of times a kmer can appear. A kmer appearing more than the specified number of times is considered common and discarded. A value of C<0>
indicates all kmers should be kept. The default is C<10>.

=item nameCol

The index (1-based) or name of the input column containing the group names.

=item discriminating

If specified, only discriminating kmers (that is, kmers unique to a single group) are kept. In this case, the C<--max> option is ignored.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use KmerDb;

# Get the command-line options.
my $opt = P3Utils::script_opts('idCol outFile', P3Utils::ih_options(), P3Utils::col_options(),
        ['nameCol|name|l=s', 'index (1-based) or name of the input column containing group names'],
        ['kmerSize|kmersize|kmer|k=i', 'kmer size', { default => 15 }],
        ['max|m=i', 'maximum number of occurrences per useful kmer', { default => 10 }],
        ['discriminating|discrim|D', 'discriminating kmers only'],
        );
# Determine the input characteristics.
my ($idCol, $outFile) = @ARGV;
my $fastaFlag;
if (! $idCol) {
    die "ID column and output file name must be specified.";
} elsif (lc($idCol) eq 'fasta') {
    $fastaFlag = 1;
}
if (! $outFile) {
    die "No output file name specified.";
} elsif (-d $outFile) {
    die "Invalid output file name specified.";
}
# Get the kmer size.
my $K = $opt->kmersize;
print "Kmer size is $K.\n";
# Open the input file.
my $ih = P3Utils::ih($opt);
# Construct the raw database depending on the type of input.
my $kmerDB = KmerDb->new(kmerSize => 8, maxFound => $opt->max);
if ($fastaFlag) {
    print "Processing FASTA input.\n";
    ProcessFasta($ih, $kmerDB);
} else {
    # Here we have a tab-delimited file, so we need to process headers.
    my ($headers, $seqCol) = P3Utils::process_headers($ih, $opt);
    $idCol = P3Utils::find_column($idCol, $headers);
    my @keyCols = ($idCol, $seqCol);
    my $nameCol = $opt->namecol;
    if (defined $nameCol) {
        push @keyCols, P3Utils::find_column($nameCol, $headers);
    } else {
        print "No group name column specified.\n";
    }
    print "Processing tab-delimited input.\n";
    ProcessTBL($ih, $kmerDB, @keyCols);
}
# Finalize the database depending on the options.
print "Finalizing database.\n";
if ($opt->discriminating) {
    $kmerDB->ComputeDiscriminators();
} else {
    $kmerDB->Finalize();
}
print "Saving database to $outFile.\n";
# Save to the output file.
$kmerDB->Save($outFile);
print "Database saved.\n";

## Process a FASTA file for kmers.
sub ProcessFasta {
    my ($ih, $kmerDB) = @_;
    # Initialize for the first record.
    my ($id, $comment, @seq);
    # Loop through the input.
    while (! eof $ih) {
        my $line = <$ih>;
        $line =~ s/[\r\n]+$//;
        if ($line =~ /^>(\S+)\s*(.*)/) {
            my ($newID, $newName) = ($1, $2);
            if ($id) {
                $kmerDB->AddSequence($id, join("", @seq), $comment);
            }
            ($id, $comment) = ($newID, $newName);
            print "Processing $id.\n";
        } else {
            push @seq, $line;
        }
    }
    # Output any residual.
    if ($id) {
        $kmerDB->AddSequence($id, join("", @seq), $comment);
    }
}

## Process a tab-delimited file for kmers.
sub ProcessTBL {
    my ($ih, $kmerDB, @keyCols) = @_;
    # Loop through the input.
    while (! eof $ih) {
        my ($id, $seq, $name) = P3Utils::get_cols($ih, \@keyCols);
        print "Processing $id.\n";
        $kmerDB->AddSequence($id, $seq, $name);
    }
}
