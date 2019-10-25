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

=head1 Compare Two Columns in a File

    p3-compare-cols.pl [options] col1 col2

Read in a single tab-delimited file and output a comparison between two columns.  The output will be a tab-delimited
matrix indicating how many times each value in the second column occurs with each value in the first.  The number of
distinct values in the second column should be small.

=head2 Parameters

The positional parameters are positions (1-based) or names of the two columns being compared.  The first column will be
rows, and the second will be matrix columns.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

The command-line options are as follows.

=over 4

=item save

The name of a file in which to save lines where the two column values do not match.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('col1 col2', P3Utils::ih_options(),
        ['save=s', 'file in which to save mismatches']
        );

# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers and find the columns of interest.
my ($col1, $col2) = @ARGV;
die "Insufficient input parameters.  Two columns required." if ! defined $col2;
my ($inHeaders, $keyCols) = P3Utils::find_headers($ih, input => $col1, $col2);
# Get the save file set up.
my $vh;
if ($opt->save) {
    open($vh, '>', $opt->save) || die "Could not open save file: $!";
    P3Utils::print_cols($inHeaders, oh => $vh);
}
# This 2D hash matrix will contain the counts.
my %counts;
# This tracks the column-2 values.
my %values;
# Loop through the input.
while (! eof $ih) {
    my $line = <$ih>;
    my ($val1, $val2) = P3Utils::get_cols($line, $keyCols);
    $counts{$val1}{$val2}++;
    $values{$val2} = 1;
    if ($vh && $val1 ne $val2) {
        print $vh $line;
    }
}
# Now produce the output.
my @values = sort keys %values;
P3Utils::print_cols([$col1, @values]);
for my $key (sort keys %counts) {
    my $subCounts = $counts{$key};
    my @line = $key;
    for my $value (@values) {
        push @line, ($subCounts->{$value} || 0);
    }
    P3Utils::print_cols(\@line);
}
