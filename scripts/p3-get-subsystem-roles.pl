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

=head1 Return the Roles of a Subsystem

    p3-get-subsystem-roles.pl [options]

This script takes as input a list of subsystem IDs or names and appends the subsystem's roles.  There will always
be multiple roles per subsystem, so each input line will produce more than one output line.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/col_options> plus the following.

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
use URI::Escape;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
    ['fields|f', 'Show available fields'],
    ['names|name|N', 'input contains subsystem names instead of IDs']);

# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
$p3->set_raw(1);
my $fields = ($opt->fields ? 1 : 0);
if ($fields) {
    my $fieldList = P3Utils::list_object_fields($p3, 'subsystem');
    print join("\n", @$fieldList, "");
    exit();
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Form the full header set and write it out.
if (! $opt->nohead) {
    push @$outHeaders, 'role';
    P3Utils::print_cols($outHeaders);
}
# This is used for escaping problematic characters.
my %encode = ('<' => '%60', '=' => '%61', '>' => '%62', '"' => '%34', '#' => '%35', '%' => '%37',
              '+' => '%43', '/' => '%47', ':' => '%58', '{' => '%7B', '|' => '%7C', '}' => '%7D',
              '^' => '%94', '`' => '%96', '&' => '%26', "'" => '%27', '(' => '%28', ')' => '%29',
              ',' => '%2C');

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
    # Insure we eliminate ampersands.
    for my $couplet (@$couplets) {
        $couplet->[0] =~ s/([<=>"#%+\/:{|}\^`&'\(\)\,])/$encode{$1}/gs;
    }
    # Get the output rows for these input couplets.
    my $resultList = P3Utils::get_data_batch($p3, subsystem => [], ['role_name'], $couplets);
    # Print them.  Note that the last object will be a list of roles.
    for my $result (@$resultList) {
        my $roles = pop @$result;
        # Insure roles exist in the database.
        if (ref $roles eq 'ARRAY') {
            # Loop through the roles, printing.
            for my $role (@$roles) {
                P3Utils::print_cols([@$result, $role]);
            }
        }
    }
}