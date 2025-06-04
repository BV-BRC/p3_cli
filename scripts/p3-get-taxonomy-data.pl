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

=head1 Get Taxonomy Data from BV-BRC

    p3-get-taxonomy-data.pl [options]

This script retrieves taxonomy data from the BV-BRC database. It supports standard filtering parameters and 
allows the specification of additional columns if desired.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

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
my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
    ['fields|f', 'Show available fields']);

# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
my $fields = ($opt->fields ? 1 : 0);
if ($fields) {
    my $fieldList = P3Utils::list_object_fields($p3, 'taxonomy');
    print join("\n", @$fieldList, "");
    exit();
}
# Compute the output columns.
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, taxonomy => $opt);
# Compute the filter.
my $filterList = P3Utils::form_filter($p3, $opt);
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Form the full header set and write it out.
if (! $opt->nohead) {
    push @$outHeaders, @$newHeaders;
    P3Utils::print_cols($outHeaders);
}
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    # Get the output rows for these input couplets.
    my $resultList = P3Utils::get_data_batch($p3, taxonomy => $filterList, $selectList, $couplets);
    # Print them.
    for my $result (@$resultList) {
        P3Utils::print_cols($result, opt => $opt);
    }
}
