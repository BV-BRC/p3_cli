#!/usr/bin/perl
use strict;
use URI::Escape;

=head1 Aggregates-to-html Produces readable summaries of Aggregates

     p3-aggregates-to-html < aggregated.clusters > readable.aggregates

This tool is part of a pipeline used to compute and display
signature clusters (clusters that characterize one subset of genomes
from another).

=head2 Parameters

There are no positional parameters.

Standard input is not used.

=head3 Example

This command is used in the tutorial "p3_signature_clusters.html ";

    p3-format-results -d Strep | p3-aggregates-to-html &gt;clusters.html

=cut
    
my $patric = "https://www.patricbrc.org/";
my $hdg=1;
my $f1;
my $f2;
my $count;
my $genome;
my $html = "";
my $tmp = "";

my $ih;
if (@ARGV) {
    open($ih, "<$ARGV[0]") || die "Could not open input file: $!";
} else {
    $ih = \*STDIN;
}
while (<$ih>) {
    if ($_ =~ '////') {
        $hdg=1;
    } elsif ($_ =~ '//$') {
         next;
    } elsif ($_ =~ '^###') {
        my ($hash, $genome) = split("\t", $_);
        #print  "<H3>$genome </H3>";
        print  "<table border=\"1\">\n";
        print "<th colspan=3><h3>$genome<h3></th>";
        print $html;
        print "</table><br><br><br>\n\n";
        $html="";
    }else {
        if ($hdg) {
              chomp($_);
              ($f1, $f2, $count) = split("\t",$_);
              print  "<H2> $f1 and $f2 <br>occur together $count times</H2>";
#              print "(<span style=\"color: blue; font-weight: 300;\">fig|nnn.n.peg.n</span> = go to Patric feature page for this peg)";
              print "<br>(<span style=\"color: blue; font-weight: 300;\">&#9400;</span> = go to compare regions for this peg)";
              print   "<H3>$genome </H3>";
              $hdg=0;
        } else {
            $html .=  "<tr>\n";
            chomp $_;
            my ($id, $fam, $func) = split("\t", $_);
            my $escId = uri_escape($id);
            my $link = $patric."view/Feature/".$escId;
            my $crlink = "http://p3.theseed.org/qa/compare_regions/$escId";
            $html .=  "<td><A HREF=\"".$link."\" target=\_blank >".$id."</A>&nbsp &nbsp";
            $html .= "<A HREF=\"".$crlink."\" target=\_blank style=\"font-size: 100%; font-weight: 300; color: blue;\">&#9400;</A></td>\n";
            my $color = "color:blue";
            if ($fam eq $f1 || $fam eq $f2) {$color="color:red";}
            my $famlink = $patric."view/FeatureList/?eq(pgfam_id,$fam)#view_tab=features";
            $html .=  "<td><A HREF=\"".$famlink."\" target=\_blank style=\"$color\">".$fam."</A></td>\n";
            $html .=  "<td>$func</td>\n";
            $html .=  "</tr>\n";
        }
    }
}

