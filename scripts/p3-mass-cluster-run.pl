=head1 Mass Cluster Run

    p3-mass-cluster-run.pl [options] workDir outDir

This is a special-purpose script that processes the genus-species file from L<p3-genus-species.pl> as input and creates signature
cluster information for each species listed.

=head2 Parameters

The positional parameters are the name of the working directory and the name of the output directory. The working directory will
contain temporary files built by the clustering script. The output directory will contain a file called I<genus>C<.>I<species>C<.clusters.html>
containing the cluster data for the specified genus and species.

The standard input can be overridden using the options in L<P3Utils/ih_options>. The first column must contain genus names and
the second species names.

The additional command-line options are as follows.

=over 4

=item size

The size of each sample set when computing clusters. The default is C<20>.

=item iterations

The number of sampling iterations to run. The default is C<4>.

=item min

The minimum portion of occurrences for a protein family to be considered significant. The default is C<0.8>.

=item max

The maximum portion of occurrences for a protein family to be considered insignificant. The default is C<0.1>.

=item resume

If specified, genus-species combinations will be skipped if output files already exist.


=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use POSIX qw(ceil);
use File::Copy::Recursive;
use SeedTkRun;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('workDir outDir', P3Utils::ih_options(),
          ['size|n=i', 'sample size', { default => 20 }],
          ["min=f","min fraction of in-group to be signature family", { default => 0.8 }],
          ["max=f","max fraction of out-group to be signature family", { default => 0.1 }],
          ["iterations|n=i", "number of iterations to run", { default => 4 }],
          ["missing", "process new species only"]
        );
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Get the options.
my $size = $opt->size;
my $min = $opt->min;
my $max = $opt->max;
my $defaultI = $opt->iterations;
my $missing = $opt->missing;
# Get the directories.
my ($workDir, $outDir) = @ARGV;
if (! $workDir) {
    die "No working directory specified.";
} elsif (! -d $workDir) {
    print "Creating $workDir.\n";
    File::Copy::Recursive::pathmk($workDir) || die "Could not create $workDir: $!";
}
if (! $outDir) {
    die "No output directory specified.";
} elsif (! -d $outDir) {
    print "Creating $outDir.\n";
    File::Copy::Recursive::pathmk($outDir) || die "Could not create $outDir: $!";
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my $line = <$ih>;
# This will hold the current genus.
my $currentGenus = '';
# This will hold the current genome list, mapping each genome ID to its species.
my $genomesH;
# Loop through the input.
while (! eof $ih) {
    # Read in the genus and species desired.
    my ($genus, $species) = P3Utils::get_cols($ih, [0,1]);
    my $outFile = "$outDir/$genus.$species.clusters.html";
    # Only proceed if this is a new species or we are NOT in missing-mode.
    if (! $missing || ! -s $outFile) {
        # Insure this is the genus we have in memory.
        if ($genus ne $currentGenus) {
            $genomesH = ReadGenomes($p3, $genus);
            print scalar(keys %$genomesH) . " genomes found in $genus.\n";
            $currentGenus = $genus;
        }
        # Create the in-group and out-group files for this species.
        my ($inCount, $outCount) = (0, 0);
        open(my $inH, ">$outDir/in.tbl") || die "Could not open in-group output file: $!";
        print $inH "genome_id\n";
        open(my $outH, ">$outDir/out.tbl") || die "Could not open out-group output file: $!";
        print $outH "genome_id\n";
        for my $genome (keys %$genomesH) {
            if ($genomesH->{$genome} eq $species) {
                print $inH "$genome\n";
                $inCount++;
            } else {
                print $outH "$genome\n";
                $outCount++;
            }
        }
        close $inH; close $outH;
        # Compute the number of iterations.
        if (! $inCount) {
            print "No genomes found for $species. Skipping.\n";
        } elsif (! $outCount) {
            print "Only $species found in $genus. Skipping.\n";
        } else {
            my $iterations = ceil($inCount / $size);
            if ($outCount > $inCount) {
                $iterations = ceil($outCount / $size);
            }
            if ($defaultI < $iterations) {
                $iterations = $defaultI;
            }
            print "$iterations iterations recommended.\n";
            # Run the clustering.
            my $rc = system('p3-related-by-clusters', '--gs1', "$outDir/in.tbl", '--gs2', "$outDir/out.tbl", '--sz1', $size, '--sz2', $size,
                    '--min', $min, '--max', $max, '--iterations', $iterations, '--output', "$workDir/$genus");
            print "Clustering for $genus $species returned $rc.\n";
            die "Error return from clustering." if $rc;
            # Format the output.
            $rc = system('p3-format-results', '-d', "$workDir/$genus", '-q');
            print "Formatting for $genus $species returned $rc.\n";
            die "Error return from formatting." if $rc;
            open(my $oh, ">$outFile") || die "Could not open $outFile: $!";
            open(my $ch, "p3-aggregates-to-html $workDir/$genus/labeled |") || die "Could not open aggregation stream: $!";
            while (! eof $ch) {
                my $line = <$ch>;
                print $oh $line;
            }
        }
    }
}

## Read this genus into memory and return a hash.
sub ReadGenomes {
    my ($p3, $genus) = @_;
    # Read the genomes.
    print "Reading genomes for $genus.\n";
    my $genomes = P3Utils::get_data($p3, genome => [['eq', 'genome_name', $genus], ['eq', 'public', 1]],
            ['genome_id', 'genome_name']);
    # This will be our return hash.
    my %retVal;
    # Loop through the genomes read.
    for my $genome (@$genomes) {
        my ($genomeID, $name) = @$genome;
        # Only proceed for a valid genome.
        if ($genomeID) {
            my ($genus, $species) = split ' ', $name;
            if ($species =~ /sp\./) {
                $species = '';
            }
            $retVal{$genomeID} = $species;
        }
    }
    # Return the hash.
    return \%retVal;
}