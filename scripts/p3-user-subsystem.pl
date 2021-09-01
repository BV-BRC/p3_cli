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

=head1 Create a Spreadsheet for a Custom Subsystem

    p3-user-subsystem.pl [options] featureGroup1 featureGroup2 ... featureGroupN

This script takes as input the names of one or more feature groups and builds a subsystem
spreadsheet.  The spreadsheet is output in both tab-delimited and HTML formats.

The features listed in the feature groups define subsystem variants.  The subsystem may then be projected onto each genome
in an optionally-specified genome group.  Projection is done using protein families.

=head2 Parameters

The positional parameters are the name of the subsystem and the names or one or more feature groups.

The command-line options are the following

=over 4

=item outDir

The name of an output directory into which the output files C<spreadsheet.txt> and C<spreadsheet.html> will be written.  The default
is the current directory.

=item genomes

The name of a genome group.  If specified, the subsystem will be projected onto the genomes in this group.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use Cwd;
use JSON::XS;
use P3WorkspaceClient;
use Data::Dumper;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('subName featureGroup1 featureGroup2 ... featureGroupN',
    ['genomes|g=s', 'name of a genome group onto which the subsystems should be projected'],
    ['outDir|o=s', 'output directory for subsystem spreadsheet files', { default => getcwd() }]);

# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
# Connect to the workspace.
my $ws = P3WorkspaceClientExt->new();
if (! $ws->{token}) {
    die "You must login with p3-login.";
}
# Get the groups.
my $genomeGroup = $opt->genomes;
my ($subName, @featureGroups) = @ARGV;
if (! @featureGroups) {
    die "At least one feature group must be specified.";
}
# Check the output directory.
my $outDir = $opt->outdir;
if (! -d $outDir) {
    die "Invalid output directory $outDir specified.";
}
# Get a complete list of features.
my @fids;
for my $featureGroup (@featureGroups) {
    my $fids = getGroup(feature => $featureGroup);
    push @fids, @$fids;
}
my $fCount = scalar @fids;
print "Retrieving $fCount features.\n";
# Now we need to read all these features.  For each feature, we need the genome ID and name, the patric_id, the function, and the PGFAM ID.
my $flist = getFeatures(\@fids);
# Now organize the features.  This contains the name of each genome.
my %genomes;
# This maps each family ID to its function.
my %roles;
# This maps each genome to its family list.
my $rows;
# Loop through the features.
for my $fData (@$flist) {
    my ($genomeID, $genomeName, $fid, $product, $pgfam) = @$fData;
    $genomes{$genomeID} = $genomeName;
    $roles{$pgfam} = $product;
    push @{$rows->{$genomeID}}, $pgfam;
}
print scalar(keys %genomes) . " genomes and  " . scalar(keys %roles) . " protein families found.\n";
# Consolidate duplicate variants.
$rows = deleteDuplicates($rows);
print scalar(keys %$rows) . " unique variants found.\n";
# Now get the genomes in the genome group.
if ($genomeGroup) {
    my $genomes = getGroup(genome => $genomeGroup);
    my $gList = P3Utils::get_data_keyed($p3, genome => [], ['genome_id', 'genome_name'], $genomes);
    for my $gData (@$gList) {
        my ($genomeID, $genomeName) = @$gData;
        $genomes{$genomeID} = $genomeName;
    }
}
print scalar(keys %genomes) . " genomes will be in the spreadsheet.\n";
# The initial spreadsheet is a two-level hash.  The top level is a family ID.  Each family has a hash based on genome ID containing a list of pegs.
my %ssHash;
# This tracks the variant for each genome.
my %variants;
# This is the PGFAM filter for features.
my $pgFilter = ['in', 'pgfam_id', '(' . join(",", keys %roles) . ')'];
# Now we project the subsystems onto the genomes.
for my $genome (sort keys %genomes) {
    my $name = $genomes{$genome};
    print "Projecting onto $genome: $name.\n";
    my %fams;
    $flist = P3Utils::get_data($p3, feature => [['eq', 'genome_id', $genome], $pgFilter], ['patric_id', 'pgfam_id']);
    for my $fData (@$flist) {
        my ($fid, $family) = @$fData;
        push @{$ssHash{$family}{$genome}}, $fid;
        $fams{$family} = 1;
    }
    # %fams now contains the families.  Loop through the variants until we find the first match.
    my $vFound;
    my $vCode = 1;
    while (exists $rows->{$vCode} && ! $vFound) {
        my @variant = grep { ! $fams{$_} } @{$rows->{$vCode}};
        if (! @variant) {
            $vFound = $vCode;
        } else {
            $vCode++;
        }
    }
    $vFound //= "inactive";
    $variants{$genome} = $vFound;
    print "Variant $vFound assigned to $genome.\n";
}
# Now we have enough information to build the spreadsheet.  We build a flat file and an HTML file.
print "Initializing output.\n";
open(my $oh, '>', "$outDir/spreadsheet.txt") || die "Could not open text output: $!";
open(my $wh, '>', "$outDir/spreadsheet.html") || die "Could not open HTML output: $!";
initializeHTML($wh, $subName);
my @fams = sort keys %roles;
# Now we need to build a table of abbreviations for these roles.
my %prefixHash;
my @abbrs = map { magicName($roles{$_}, \%prefixHash) } @fams;
# The top portion maps abbreviations to roles.
print "Writing role table.\n";
startHtmlTable($wh, 'Role Mappings', 'abbr', 'pgfam_id', 'function');
for (my $i = 0; $i < scalar @fams; $i++) {
    my $fam = $fams[$i];
    my $abbr = $abbrs[$i];
    my $fun = $roles{$fam};
    my $famLink = qq(<a href="https://www.patricbrc.org/view/FeatureList/?eq(pgfam_id,$fam)#view_tab=overview" target="_blank">$fam</a>);
    writeRow($oh, $abbr, $fam, $fun);
    writeHtmlRow($wh, $abbr, $famLink, $fun);
}
endHtmlTable($wh);
# Now we must write the spreadsheet.
print $oh "//\n";
print "Writing spreadsheet.\n";
startHtmlTable($wh, "Subsystem Spreadsheet", "genome", "name", "var", @abbrs);
for my $genome (sort keys %genomes) {
    my $name = $genomes{$genome};
    my $gLink = qq(<a href="https://www.patricbrc.org/view/Genome/$genome" target="_blank">$genome</a>);
    # Build the spreadsheet cells.
    my @cells;
    my @htmlCells;
    for (my $i = 0; $i < scalar @fams; $i++) {
        my $cell = $ssHash{$fams[$i]}{$genome};
        if (! $cell) {
            # Here we have an empty cell.
            push @cells, "";
            push @htmlCells, "&nbsp;";
        } else {
            # Here we have multiple genomes in the cell.
            push @cells, join(", ", @$cell);
            my $htmlCell = join(", ", map { qq(<a href="https://www.patricbrc.org/view/Feature/$_#view_tab=overview" target="_blank">$_</a>)} @$cell);
            # We need to fix the vertical bar, but only the first occurrence inside the URL.
            $htmlCell =~ s/fig\|/fig%7C/;
            push @htmlCells, $htmlCell;
        }
    }
    writeRow($oh, $genome, $name, $variants{$genome}, @cells);
    writeHtmlRow($wh, $gLink, $name, $variants{$genome}, @htmlCells);
}
# Finish the HTML.
endHtmlTable($wh);
print $wh "</body></html>\n";

##
## Write flat-file row
##
sub writeRow {
    my ($oh, @cols) = @_;
    print $oh join("\t", @cols) . "\n";
}

##
## Open an HTML table
##
sub startHtmlTable {
    my ($wh, $title, @cols) = @_;
    print $wh qq(<div class="wrapper"><h2>$title</h2>\n<table class="p3basic">\n);
    print $wh "<tr>" . join("", map { "<th>$_</th>" } @cols) . "</tr>\n";
}

##
## Write a table row
##
sub writeHtmlRow {
    my ($wh, @cols) = @_;
    print $wh "<tr>" . join("", map { "<td>$_</td>" } @cols) . "</tr>\n";
}

##
## Close an HTML table
##
sub endHtmlTable {
    my ($wh) = @_;
    print $wh "</table>\n";
}

##
## Output the header and title for the subsystem HTML page.
##
sub initializeHTML {
    my ($wh, $name) = @_;
    my $start = <<END
<!doctype html>
<html><head><title>Subsystem Spreadsheet</title>
<link rel="stylesheet" href="https://bioseed.mcs.anl.gov/~parrello/SEEDtk/css/p3.css" type="text/css">
<style type="text/css">	table.p3basic th {
        background-color: #c8c8c8;
    }
    table.p3basic th.num, table.p3basic td.num {
        text-align: right;
    }
    table.p3basic th.flag, table.p3basic td.flag {
        text-align: center;
    }
   h1, h2 {
        font-weight: bolder;
    }
   h1, h2, p, ul {
        margin: 12px 12px 0px 12px;
    }
   table.p3basic ul {
        margin: 0px;
        list-style: disc outside none;
        padding-left: 20px;
    }
   table.p3basic li {
        margin: 3px 0px;
    }
   div.wrapper {
       margin: 12px;
   }
   div.shrinker {
       margin: 12px;
       display: inline-block;
       min-width: 0;
       width: auto;
   }
   li {
        margin: 6px 12px 0px 12px;
    }
    table.p3basic {
        display:table;
    }
</style></head><body class="claro">
END
;
    print $wh $start;
    print $wh "<h1>$subName</h1>\n";
}

## This converts the incoming hash of genomeID => [fam1, fam2, .... famN] to a projector hash.
## The projector hash maps variant codes to sorted lists of family IDs.  We use a temporary hash
## to weed out duplicates.
##
sub deleteDuplicates {
    my ($inRows) = @_;
    my $outRows = {};
    # This is used to compute variant codes.
    my $vCode = 1;
    # This will be the buffer for the unique variants.
    my @vLists;
    # This will contain all of the row sets currently known.
    my %dups;
    # Loop through the genomes.
    for my $genome (keys %$inRows) {
        my @variant = sort @{$inRows->{$genome}};
        my $dupCheck = join(" ", @variant);
        if (! $dups{$dupCheck}) {
            push @vLists, [scalar @variant, \@variant];
            $dups{$dupCheck} = 1;
        }
    }
    # Now build the variants, from largest to smallest.
    @vLists = sort { $b->[0] <=> $a->[0] } @vLists;
    for my $vList (@vLists) {
        $outRows->{$vCode} = $vList->[1];
        $vCode++;
    }
    return $outRows;
}

##
## Return a reference to a list of the IDs in the specified group.  $type is the type of group (genome, feature) and $path
## is the full path to the group definition.
##
use constant FIELDS => { genome => 'genome_id', feature => 'feature_id' };
sub getGroup {
    my ($type, $path) = @_;
    print "Retrieving $type group $path.\n";
    my $raw_group = $ws->get({ objects => [$path]});
    my ($meta, $data_json) = @{$raw_group->[0]};
    my $data = decode_json($data_json);
    my $retVal = $data->{id_list}->{FIELDS->{$type}} // [];
    return $retVal;
}

##
## Return a list of feature descriptors.  Each descriptor is [genome_id, genome_name, patric_id, product, pgfam_id]
## The input is a list of feature IDs.
##
sub getFeatures {
    my ($fids) = @_;
    my $retVal = P3Utils::get_data_keyed($p3, feature => [], ['genome_id', 'genome_name', 'patric_id', 'product', 'pgfam_id'], $fids, 'feature_id');
    return $retVal;
}

##
## Compute a magic name for a role.  We need the name and the prefix/suffix hash.
##
use constant LITTLES => { 'and' => 1, 'or' => 1, the => 1, a => 1, of => 1, in => 1, an => 1, to => 1, on => 1 };

sub magicName {
    # Get the parameter.
    my ($name, $prefixHash) = @_;
    # Translate the Unicode entities.
    while ($name =~ /^(.*?)\&#(\d+)(.+)/) {
        # Extract the unicode entity.
        my ($first, $uni, $last) = ($1, $2, $3);
        # Get its full name. If it has none, just keep the number.
        my $phrase = charnames::viacode($uni) // $uni;
        # Get the last word.
        if ($phrase =~ /(\S+)$/) {
            $uni = $1;
        }
        # Insert the translation.
        $name = "$first $uni $last";
    }
    # Clean what's left and split it into words. Note we remove parenthetical sections.
    $name =~ s/\(.+?\)/ /g;
    $name =~ s/\W+/ /g;
    my @words = split /\s+/, $name;
    # Build a string of the words. We stop building at
    # 16 characters. Since we never add more than 4, this
    # means the maximum is 19, leaving 5 digits for
    # uniqueness numbering.
    my $prefix = "";
    while (length($prefix) < 16 && scalar(@words)) {
        my $word = shift @words;
        if ($word =~ /^(\d)$/) {
            # For a number, use the first digit.
            $prefix .= $1;
        } elsif (! LITTLES->{lc $word}) {
            # We ignore common little words. For
            # others, we take the first four characters.
            $prefix .= substr(ucfirst lc $word, 0, 4);
        }
    }
    # The default suffix is none.
    my $suffix = "";
    # Insure we don't end with a digit. If we do, we
    # start with a suffix of 1.
    if ($prefix =~ /\d$/) {
        $prefix .= "n";
        $suffix = 1;
    }
    my $retVal;
    if (! $prefixHash->{$prefix}) {
        $retVal = $prefix . $suffix;
        $prefixHash->{$prefix} = 2;
    } else {
        $retVal = $prefix . $prefixHash->{$prefix};
        $prefixHash->{$prefix}++;
    }
    return $retVal;
}


