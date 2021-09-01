=head1 Create Representative Genome Server Directory

    p3-rep-prots.pl [options] outDir

This script processes a list of genome IDs to create a directory suitable for use by the representative genomes server.
It will extract all the instances of the specified seed protein (default is Phenylanyl synthetase alpha chain). The list of genome IDs and
names will go in the output file C<complete.genomes> and a FASTA of the seed proteins in C<6.1.1.20.fasta>.

=head2 Parameters

The positional parameter is the name of the output directory. If it does not exist, it will be created.

The standard input can be overriddn using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/col_options> plus the following
options.

=over 4

=item clear

Clear the output directory if it already exists. The default is to leave existing files in place.

=item prot

Role name of the protein to use. The default is C<Phenylalanyl-tRNA synthetase alpha chain>.

=item dna

If specified, a C<6.1.1.20.dna.fasta> file will be produced in addition to the others, containing
the DNA sequences of the proteins.

=item binning

If specified, a seed protein database suitable for binning will be produced with the specified name.
(This is similar to the C<dna> option, but produces the comments in a slightly different format).

=item debug

If specified, status messages for the PATRIC3 API will be displayed.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use Stats;
use File::Copy::Recursive;
use RoleParse;
use Time::HiRes;
use Math::Round;
use FastA;
use Data::Dumper;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('outDir', P3Utils::col_options(), P3Utils::ih_options(),
        ['clear', 'clear the output directory if it exists'],
        ['prot=s', 'name of the protein to use', { default => 'Phenylalanyl-tRNA synthetase alpha chain' }],
        ['dna', 'produce a DNA FASTA file in addition to the default files'],
        ['binning=s', 'produce a SEED protein binning database in the named file'],
        ['debug', 'show P3 API messages']
        );
# Get the output directory name.
my ($outDir) = @ARGV;
if (! $outDir) {
    die "No output directory specified.";
} elsif (! -d $outDir) {
    print "Creating directory $outDir.\n";
    File::Copy::Recursive::pathmk($outDir) || die "Could not create $outDir: $!";
} elsif ($opt->clear) {
    print "Erasing directory $outDir.\n";
    File::Copy::Recursive::pathempty($outDir) || die "Error clearing $outDir: $!";
}
# Check for DNA mode.
my $dnaFile;
if ($opt->dna) {
    $dnaFile = "$outDir/6.1.1.20.dna.fasta";
}
my $binning = $opt->binning;
# Create the statistics object.
my $stats = Stats->new();
# Create a filter from the protein name.
my $protName = $opt->prot;
my @filter = (['eq', 'product', $protName]);
# Save the checksum for the seed role.
my $roleCheck = RoleParse::Checksum($protName);
# Create a list of the columns we want.
my @cols = qw(genome_id genome_name patric_id aa_sequence_md5 product);
my $dnaMode;
if ($dnaFile || $binning) {
    push @cols, 'na_sequence_md5';
    $dnaMode = 1;
}
# Open the output files.
print "Setting up files.\n";
open(my $gh, '>', "$outDir/complete.genomes") || die "Could not open genome output file: $!";
open(my $fh, '>', "$outDir/6.1.1.20.fasta") || die "Could not open FASTA output file: $!";
my ($bh, $nh);
if ($dnaFile) {
    open($nh, '>', $dnaFile) || die "Could not open DNA output file: $!";
}
if ($binning) {
    open($bh, '>', $binning) || die "Could not open binning output file: $!";
}
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
if ($opt->debug) {
    $p3->debug_on(\*STDERR);
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Get the full list of proteins.
print "Reading proteins.\n";
my $start0 = time;
my $protList = P3Utils::get_data($p3, feature => \@filter, \@cols);
print scalar(@$protList) . " proteins returned in " . Math::Round::nearest(0.01, time - $start0) . " seconds.\n";
# Get the list of genomes we want.
print "Reading genomes.\n";
my $genomes = P3Utils::get_col($ih, $keyCol);
my %genomes = map { $_ => 1 } @$genomes;
print scalar(@$genomes) . " genomes found in input file.\n";
my ($gCount, $pCount) = 0;
# This will track the proteins for each genome. It maps a genome ID to a list of protein tuples [name, seq, dna].
my %proteins;
# Loop through the proteins.
print "Processing proteins.\n";
for my $prot (@$protList) {
    my ($genome, $name, $fid, $seq, $product, $dna) = @$prot;
    if ($fid) {
        # We have a real feature, check the genome.
        if (! $genomes{$genome}) {
            $stats->Add(filteredGenome => 1);
        } else {
            my $check = RoleParse::Checksum($product // '');
            if ($check ne $roleCheck) {
                $stats->Add(funnyProt => 1);
            } else {
                push @{$proteins{$genome}}, [$name, $seq, $dna];
                $stats->Add(protFound => 1);
            }
        }
    }
    $pCount++;
    print "$pCount proteins processed.\n" if $pCount % 10000 == 0;
}
# Process the genomes one at a time, remembering MD5s.
my %md5s;
print "Processing genomes.\n";
for my $genome (@$genomes) {
    if (! $proteins{$genome}) {
        $stats->Add(genomeNotFound => 1);
    } else {
        my @prots = @{$proteins{$genome}};
        $stats->Add(genomeFound => 1);
        if (scalar @prots > 1) {
            # Skip if we have multiple proteins.
            $stats->Add(multiProt => 1);
            delete $proteins{$genome};
        } else {
            # Remember the genome name and sequence.
            my ($name, $protMd5, $dnaMd5) = @{$prots[0]};
            $proteins{$genome} = [$name, $protMd5, $dnaMd5];
            $md5s{$protMd5} = 1;
            if ($dnaMd5) {
                $md5s{$dnaMd5} = 1;
            }
            $stats->Add(genomeSaved => 1);
        }
    }
}
# Get the sequences.
print "Reading MD5s.\n";
my $start1 = time;
my $md5Hash = $p3->lookup_sequence_data_hash([keys %md5s]);
print "Sequences retrieved in " . (time - $start1) . " seconds.\n";
for my $genome (keys %proteins) {
    my ($name, $protMd5, $dnaMd5) = @{$proteins{$genome}};
    my $seq = $md5Hash->{$protMd5};
    if (! $seq) {
        $stats->Add(missingProtein => 1);
    } else {
        print $gh "$genome\t$name\n";
        print $fh ">$genome\n$seq\n";
        if ($dnaMd5) {
            my $dna = $md5Hash->{$dnaMd5};
            if (! $dna) {
                $stats->Add(missingDna => 1);
            } else {
                if ($nh) {
                    print $nh ">$genome\n$dna\n";
                    $stats->Add(dnaOut => 1);
                }
                if ($bh) {
                    print $bh ">fig|$genome.peg.X $genome\t$name\n$dna\n";
                    $stats->Add(binDnaOut => 1);
                }
            }
        }
    }
    $stats->Add(genomeOut => 1);
    $gCount++;
    print "$gCount genomes processed.\n" if $gCount % 10000 == 0;
}
$stats->Add(timeElapsed => int(time - $start0));
print "All done.\n" . $stats->Show();
