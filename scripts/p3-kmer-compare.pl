=head1 Perform a Kmer Comparison for Two Genomes

    p3-kmer-compare.pl [options] genome1 genome2 ... genomeN

This script compares genomes based on DNA kmers. It outputs the number of kmers the two genomes have in common, the number appearing
only in the first genome, and the number appearing only in the second.

In verbose mode, it produces a pair of percentages for each combination-- completeness and contamination-- displayed in a matrix. The percentages
project the row genome onto the column genome. A completeness of 100% means every kmer in the column genome is found in the row genome. A
contamination of 100% means every kmer in the column genome is NOT found in the row genome. So, if the genomes are identical, the percentages
will be C<100.0/0.0>. If the column genome is a subset of the row genome, the completeness will be 100% but the contamination will be nonzero.

NOTE that for best performance, the longest genome should be specified first in the list. This reduces the number of times memory needs to be
reorganized.

=head2 Parameters

The positional parameters are the two genomes to compare. Each genome can be either (1) a PATRIC genome ID, (2) the name of a DNA FASTA file, or
(3) the name of a L<GenomeTypeObject> file.

There is no standard input.

The command-line options are as follows.

=over 4

=item kmerSize

The size of a kmer. The default is C<12> for DNA and C<8> for protein.

=item geneticCode

If specified, a genetic code to use to translate the DNA sequences to proteins. In this case, the matching will be on protein kmers.

=item verbose

If specified, completeness and contamination percentages will be included in the output matrix.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use KmerDb;

# Get the command-line options.
my $opt = P3Utils::script_opts('genome1 genome2 ... genomeN',
        ['kmerSize|kmersize|kmer|k=i', 'kmer size'],
        ['geneticCode|geneticcode|code|gc|x=i', 'genetic code for protein kmers (default is to use DNA kmers)'],
        ['verbose|v', 'include percentages in output']
        );
# Compute the genetic code (if any).
my $geneticCode = $opt->geneticcode;
if ($geneticCode) {
    $geneticCode = SeedUtils::genetic_code($geneticCode);
}
# Extract the options.
my $verbose = $opt->verbose;
# Compute the kmer size.
my $defaultKmer = ($geneticCode ? 8 : 12);
my $kmerSize = $opt->kmersize // $defaultKmer;
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Get the two genomes.
my @genomes = @ARGV;
# This will count the sequences processed.
my $count = 0;
# Create the kmer database. Each genome will be a group.
my $kmerDb = KmerDb->new(kmerSize => $kmerSize, maxFound => 0);
for my $genome (@genomes) {
    if ($genome =~ /^\d+\.\d+$/) {
        print STDERR "Processing PATRIC genome $genome.\n";
        ProcessPatric($kmerDb, $genome);
    } elsif (-s $genome) {
        # Here the genome is a file.
        open(my $gh, "<$genome") || die "Could not open genome file $genome: $!";
        # Read the first line.
        my $line = <$gh>;
        if ($line =~ /^>(\S+)/) {
            # Process the FASTA file starting with the contig whose header we just read.
            print STDERR "Processing FASTA file $genome.\n";
            ProcessFasta($kmerDb, $genome, $1, $gh);
        } elsif ($line =~ /\{/) {
            # Read the file into memory and convert to a GTO.
            print STDERR "Reading GTO file $genome.\n";
            my $gto = ReadGto($line, $gh);
            # Close the file and release the line variable in case it's a one-line GTO.
            close $gh;
            undef $line;
            # Process the GTO's contigs.
            print STDERR "Processing GTO file $genome.\n";
            ProcessGto($kmerDb, $genome, $gto);
        } else {
            die "$genome is not a recognizable GTO or FASTA file.";
        }
    } else {
        die "Invalid genome specifier $genome.";
    }
}
# Compute the cross-reference matrix.
print STDERR "Creating cross-reference matrix, format is col/both/row.\n";
if ($verbose) {
    print STDERR "Percentages shown for projecting column genomes into row genomes.\n";
}
my $xref = $kmerDb->xref();
print STDERR "Printing cross-reference matrix.\n";
# Print out the matrix.
P3Utils::print_cols(['genome', 'name', @genomes]);
for my $genomeI (@genomes) {
    my @row = ($genomeI, $kmerDb->name($genomeI));
    for my $genomeJ (@genomes) {
        # If the genomes are identical, use a dummy.
        if ($genomeI eq $genomeJ) {
            push @row, 'x';
        } else {
            # There is only one entry for this genome pair. If it's not the one we expect,
            # we use its dual.
            my $list = $xref->{$genomeI}{$genomeJ};
            if (! $list) {
                $list = [reverse @{$xref->{$genomeJ}{$genomeI}}];
            }
            my $ratio = join("/", @$list);
            if ($verbose) {
                my $complete = $list->[1] * 100 / ($list->[1] + $list->[2]);
                my $contam = $list->[0] * 100 / ($list->[0] + $list->[1]);
                $ratio .= ", " . sprintf("%0.1f/%0.1f", $complete, $contam);
            }
            push @row, $ratio;
        }
    }
    P3Utils::print_cols(\@row);
}

## Read a GenomeTypeObject file. We don't bless it or anything, because we just need the contigs.
## Doing this in a subroutine cleans up the very memory-intensive intermediate variables.
sub ReadGto {
    my ($line, $gh) = @_;
    my @lines = <$gh>;
    my $string = join("", $line, @lines);
    my $retVal = SeedUtils::read_encoded_object(\$string);
    return $retVal;
}

## Process a PATRIC genome. The genome's contigs will be put into the Kmer database.
sub ProcessPatric {
    my ($kmerDb, $genome) = @_;
    # Get the genome's contigs.
    my $results = P3Utils::get_data($p3, contig => [['eq', 'genome_id', $genome]], ['genome_name', 'sequence']);
    # Process the sequence kmers.
    for my $result (@$results) {
        AddSequence($kmerDb, $genome, $result->[1], $result->[0], $geneticCode);
    }
}

## Process a FASTA genome. The FASTA sequences will be put into the Kmer database. Note we ignore the labels.
sub ProcessFasta {
    my ($kmerDb, $genome, $label, $gh) = @_;
    my $count = 0;
    # We will accumulate the current sequence in here.
    my @chunks;
    # This will be TRUE if we read end-of-file.
    my $done;
    # Loop through the file.
    while (! $done) {
        my $chunk = <$gh>;
        if (! $chunk || $chunk =~ /^>/) {
            # Here we are at the end of a sequence.
            my $line = join("", @chunks);
            AddSequence($kmerDb, $genome, $line, "$genome FASTA file", $geneticCode);
            $done = ! $chunk;
        } else {
            # Here we have part of a sequence.
            chomp $chunk;
            push @chunks, $chunk;
        }
    }
}

## Process a GTO genome. The contigs will be put into the Kmer database.
sub ProcessGto {
    my ($kmerDb, $genome, $gto) = @_;
    # Get the genome name.
    my $name = $gto->{scientific_name};
    # Loop through the contigs.
    my $contigsL = $gto->{contigs};
    for my $contig (@$contigsL) {
        AddSequence($kmerDb, $genome, $contig->{dna}, $name, $geneticCode);
    }
}

## Add a sequence to the kmer database (both strands).
sub AddSequence {
    my ($kmerDb, $genome, $sequence, $gName, $gCode) = @_;
    # Add this sequence to the kmer database in both directions.
    AddSequence1($kmerDb, $genome, $sequence, $gName, $gCode);
    $sequence = SeedUtils::reverse_comp($sequence);
    AddSequence1($kmerDb, $genome, $sequence, $gName, $gCode);
    $count++;
    print STDERR "$count sequences processed.\n";
}

## Add a sequence to the kmer database (one strand).
sub AddSequence1 {
    my ($kmerDb, $genome, $sequence, $gName, $gCode) = @_;
    if (! $gCode) {
        # DNA kmers.
        $kmerDb->AddSequence($genome, $sequence, $gName);
    } else {
        for my $frm (0, 1, 2) {
            my $prot = SeedUtils::translate(\$sequence, $frm, $gCode);
            $kmerDb->AddSequence($genome, $prot, $gName);
        }
    }
}