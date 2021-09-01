=head1 Create GTO or FASTA Files from BV-BRC Genomes

    p3-dump-genomes.pl [options] genome1 genome2 ... genomeN

This script creates L<GenomeTypeObject> or FASTA files for the specified BV-BRC genomes. Each file is named using the genome ID with
the appropriate suffix and placed in the current directory. The C<--outDir> option can be used to specify an alternate 
output directory. Existing files will be replaced.  This script is more general than L<p3-gto.pl>, which it replaces.

=head2 Parameters

The positional parameters are the IDs of the genomes to extract. A parameter of C<-> indicates that the standard input contains a
list of genome IDs to process. The options in L<P3Utils/col_options> can be used to specify the input column and L<P3Utils/ih_options> can
be used to modify the standard input.

One or more output options can be specified to determine what files to produce for each genome.  If no option is specified, the
default is C<--gto>.

In addition, the following command-line options can modify the default behavior.

=over 4

=item outDir

Name of the directory in which to put the output files. (The default is the current working directory.)

=item missing

Only process genomes for which files do not yet exist in the output directory. The default is to replace existing files.

=item fasta

Produce DNA FASTA files for the genomes.  There will be one sequence per contig and the suffix will be C<.fa>.

=item gto

Produce JSON-format L<GenomeTypeObject> files for the genomes.  The suffix will be C<.gto>.

=item prot

Produce protein FASTA files for the genomes.  There will be one sequence per CDS and the suffix will be C<.faa>.

=item dna

Produce DNA feature FASTA files for the genomes.  There will be one sequence per feature and the suffix will be C<.fna>.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use Stats;
use File::Copy::Recursive;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('genome1 genome2 ... genomeN', P3Utils::ih_options(), P3Utils::col_options(),
        ['outDir|o=s', 'output directory name', { default => '.'} ],
        ['missing|safe|m', 'only process new genomes without replacing files'],
        ['fasta|contigs|F', 'produce contig FASTA files for the genomes'],
        ['gto|G', 'produce GTO files for the genomes'],
        ['prot|proteins|P', 'produce feature protein FASTA files for the genomes'],
        ['dna|features|N', 'produce feature DNA FASTA files for the genomes']
        );
# Create a statistics object.
my $stats = Stats->new();
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
# Get the genome list.
print "Processing genome list.\n";
my @genomes;
for my $arg (@ARGV) {
    if ($arg =~ /^\d+\.\d+$/) {
        push @genomes, $arg;
        $stats->Add(genomesIn => 1);
    } elsif ($arg eq '-') {
        # Here we have a file of genome IDs.
        # Open the input file.
        my $ih = P3Utils::ih($opt);
        # Read the incoming headers.
        my (undef, $keyCol) = P3Utils::process_headers($ih, $opt);
        # Extract the genomes from the input.
        my $column = P3Utils::get_col($ih, $keyCol);
        my $total = scalar(@$column);
        my @good = grep { $_ =~ /^\d+\.\d+$/ } @$column;
        my $nGood = scalar @good;
        if ($nGood < $total) {
            my $bad = $total - $nGood;
            print "$bad invalid genome IDs found in input.\n";
        }
        push @genomes, @good;
        print "$nGood genome IDs read from input file.\n";
        $stats->Add(genomesRead => $nGood);
    } else {
        print "$arg is an invalid genome ID.\n";
        $stats->Add(badGenomesIn => 1);
    }
}
# Get the output directory.
my $outDir = $opt->outdir;
if (! -d $outDir) {
    print "Creating $outDir.\n";
    File::Copy::Recursive::pathmk($outDir) || die "Could not create the output directory $outDir: $!";
}
# Get the missing-files-only option.
my $missing = $opt->missing;
# Compute the output types.  Note we default to GTO if we have nothing specified.
my @types;
push @types, 'faa' if $opt->prot;
push @types, 'fasta' if $opt->fasta;
push @types, 'fna' if $opt->dna;
push @types, 'gto' if $opt->gto || ! @types;
# Loop through the genome IDs.
for my $genome (@genomes) {
    for my $type (@types) {
        my $outFile = "$outDir/$genome.$type";
        if ($missing && -s $outFile) {
            print "$outFile already exists. Skipping.\n";
            $stats->Add("$type-skipped" => 1);
        } else {
            print "Processing $type for $genome.\n";
            my $ok = Produce($p3, $type, $genome, $outFile);
            if ($ok) {
                $stats->Add("$type-built" => 1);
            } else {
                $stats->Add("$type-notFound" => 1);
            }
        }
    }
}
print "All done.\n" . $stats->Show();

## Produce output of the specified type.
sub Produce {
    my ($p3, $type, $genome, $outFile) = @_;
    # This will be the return value.
    my $retVal;
    # Process according to the type.  GTOs are special.
    if ($type eq 'gto') {
        my $gto = $p3->gto_of($genome);
        if ($gto) {
            $gto->destroy_to_file($outFile);
            $retVal = 1;
        }
    } else {
        # Here we are producing a FASTA file.  We need to form a query that gets us the ID, comment, and data for each
        # sequence.
        my $filter = [['eq', 'genome_id', $genome]];
        my $fastaLines;
        if ($type eq 'fasta') {
            # In contig mode, we want the query to return [contig-id, sequence-type, sequence].
            $fastaLines = P3Utils::get_data($p3, 'contig', $filter, ['sequence_id', 'sequence_type', 'sequence']);
        } else {
            # Here we are getting all features for a genome.
            my $sequenceField = ($type eq 'faa' ? 'aa_sequence' : 'na_sequence');
            $fastaLines = P3Utils::get_data($p3, 'feature', $filter, ['patric_id', 'product', $sequenceField]);
        }
        if (@$fastaLines) {
            # $fastaLines is now a list of triples. Write out the triples as a FASTA file.
            open(my $oh, '>', $outFile) || die "Could not open $outFile: $!";
            for my $fastaLine (@$fastaLines) {
                my ($id, $comment, $seq) = @$fastaLine;
                if ($seq) {
                    my @chunks = ($seq =~ /(.{1,60})/g);
                    print $oh ">$id $comment\n";
                    print $oh join("\n", @chunks, "");
                }
            }
            # Denote we have output.
            $retVal = 1;
        }
    }
    return $retVal;
}