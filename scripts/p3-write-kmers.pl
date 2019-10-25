=head1 Write Kmers to Files

    p3-write-kmers.pl [options] kmerdb outDir

This script takes a L<KmerDb> as input and writes the kmer groups to flat files.  The output files will be written to the
specified output directory, and each will have as its name the group ID or name with a suffix of C<.kmer>.  The files will
not have headers, and consist of one kmer per line.

=head2 Parameters

The positional parameters are the file name of the kmer database (which must be stored in JSON format) and the name of the output
directory.

Additional command-line options are as follows.

=over 4

=item names

If specified, the group names rather than the group IDs will be used to form the output file names.

=item clear

If specified, the output directory will be emptied before processing.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use KmerDb;
use File::Copy::Recursive;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('kmerdb outDir',
        ['names', 'use group names for output files'],
        ['clear', 'erase output directory']
        );
# Get the parameters.
my ($kmerDbFile, $outDir) = @ARGV;
if (! -s $kmerDbFile) {
    die "Input file $kmerDbFile missing or empty.";
} elsif (! -d $outDir) {
    print "Creating $outDir.\n";
    File::Copy::Recursive::pathmk($outDir) || die "Could not create $outDir: $!";
} elsif ($opt->clear) {
    print "Erasing $outDir.\n";
    File::Copy::Recursive::pathempty($outDir) || die "Could not erase $outDir: $!";
}
# Get the naming mode.
my $names = $opt->names;
# Load the KMER database.
print "Loading kmer database from $kmerDbFile.\n";
my $kmerDB = KmerDb->new(json => $kmerDbFile);
# Get the list of groups.
my $groupList = $kmerDB->all_groups();
# Loop through them.  For each group we will open a file and store its handle in this hash.
my %groups;
for my $group (@$groupList) {
    my $fName = ($names ? $kmerDB->name($group) : $group) . '.kmer';
    open(my $fh, '>', "$outDir/$fName") || die "Could not open output file $fName: $!";
    $groups{$group} = $fh;
    print "File $fName created.\n";
}
# Now get all the kmers.
my $kmerList = $kmerDB->kmer_list();
my $kTot = scalar @$kmerList;
print "$kTot kmers for output.\n";
# Loop through them, writing them to files.
my $kCount = 0;
for my $kmer (@$kmerList) {
    my $groups = $kmerDB->groups_of($kmer);
    for my $group (@$groups) {
        my $fh = $groups{$group};
        print $fh "$kmer\n";
    }
    $kCount++;
    print "$kCount of $kTot processed.\n" if $kCount % 5000 == 0;
}
print "All done.\n";
