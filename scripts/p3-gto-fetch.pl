#!/usr/bin/env perl
#
# Copyright (c) 2003-2015 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#

=head1 Copy GTOs from SubDirectories

    p3-gto-fetch.pl [options] sourceDir targetDir

This is a rather esoteric script that locates L<GenomeTypeObject> file in a set of subdirectories by genome ID.  The genome IDs
are read from the input file, and then the subdirectories are searched to find GTOs with those IDs in the names.  The GTOs are
then copied to the target directory.

=head2 Parameters

The positional parameters are the names of the source and target directories.

The standard input can be overridden using the options in L<P3Utils/ih_options>.  The column containing the genome ID
can be specified using the options in L<P3Utils/col_options>.

Additional command-line options are the following.

=over 4

=item clear

Erase the target directory if it already exists.

=item subCol

If specified, the index (1-based) or name of a column containing subdirectory names.  The GTOs will be copied into
a subdirectory of the target with the same name as the value in the column.

=back

=cut

use strict;
use P3Utils;
use File::Copy::Recursive;
use Stats;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('sourceDir targetDir', P3Utils::col_options(), P3Utils::ih_options(),
        ['subCol=s', 'column containing subdirectory names'],
        ['clear', 'erase target before copying']);
my $stats = Stats->new();
# Get the directory names.
my ($sourceDir, $targetDir) = @ARGV;
if (! $sourceDir) {
    die "No source directory specified.";
} elsif (! -d $sourceDir) {
    die "Source directory $sourceDir missing or invalid.";
} elsif (! $targetDir) {
    die "No target directory specified.";
} elsif (! -d $targetDir) {
    print "Creating $targetDir.\n";
    File::Copy::Recursive::pathmk($targetDir) || die "Could not create target directory: $!";
} elsif ($opt->clear) {
    print "Clearing $targetDir.\n";
    File::Copy::Recursive::pathempty($targetDir) || die "Could not empty target directory: $!";
}
print "Source directory is $sourceDir. Target directory is $targetDir.\n";
# Open the input file.
my $ih = P3Utils::ih($opt);
# Check for a subdirectory column.
my $subCol = $opt->subcol;
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Get the genome IDs and the output directory for each.  This is more complicated if we have a subdirectory column.
my %gHash;
if (defined $subCol) {
    $subCol = P3Utils::find_column($subCol, $outHeaders);
    # Read the genome IDs and the subdirectories.
    while (! eof $ih) {
        my ($genome, $subDir) = P3Utils::get_cols($ih, [$keyCol, $subCol]);
        my $outDir = "$targetDir/$subDir";
        if (! -d $outDir) {
            print "Creating $outDir.\n";
            File::Copy::Recursive::pathmk($outDir) || die "Could not create target directory: $!";
        }
        $gHash{$genome} = $outDir;
    }
} else {
    # Read the genome IDs only.
    my $genomes = P3Utils::get_col($ih, $keyCol);
    %gHash = map { $_ => $targetDir } @$genomes;
}
my $genomeCount = scalar keys %gHash;
my $genomeFound = 0;
print "$genomeCount genomes to find in $sourceDir.\n";
# Now we search the source directories for the GTOs.
my @stack = ($sourceDir);
while (my $dir = pop @stack) {
    # We get all the contents from this directory.  Subdirectories are stacked, and GTOs are checked against
    # the filter hash.
    print "Processing $dir.\n";
    $stats->Add(directories => 1);
    opendir(my $dh, $dir) || die "Could not open directory $dir: $!";
    my @members = grep { substr($_, 0, 1) ne '.' && -d "$dir/$_" || $_ =~ /^\d+\.\d+\.gto$/ } readdir $dh;
    for my $member (@members) {
        if ($member =~ /^(\d+\.\d+)\.gto$/) {
            $stats->Add(sourceGtoFound => 1);
            # Here we have a GTO.
            if (! $gHash{$1}) {
                $stats->Add(sourceGtoSkipped => 1);
            } else {
                my ($source, $target) = map { "$_/$member" } ($dir, $gHash{$1});
                File::Copy::Recursive::fcopy($source, $target);
                $stats->Add(sourceGtoCopied => 1);
                $genomeFound++;
            }
        } elsif (-d "$dir/$member") {
            # Here we have a sub-directory.  We add it to the stack.
            push @stack, "$dir/$member";
        }
    }
}
print "$genomeFound of $genomeCount copied.\n";
print "All done.\n" . $stats->Show();