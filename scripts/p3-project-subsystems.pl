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


use strict;
use warnings;
use P3DataAPI;
use SubsystemProjector;
use File::Copy::Recursive;
use File::Basename;
use ScriptUtils;
use GenomeTypeObject;

=head1 Project Subsystems onto BV-BRC Genomes

    p3-project-subystems.pl [ options ] outDir genome1 genome2 ... genomeN

This script will examine BV-BRC genomes and project subsystems onto them. The resulting GTOs will be output to the
specified output directory.

=head2 Parameters

The positional parameters are the name of the output directory followed by one or more BV-BRC genome IDs or GTO file
names.

The command-line options are the following:

=over 4

=item roleFile

Name of a tab-delimited file containing [role checksum, subsystem name] pairs.

=item variantFile

Name of a tab-delimited file containing in each record (0) a subsystem name, (1) a variant code, and
(2) a space-delimited list of role checksums.

=item subListFile

Name of a text file containing the subsystem role lists and classifications. This defaults to B<subList.tbl> in the
same directory as the variant file in order to create a compatible signature with the old script.

=back

=cut

$| = 1;
# Get the command-line parameters.
my $opt = ScriptUtils::Opts('outDir genome1 genome2 ... genomeN',
        ['roleFile|r=s', 'name of file containing subsystems for roles', { required => 1 }],
        ['variantFile|v=s', 'name of file containing variant maps', { required => 1}],
        ['subListFile|s=s', 'name of file containing subsystem classes and role lists']
        );
# Get the positional parameters.
my ($outDir, @genomes) = @ARGV;
# Verify the parameters.
if (! $outDir) {
    die "No output directory specified.";
} elsif (! -d $outDir) {
    print "Creating $outDir.\n";
    File::Copy::Recursive::pathmk($outDir) || die "Could not create output directory $outDir: $!";
}
if (! @genomes) {
    die "No genomes specified.";
}
# Connect to BV-BRC.
print "Connecting to BV-BRC.\n";
my $p3 = P3DataAPI->new();
# Get the subsystem list file name.
my $variantFile = $opt->variantfile;
my $subListFile = $opt->sublistfile;
if (! $subListFile) {
    # Get the directory part of the variant file.
    my $dir = dirname($variantFile);
    $subListFile = "$dir/subList.tbl";
}
# Create the subsystem projector.
print "Initializing projector.\n";
my $projector = SubsystemProjector->new($opt->rolefile, $variantFile, $subListFile);
# Get the statistics object.
my $stats = $projector->stats;
# Loop through the genomes.
for my $genome (@genomes) {
    print "Reading $genome.\n";
    my $gto;
    if (-s $genome) {
        $gto = GenomeTypeObject->create_from_file($genome);
    } else {
        $gto = $p3->gto_of($genome);
    }
    my $genomeId = $gto->{id};
    if (! $gto) {
        print "ERROR: genome not found.\n";
        $stats->Add(badGenome => 1);
    } else {
        print "Computing subsystems.\n";
        my $subsystemHash = $projector->ProjectForGto($gto, store => 1);
        my $count = scalar(keys %$subsystemHash);
        print "$count subsystems found.\n";
        my $outFile = "$outDir/$genomeId.gto";
        print "Writing output to $outFile.\n";
        $gto->destroy_to_file($outFile);
    }
}
print "All done: " . $stats->Show();
