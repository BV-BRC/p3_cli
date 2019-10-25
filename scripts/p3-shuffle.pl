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

=head1 Scramble the Records in a File

    p3-shuffle.pl [options]

This script reads a file in batches of 500,000 records at a time and writes them out in a different order.  It is used
to un-sort files for deep learning purposes.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are as follows.

=over 4

=item batchSize

Number of records to read in a batch.  The default is 500,000.

=item verbose

If specified, progress messages will be written to STDERR.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::ih_options(),
    ['batchSize=i', 'size of each batch to scramble', { default => 500000 }],
    ['verbose|debug|v', 'show progress on STDERR']);

# Open the input file.
my $ih = P3Utils::ih($opt);
# Get the options.
my $batchSize = $opt->batchsize;
my $debug = $opt->verbose;
# Set up the progress counter.
my $batchCount = 0;
# Echo to header.
my $line = <$ih>;
print $line;
# This will hold the batch.
my @lines;
# Loop until the file is empty.
while (! eof $ih) {
    $line = <$ih>;
    push @lines, $line;
    if (scalar @lines >= $batchSize) {
        Scramble(\@lines);
        @lines = ();
    }
}
if (scalar @lines > 0) {
    Scramble(\@lines);
}

sub Scramble {
    my ($lines) = @_;
    $batchCount++;
    print STDERR "Shuffling batch $batchCount.\n" if $debug;
    my $n = scalar @$lines;
    my $limit = $n - 1;
    for (my $i = 0; $i < $limit; $i++) {
        my $j = int(rand($limit - $i)) + $i;
        ($lines[$i], $lines[$j]) = ($lines[$j], $lines[$i]);
    }
    for my $line (@$lines) {
        print $line;
    }
}