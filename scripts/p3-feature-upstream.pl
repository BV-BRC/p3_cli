=head1 Find Upstream DNA Regions

    p3-feature-upstream.pl [options] parms

This script takes as input a file of feature IDs. For each feature, it appends the upstream region on the input record.
Use the C<--downstream>) option to get the downstream regions instead.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are those given in L<P3Utils/col_options> plus the following.

=over 4

=item downstream

Display downstream instead of upstream regions.

=item length

Specifies the length to display upstream. The default is C<100>.

=item in

Specifies the length to display inside the feature.  The default is C<0>, indicating none.

=item verbose

Show data API trace messages on STDERR.

=back

=head3 Example

This command is shown in the tutorial p3_common_tasks.html

p3-echo -t genome_id 1313.7001 | p3-get-genome-features --eq feature_type,CDS --attr patric_id --attr product | p3-feature-upstream --col=feature.patric_id

genome_id   feature.patric_id   feature.product upstream
1313.7001   fig|1313.7001.peg.1182  beta-glycosyl hydrolase ttgtcatctcctcttgactctcgttaatataagaaataaaataagggcgttgatttatataatcgctatcaatataacaatgcaatcaggaggttttgca
1313.7001   fig|1313.7001.peg.1189  IMP cyclohydrolase (EC 3.5.4.10) / Phosphoribosylaminoimidazolecarboxamide formyltransferase (EC 2.1.2.3)   gatcaatatcttaggtatgcttagccttggttttgcttatcttgttttactgttactgcatttaattggtgtttaactaatgattaaaaaggagaatata
...

=cut

use strict;
use P3DataAPI;
use P3Utils;
use SeedUtils;

# These are the instructions for finding the desired DNA. + means go to the left, - means go to the right.
use constant RULES => { downstream => { '+' => '+', '-' => '-' },
                        upstream => { '+' => '-', '-' => '+'} };

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(10), P3Utils::ih_options(),
        ['downstream|down|d', 'display downstream rather than upstream'],
        ['length|l=i', 'length outside the feature to display', { default => 100 }]
        );
# Get the options.
my $type = ($opt->downstream ? 'downstream' : 'upstream');
my $len = $opt->length;
my $inLen = $opt->in;
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
if ($opt->debug) {
    $p3->debug_on(\*STDERR);
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
if (! $opt->nohead) {
    # Form the full header set and write it out.
    push @$outHeaders, $type;
    P3Utils::print_cols($outHeaders);
}
# We will stash contigs in here for re-use.
my %contigs;
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    # Get the location information for each feature.
    my $locData =  P3Utils::get_data_keyed($p3, feature => [], [qw(patric_id sequence_id start end strand na_sequence)], [map { $_->[0] } @$couplets]);
    # Compute the sequences that we don't know yet.
    my @newSeqs = grep { ! $contigs{$_} } map { $_->[1] } @$locData;
    if (@newSeqs) {
        my $seqClause = '(' . join(',', @newSeqs) . ')';
        my @seqData = $p3->query(genome_sequence => [qw(select sequence_id sequence)], ['in', 'sequence_id', $seqClause]);
        for my $seqDatum (@seqData) {
            $contigs{$seqDatum->{sequence_id}} = $seqDatum->{sequence};
        }
    }
    # Convert the location data into a hash.
    my %locs = map { $_->[0] => $_ } @$locData;
    undef $locData;
    # Now we need to find the upstream DNA for each feature.
    for my $couplet (@$couplets) {
        my ($fid, $line) = @$couplet;
        my $locDatum = $locs{$fid};
        my $strand = $locDatum->[4];
        my $rule = RULES->{$type}{$strand};
        # Get the length of the sequence.
        my $seqLen = length($contigs{$locDatum->[1]});
        # The rule now tells us where to find the DNA.
        my ($x0, $n);
        if ($rule eq '-') {
            my $end = $locDatum->[2] - 1;
            $x0 = ($end < $len ? 0 : $end - $len);
            $n = $end - $x0;
        } else {
            $x0 = $locDatum->[3];
            my $end = $x0 + $len;
            $n = ($end > $seqLen ? $seqLen - $x0 : $len);
        }
        my $dna = lc substr($contigs{$locDatum->[1]}, $x0, $n);
        if ($strand eq '-') {
            $dna = SeedUtils::rev_comp($dna);
        }
        # Now append the instream data.
        if ($opt->downstream) {
            $dna = (uc substr($locDatum->[5], -$inLen)) . $dna;
        } else {
            $dna .= uc substr($locDatum->[5], 0, $inLen);
        }
        push @$line, $dna;
        P3Utils::print_cols($line, opt => $opt);
    }
}
