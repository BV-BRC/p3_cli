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

=head1 Compute Checksums for Whole Genome Sequences

    p3-genome-md5.pl [options]

This script will compute an MD5 checksum for a genome's complete DNA sequence.  Every genome with identical contigs
(that is, the same number of contigs, with the same sequence content) will hash to the same MD5.  The genomes must
be in PATRIC, and the genome IDs are taken from the standard input.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>. The options in K<P3Utils/col_options> can
be used to select the column containing the genome ID.

Additional command-line options are the following.

=over 4

=item restart

Restart after a run that ended in error.  No headers will be output, and all genomes up to and including the one
identified by this parameter will be skipped.

=item verbose

Display debug information on STDERR.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use MD5Computer;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(),
    ['restart=s', 'Restart after the specified genome'],
    ['verbose|debug|v', 'display debug information on STDERR']);

# Get access to PATRIC.
my $p3 = P3DataAPI->new();
if ($opt->verbose) {
    $p3->debug_on(\*STDERR);
}
# Check for restart.
my $restart = $opt->restart;
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Form the full header set and write it out.
if (! $opt->nohead && ! $restart) {
    push @$outHeaders, 'genome_md5';
    P3Utils::print_cols($outHeaders);
}
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    # Process each genome individually.
    for my $couplet (@$couplets) {
        my ($genome, $line) = @$couplet;
        if ($restart) {
            # Here we are skipping until we find the specified genome.
            if ($restart eq $genome) {
                $restart = "";
            }
        } else {
            # Here we want to process this genome.
            my $md5Engine = MD5Computer->new();
            # Get all the contigs for the genome.
            my $contigs = P3Utils::get_data($p3, contig => [['eq', 'genome_id', $genome]], ['sequence_id', 'sequence']);
            # Compute the MD5.
            for my $contig (@$contigs) {
                $md5Engine->ProcessContig($contig->[0], [$contig->[1]]);
            }
            my $md5 = $md5Engine->CloseGenome();
            P3Utils::print_cols([@$line, $md5]);
        }
    }
}