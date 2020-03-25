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

=head1 Return Features in Specific Genome Regions

    p3-get-features-in-regions.pl [options] genomeCol contigCol startCol endCol

This script reads a list of genome coordinates and returns the features that overlap those coordinates.  The standard
input must contain four columns describing the coordinates-- genome ID, contig ID, start location, and end location.
Features that overlap the region will be retrieved and the specified feature attributes added to the end of each
input record.  Because multiple features may exist in a region, each input record may occur multiple times in the output.

=head2 Parameters

The positional parameters are the indices (1-based) or names of the genome ID column, the contig ID column, the
starting-location column, and the ending-location column in the input.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> plus the following.

=over 4

=item fields

List the available field names.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('genomeCol contigCol startCol endCol',
        P3Utils::data_options(), P3Utils::ih_options(),
        ['fields|f', 'Show available fields']);

# Get access to PATRIC.
my $p3 = P3DataAPI->new();
my $fields = ($opt->fields ? 1 : 0);
if ($fields) {
    my $fieldList = P3Utils::list_object_fields($p3, 'feature');
    print join("\n", @$fieldList, "");
    exit();
}
# Compute the output columns.
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, feature => $opt);
# Compute the filter.
my $filterList = P3Utils::form_filter($opt);
# Open the input file.
my $ih = P3Utils::ih($opt);
# Verify the positional parameters.
my @parms = @ARGV;
if (scalar @parms != 4) {
    die "There must be four positional parameters:  genomeCol contigCol startCol endCol.";
}
# Read the incoming headers and find the key columns.
my ($outHeaders, $keyCols) = P3Utils::find_headers($ih, inputFile => @parms);
# Form the full header set and write it out.
push @$outHeaders, @$newHeaders;
P3Utils::print_cols($outHeaders);
# Loop through the input.
while (! eof $ih) {
    # There is no way to do an OR in the data API, so we process one input record at a time.
    my @line = P3Utils::get_fields($ih);
    my ($genomeID, $contigID, $start, $end) = P3Utils::get_cols(\@line, $keyCols);
    # A feature overlaps if it starts on or before our end point and ends on or after our start point.
    my @filter = (@$filterList, ['eq', 'genome_id', $genomeID], ['eq', 'sequence_id', $contigID],
            ['le', 'start', $end], ['ge', 'end', $start]);
    my $resultList = P3Utils::get_data($p3, feature => \@filter, $selectList);
    # Print the features found (if any).
    for my $result (@$resultList) {
        P3Utils::print_cols([@line, @$result]);
    }
}
