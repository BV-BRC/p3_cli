=head1 Create GTO Files from BV-BRC Genomes

    p3-gto.pl [options] genome1 genome2 ... genomeN

This script creates L<GenomeTypeObject> files for the specified BV-BRC genomes. Each file is named using the genome ID with the suffix C<.gto>
and placed in the current directory. The C<--outDir> option can be used to specify an alternate output directory. Existing files will be
replaced.

=head2 Parameters

The positional parameters are the IDs of the genomes to extract. A parameter of C<-> indicates that the standard input contains a
list of genome IDs to process. The options in L<P3Utils/col_options> can be used to specify the input column and L<P3Utils/ih_options> can
be used to modify the standard input.

In addition, the following command-line options can modify the default behavior.

=over 4

=item outDir

Name of the directory in which to put the output files. (The default is the current working directory.)

=item missing

Only process genomes for which files do not yet exist in the output directory. The default is to replace existing files.

=item verbose

Display data API status messages in the standard output.

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
        ['debug|verbose|v', 'display data API status messages in the standard output']
        );
# Create a statistics object.
my $stats = Stats->new();
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
if ($opt->debug) {
    $p3->debug_on(\*STDOUT);
}
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
my ($count, $total) = (0, scalar @genomes);
# Loop through the genome IDs.
for my $genome (@genomes) {
    my $outFile = "$outDir/$genome.gto";
    $count++;
    if ($missing && -s $outFile) {
        print "$outFile already exists. Skipping.\n";
        $stats->Add(genomesSkipped => 1);
    } else {
        print "Processing $genome ($count of $total).\n";
        my $gto = $p3->gto_of($genome);
        if ($gto) {
            $gto->destroy_to_file($outFile);
            $stats->Add(gtoBuilt => 1);
        } else {
            print "$genome not found in BV-BRC.\n";
            $stats->Add(genomeNotFound => 1);
        }
    }
}
print "All done.\n" . $stats->Show();
