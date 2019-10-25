=head1 Find Discriminating Kmers in Big Groups

    p3-discriminating-kmers.pl [options] file1 file2 ... fileN

This script reads sequences from multiple tab-delimited files.  The files must all have the same column format.  If the
input column is specified as a column index, then the sequences must be in the same column.  If it is specified as a column
name, then the sequence columns must all have the same name.  If one file is FASTA, all of them must be FASTA.

Each file is presumed to contain sequences from a single group.  We will output a json-format kmer database containing
discriminators For each group.

The name of each group will be the base name of the incoming file.  If two incoming files have the same base name this means
they will be considered part of the same group.

Progress messages will be written to the standard output.

=head2 Parameters

The positional parameters are the names of the input files.

Additional command-line options are those given in L<P3Utils/col_options> (to specify the index or name of the column containing the
sequences) plus the following options.

=over 4

=item fasta

If specified, the input files are presumed to be FASTA files.

=item groups

If specified, a comma-delimited list of group names.  There must be one per input file, and they will override the file names
when computing the group names.  If multiple groups have the same name, they will be treated as a single group.

=item kmer

The kmer size, in characters. The default is C<8> normally, and C<14> for DNA sequences.

=item dna

If specified, the sequences are treated as DNA instead of proteins.

=item output

The name of the output file.  The default is C<discrim.json> in the current directory.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use KmerDb;
use File::Basename;
use FastA;
use TabFile;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('file1 file2 ... fileN', P3Utils::col_options(),
        ['fasta', 'input files are FASTA, not tab-delimited'],
        ['groups=s', 'group names to assign to the input file'],
        ['kmer|K=i', 'kmer size'],
        ['output=s', 'name of the JSON output file', { default => 'discrim.json'}],
        ['dna', 'treat sequences as DNA']
        );
# Determine the input style.
my $fasta = $opt->fasta;
# Determine the sequence style.
my $dna = $opt->dna || 0;
my $K = $opt->kmer // ($dna ? 14 : 8);
print 'Input is ' . ($fasta ? 'FASTA' : 'tab-delimited') . ' format with ' . ($dna ? 'DNA' : 'protein') . " kmers of size $K.\n";
# Get the input files and group names.
my @files = @ARGV;
my @groups = split /,/, ($opt->groups // '');
my $fileCount = scalar(@files);
# This hash will map each group name to a group ID.
my %groups;
# This contains the next available group ID.
my $nextGroup = 1;
# Loop through the input files.
for (my $i = 0; $i < $fileCount; $i++) {
    my $file = $files[$i];
    if (! -s $file) {
        die "File $file missing, invalid, or empty.";
    } else {
        my $name = $groups[$i];
        if (! $name) {
            ($name) = fileparse($file);
            $name =~ s/\.\w+$//;
            $groups[$i] = $name;
        }
        if (!$groups{$name}) {
            $groups{$name} = $nextGroup;
            $nextGroup++;
        }
    }
}
my $groupCount = $nextGroup - 1;
print "$groupCount input groups found in $fileCount files.\n";
# Get the output file.  We do this now so that we don't spend days crunching kmers only to find out later we can't
# write the results.
open(my $oh, '>', $opt->output) || die "Could not open output file: $!";
# Create the Kmer Database.
my $kmerDB = KmerDb->new(kmerSize => $K, maxFound => 0, mirror => $dna);
# Loop through the input files.
for (my $i = 0; $i < $fileCount; $i++) {
    # Get this file.
    my $file = $files[$i];
    my $group = $groups[$i];
    my $groupID = $groups{$group};
    print "Processing $file.\n";
    my $ih;
    # This will hold the index of the key column, or C<undef> if this is a FASTA file.
    my $keyCol;
    if ($fasta) {
        $ih = FastA->new($file);
    } else {
        open(my $fh, '<', $file) || die "Could not open $file: $!";
        (undef, $keyCol) = P3Utils::process_headers($fh, $opt);
        $ih = TabFile->new($fh, 0, $keyCol);
    }
    # Now loop through the input records, collecting sequences.
    my $lineCount = 0;
    while ($ih->next) {
        $lineCount++;
        $kmerDB->AddSequence($groupID, $ih->left, $group);
        print "$lineCount sequences read.\n" if $lineCount % 1000 == 0;
    }
    print "$lineCount sequences in file.\n";
}
print "Computing discriminators.\n";
$kmerDB->ComputeDiscriminators();
print "Saving to output.\n";
$kmerDB->Save($oh);
