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

=head1 Return Specialty Genes of the Specified Type in One or More Genomes

    p3-get-genome-sp-genes.pl [options] property

This script returns specialty gene data for the genes in one of more genomes.  The script recognizes the following types
of specialty genes.

=over 4

=item amr

Antibiotic Resistance

=item human

Human Homolog

=item target

Drug Target

=item transporter

Transporter

=back

=head2 Parameters

The positional parameter is the type of specialty gene desired.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/data_options> and L<P3Utils/col_options> plus the following.

=over 4

=item fields

List the available field names.

=item typeNames

List the available specialty gene types.

##TODO additional options

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use constant TYPES => { human => "Human Homolog", amr => "Antibiotic Resistance", transporter => "Transporter", target => "Drug Target" };

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('property', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
    ['fields|f', 'Show available fields'],
    ['typeNames|f', 'List available specialty types']);
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
my $fields = ($opt->fields ? 1 : 0);
my $types = ($opt->typenames ? 1 : 0);
if ($fields) {
    my $fieldList = P3Utils::list_object_fields($p3, 'sp_gene');
    print join("\n", @$fieldList, "");
    exit();
} elsif ($types) {
    for my $type (sort keys %{TYPES()}) {
        print "$type\t" . TYPES->{$type} . "\n";
    }
    exit();
}
# Get the type.
my ($type) = @ARGV;
if (! TYPES->{$type}) {
    die "Invalid specialty type '$type'.";
}
# Compute the output columns.
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, sp_gene => $opt);
push @$selectList, 'property';
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
    # Get the output rows for each input couplet.
    my $resultList = P3Utils::get_data($p3, sp_gene => $filterList, $selectList, genome_id => $couplets);
    # Print them.
    for my $result (@$resultList) {
        my $actualType = pop @$result;
        if ($actualType eq TYPES->{$type}) {
            P3Utils::print_cols($result, opt => $opt);
        }
    }
}
