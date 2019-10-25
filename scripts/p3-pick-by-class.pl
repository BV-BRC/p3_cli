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

=head1 Pick Records for Classification Training

    p3-pick-by-class.pl [options]

This script reads an entire file into memory and collates them by the key column value.  It then outputs
randomly-selected records so that the number of records with each value is roughly the same.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/col_options> (to specify the key column) plus the following.

=over 4

=item verbose

Display progress messages on the standard error output.

=item fuzz

Margin of error.  The maximum number of records associated with any key value is number times the count of the least
frequent key.  The default is 1.2.  This number must be between 1 and 2 inclusive.

=item max

The maximum number of data lines to output.  The default (X<-1>) is to output as many as possible.

=back

=cut

use strict;
use P3Utils;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(1000), P3Utils::ih_options(),
    ['verbose|debug|v', 'show progress on STDERR'],
    ['max|m=i', 'maximum number of output lines', { default => -1 }],
    ['fuzz=f', 'error multiplier', { default => 1.2 }]);
# Get the options.
my $debug = $opt->verbose;
my $fuzz = $opt->fuzz;
die "Invalid fuzz number.  Must be between 1 and 2." if $fuzz < 1 || $fuzz > 2;
my $batchSize = $opt->batchsize;
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Echo the headers to the output.
P3Utils::print_cols($outHeaders);
# We will collate the input in here.
my %classes;
my $count = 0;
while (! eof $ih) {
    my $line = <$ih>;
    my @fields = split /\t/, $line;
    my $class = $fields[$keyCol];
    $class =~ s/\r?\n//;
    push @{$classes{$class}}, $line;
    $count++;
    print STDERR "$count records processed.\n" if $debug && $count % $batchSize == 0;
}
# Find the smallest class.
my $smallest = $count;
for my $class (keys %classes) {
    my $size = scalar @{$classes{$class}};
    print STDERR "$size records of type $class.\n" if $debug;
    if ($size < $smallest) {
        $smallest = $size;
    }
}
my $max = int($smallest * $fuzz);
print STDERR "Maximum records per class is $max.\n" if $debug;
# Shuffle each class.
for my $class (keys %classes) {
    print STDERR "Shuffling records for $class.\n" if $debug;
    my $lines = $classes{$class};
    my $size = scalar @$lines;
    my $used = ($max < $size ? $max : $size);
    for (my $i = 0; $i < $used; $i++) {
        my $j = int(rand($size - $i)) + $i;
        ($lines->[$i], $lines->[$j]) = ($lines->[$j], $lines->[$i]);
    }
}
# Write the output.  We want to make sure that the extras are evenly distributed.
# Get the number of extras for each class and compute how far apart we want them.
my %xPos;
my %xSpace;
for my $class (keys %classes) {
    $xPos{$class} = $smallest;
    my $residual = scalar @{$classes{$class}};
    if ($residual > $max) {
        $residual = $max;
    }
    $residual -= $smallest;
    if (! $residual) {
        $xSpace{$class} = $smallest;
    } else {
        $xSpace{$class} = int($smallest / $residual);
    }
}
print STDERR "Writing output.\n" if $debug;
my $maxLines = $opt->max;
my $lines = 0;
my $abort;
my %counts;
for (my $i = 0; $i < $smallest && ! $abort; $i++) {
    my @buffer;
    for my $class (keys %classes) {
        my @pos = $i;
        if ($i % $xSpace{$class} == 0) {
            push @pos, $xPos{$class}++;
        }
        for my $j (@pos) {
            my $line = $classes{$class}[$j];
            if ($line) {
                push @buffer, $line;
                $counts{$class}++;
                $lines++;
            }
        }
    }
    if ($maxLines < 0 || $lines <= $maxLines) {
        print @buffer;
    } else {
        $abort = 1;
    }
}
if ($debug) {
    $lines = 0;
    for my $class (sort keys %counts) {
        print STDERR "$counts{$class} lines output for $class.\n";
        $lines += $counts{$class};
    }
    print STDERR "$lines total lines output.\n";
}
