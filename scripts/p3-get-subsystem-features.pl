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

=head1 Get All the Features in One or More Subsystems

    p3-get-subsystem-features.pl [options]

This script takes as input a file of subsystem IDs (names) and lists the features in each one.  As with all database
scripts, the fields retrieved are appended to the input record.  In this case, however, the number of results returned
for each input record is expected to be very large.

Note that the returned object is a subsystem-item record.  It contains data about the feature's relationship to the
subsystem, not the feature itself.  To get feature data, pipe this command into L<p3-get-feature-data.pl>.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

=over 4

=item fields

List the available field names.

=item names

If specified, then the input is presumed to contain subsystem names (with spaces) instead of subsystem IDs (with
underscores).  Note that some subsystem names have invisible spaces at the end, and these MUST be included in the
input.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
    ['fields|f', 'Show available fields'],
    ['names|name|N', 'input contains subsystem names instead of IDs']);

# Get access to PATRIC.
my $p3 = P3DataAPI->new();
my $fields = ($opt->fields ? 1 : 0);
if ($fields) {
    my $fieldList = P3Utils::list_object_fields($p3, 'subsystemItem');
    print join("\n", @$fieldList, "");
    exit();
}
# Compute the output columns.
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, subsystemItem => $opt,
        0, [qw(patric_id role_name genome_id)]);
# Compute the filter.
my $filterList = P3Utils::form_filter($opt);
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
    if ($opt->names) {
        # Here the user specified names.  We need to convert the names to IDs.  For some unknown reason,
        # the names do not work.
        for my $couplet (@$couplets) {
            $couplet->[0] =~ tr/ /_/;
        }
    }
    # Get the output rows for these input couplets.  Note this command queries one subsytem at a time due to the
    # large dataset size.
    my $resultList = P3Utils::get_data($p3, subsystemItem => $filterList, $selectList, subsystem_id => $couplets);
    # Print them.
    for my $result (@$resultList) {
        P3Utils::print_cols($result, opt => $opt);
    }
}