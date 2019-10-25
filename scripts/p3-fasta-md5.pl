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

=head1 Compute the Whole-Sequence MD5 from a FASTA File

    p3-fasta-md5.pl [options]

This script computes the whole-genome MD5 checksum from a genome's FASTA file.  This can be used to
determine if two genomes have identical DNA.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.  The input should be a DNA FASTA file.

The checksum will be produced on the standard output.

=cut

use strict;
use MD5Computer;
use P3Utils;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('parms', P3Utils::ih_options(),
    );
# Open the input file.
my $ih = P3Utils::ih($opt);
# Initialize the MD5 object.
my $md5engine = MD5Computer->new();
# Loop through the input.
while (! eof $ih) {
    my $line = <$ih>;
    if ($line =~ /^>(\S+)/) {
        # Header, so start a new contig.
        $md5engine->StartContig($1);
    } else {
        # Data, so add it to this contig.
        $line =~ s/\r*\n$//;
        $md5engine->AddChunk($line);
    }
}
my $md5 = $md5engine->CloseGenome();
print "$md5";
