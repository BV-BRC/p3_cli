use Data::Dumper;
use strict;
use warnings;
use P3Utils;
use SeedUtils;

=head1 Format Raw Data for Conversion to HTML.

     p3-format-results -d DataDirectory > condensed Output

This tool takes as input an Output Directory created by p3-related-by-clusters.
It produces a condensed text for of the computed clusters.

These text-forms can be run through p3-clusters-to-html to get versions
that can be perused by a biologist.

=head2 Parameters

There are no positional parameters.

Standard input is not used.

The additional command-line options are as follows.

=over 4

=item d DataDirectory

=item q

no STDOUT, output is in DataDirectory/labeled.

=back

=cut

my ($opt, $helper) = P3Utils::script_opts('',["d=s","a directory created by p3-related-by-clusters", { required => 1 }],["q", "no STDOUT"]);
my $outD = $opt->d;
###########
&SeedUtils::run("p3-aggregate-sss -d $outD");
###########
my @ignore = ('Mobile','mobile','transposase','Transposase');

$/ = "\n////\n";

my $sss;
open(AG,"<$outD/aggregated.sss") || die "could not open $outD/aggregated.sss";
open(PULL,">$outD/pulled")        || die "could not open $outD/pulled";
while (defined($sss = <AG>))
{
    $/ = "\n";
    if ($sss =~ /^(\S+\t\S+)\t(\d+)\n(\S.*\S)\n\/\/\n\/\/\/\/\n/s)
    {
        my($pair,$sc,$exemplars) = ($1,$2,$3);
        my $i;
        for ($i=0; ($i < @ignore) && (index($exemplars,$ignore[$i]) < 0); $i++) {}
        if ($i == @ignore)
        {
#	    print STDERR &Dumper($sss); die "HERE";
            print PULL $pair,"\t",$sc,"\n";

            my %seen;
            my @tmp = split(/\n\/\/\n/,$exemplars);
            foreach my $tmp1 (@tmp)
            {
                my $fams = join("\t",(sort map { ($_ =~ /^fig\S+\t(\S+)/) ? $1 : () } split(/\n/,$tmp1)));
                if (! $seen{$fams})
                {
                    $seen{$fams} = 1;
                    print PULL $tmp1,"\n\/\/\n";
                }
            }
            print PULL "////\n";
        }
    }
    $/ = "\n////\n";
}
$/ = "\n";
close(PULL);
close(AG);
###########

open(TMP,"p3-all-genomes --attr genome_name |") || die "could not get genome names";
my %genome_names = map { ($_ =~ /^(\S+)\t(\S.*\S)/) ? ($1 => $2) : () } <TMP>;
close(TMP);
open(IN,"<$outD/pulled") || die "could not open $outD/pulled";
open(OUT,">$outD/labeled") || die "could not open $outD/labeled";

$/ = "\n////\n";
while (defined($_ = <IN>))
{
    $/ = "\n";
    my $parsed = &parse($_,\%genome_names);
    if ($parsed)
    {
        my $exemplars = $parsed->{exemplars};
        print OUT $parsed->{pair}, "\t",$parsed->{sc}, "\n";
        print OUT join("\n//\n",@$exemplars),"\n//\n////\n";
    }
    $/ = "\n////\n";
}
close(IN);
close(OUT);
if (! $opt->q) {
    open(IN, "<$outD/labeled") || die "Empty or missing $outD/labeled";
    while (defined($_ = <IN>)) {
        print $_;
    }
    close(IN);
}

#######################
sub parse {
    my($x,$genome_names) = @_;

    if ($x =~ /^(\S+\t\S+)\t(\d+)\n(\S.*\S)\n\/\/\n\/\/\/\//s)
    {
        my($pair,$sc,$exemplars) = ($1,$2,[split(/\n\/\/\n/,$3)]);
        my @tmp_exemplars = map { ($_ =~ /fig\|(\d+\.\d+)/) ? ("$_\n###\t" . $genome_names->{$1}) : ($_ . "\nunknown")  } @$exemplars;
        return { pair => $pair, exemplars => \@tmp_exemplars, sc => $sc };
    }
    return undef;
}

sub print_parsed {
    my($x,$file) = @_;

    my $gs = $x->{gs};
    my $exemplars = $x->{exemplars};
    if (! $gs) { print "missing gs\n" }
    print $file $x->{pair}, "\t",$x->{sc}, ($gs ? "\t$gs" : '' ),"\n";
    print $file join("\n//\n",@$exemplars),"\n//\n////\n";
}

#################

