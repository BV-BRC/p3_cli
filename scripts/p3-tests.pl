use strict;
use warnings;
use FIG_Config;
use P3Utils;
use P3DataAPI;
use File::Copy::Recursive;
use Test::More;

=head1 Test P3 Script Library

    p3-tests.pl workDir

Run tests on the P3 Script Library L<P3Utils>.

=head2 Parameters

The positional parameter should be the name of a working directory to use for testing.

=cut

 use constant ROWS => [
        ['id', 'name', 'length'],
        ['385964.3', 'Yersinia pestis subsp. pestis strain 231(708)', '4568800'],
        ['1234661.4', 'Yersinia pestis subsp. pestis bv. Orientalis strain ZE94-2122', '4827235'],
        ['992176.4', 'Yersinia pestis PY-94', '4644905'],
        ['992176.5', 'Yersinia pestis PY-94', '4644905'],
        ['632.188', 'Yersinia pestis strain Algeria3', '4427555'],
        ['1345710.7', 'Yersinia pestis 1045', '4684080'],
        ['1345703.9', 'Yersinia pestis 1412', '4733482'],
        ['1345704.8', 'Yersinia pestis 1413', '4736923'],
        ['1345709.34', 'Yersinia pestis 14735', '4693748'],
        ['1345705.8', 'Yersinia pestis 1522', '4738644'],
        ['1345700.10', 'Yersinia pestis 1670', '4718815'],
 ];

 use constant EXPECTED => {
        header => ['id', 'name', 'length', 'genome.taxon_lineage_names'],
        '385964.3' => ['385964.3', 'Yersinia pestis subsp. pestis strain 231(708)', '4568800', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacterales; Yersiniaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis subsp. pestis'],
        '1234661.4' => ['1234661.4', 'Yersinia pestis subsp. pestis bv. Orientalis strain ZE94-2122', '4827235', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacterales; Yersiniaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis subsp. pestis; Yersinia pestis subsp. pestis bv. Orientalis'],
        '992176.4' => ['992176.4', 'Yersinia pestis PY-94', '4644905', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacteriales; Enterobacteriaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis PY-94'],
        '992176.5' => ['992176.5', 'Yersinia pestis PY-94', '4644905', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacteriales; Enterobacteriaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis PY-94'],
        '632.188' => ['632.188', 'Yersinia pestis strain Algeria3', '4427555', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacterales; Yersiniaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis'],
        '1345710.7' => ['1345710.7', 'Yersinia pestis 1045', '4684080', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacterales; Yersiniaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis 1045'],
        '1345703.9' => ['1345703.9', 'Yersinia pestis 1412', '4733482', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacterales; Yersiniaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis 1412'],
        '1345704.8' => ['1345704.8', 'Yersinia pestis 1413', '4736923', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacterales; Yersiniaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis 1413'],
        '1345709.34' => ['1345709.34', 'Yersinia pestis 14735', '4693748', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacterales; Yersiniaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis 14735'],
        '1345705.8' => ['1345705.8', 'Yersinia pestis 1522', '4738644', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacterales; Yersiniaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis 1522'],
        '1345700.10' => ['1345700.10', 'Yersinia pestis 1670', '4718815', 'cellular organisms; Bacteria; Pseudomonadota; Gammaproteobacteria; Enterobacterales; Yersiniaceae; Yersinia; Yersinia pseudotuberculosis complex; Yersinia pestis; Yersinia pestis 1670'],
};

use constant FTEST => ["$FIG_Config::global/ftest.tbl", '1986611.3'];

# Get the working directory.
my ($workDir) = @ARGV;
if (! $workDir) {
    die "No working directory specified.";
} elsif (-d $workDir) {
    File::Copy::Recursive::pathempty($workDir) || die "Could not clear $workDir: $!";
} else {
    File::Copy::Recursive::pathmk($workDir) || die "Could not create $workDir: $!";
}
my $inFile = "$workDir/in.tbl";
CreateInFile($inFile);
# Test delimiters.
@ARGV = ('--delim=tab');
my $opt = P3Utils::script_opts('', P3Utils::delim_options());
is(P3Utils::delim($opt), "\t", 'delim test');
is(P3Utils::undelim($opt), '\t', 'undelim test');
# Test get-couplets.
@ARGV = ('--batchSize', 7, '--col', 1, '--input', $inFile, 'parm');
$opt = P3Utils::script_opts('parameter', P3Utils::col_options(), P3Utils::ih_options());
is($opt->batchsize, 7, 'batch size opt test');
is($ARGV[0], 'parm', 'positional parameter test');
my $ih = P3Utils::ih($opt);
my ($headers, $keyCol) = P3Utils::process_headers($ih, $opt);
is($keyCol, 0, 'key column test');
is($headers->[1], 'name', 'name header test');
my $couplets = P3Utils::get_couplets($ih, 0, $opt);
is(scalar @$couplets, 7, 'couplet length test');
my $lastRow = pop @$couplets;
is($lastRow->[0], '1345703.9', 'last key test');
is($lastRow->[1][2], '4733482', 'last field test');
# Test list-fields.
my $p3 = P3DataAPI->new();
my $fieldList = P3Utils::list_object_fields($p3, 'genome');
my ($tax1) = grep { $_ =~ /taxon_lineage_ids/ } @$fieldList;
my ($tax2) = grep { $_ =~ /taxonomy/ } @$fieldList;
is($tax1, 'taxon_lineage_ids (multi)', 'multivalue field test');
is($tax2, 'taxonomy (derived)', 'derived field test');
# Test keyless headers.
close $ih;
$ih = P3Utils::ih($opt);
@ARGV = (20, 'parm');
my $altOpt = P3Utils::script_opts('count parm', ['thing=s', 'thingness'], P3Utils::col_options());
($headers, $keyCol) = P3Utils::process_headers($ih, $altOpt, 1);
ok(! defined $keyCol, 'keyless test');
# Test find_column stuff.
$keyCol = P3Utils::find_column('name', $headers);
is($keyCol, 1, 'name key column test');
my @headers = qw(genome.id type genome.name feature.type);
$keyCol = P3Utils::find_column('feature.type', \@headers);
is($keyCol, 3, 'feature.type find_column test');
$keyCol = P3Utils::find_column('type', \@headers);
is($keyCol, 1, 'type find_column test');
# Test get_col.
close $ih;
$ih = P3Utils::ih($opt);
($headers) = P3Utils::process_headers($ih, $opt, 1);
my $column = P3Utils::get_col($ih, 0);
my $errorCount = 0;
for (my $i = 0; $i < scalar @$column; $i++) {
    if ($column->[$i] ne ROWS->[$i+1][0]) {
        print "** mismatch in get_col row $i: $column->[$i] found\n";
        $errorCount++;
    }
}
is($errorCount, 0, 'get_col test');
# Test clean_value.
my $value = '   This is (very) dirty   ';
my $clean = P3Utils::clean_value($value);
is($clean,'"This is very dirty"', 'clean value test');
$value = '"This is normal"';
$clean = P3Utils::clean_value($value);
is($clean, '"This is normal"', 'quoted value test');
$value = '123.4';
$clean = P3Utils::clean_value($value);
is($clean, '123.4', 'normal value test');

# Test derived fields.
my ($genomeID, undef, undef, $taxonomy) = @{EXPECTED->{'385964.3'}};
my $results = P3Utils::get_data($p3, genome => [['eq', 'genome_id', $genomeID]], ['taxonomy']);
is(scalar @$results, 1, 'get_data length test 1');
is($results->[0][0], $taxonomy, 'derived field value test');
# Test get_data for all objects.
$results = P3Utils::get_data($p3, drug => [['eq', 'antibiotic_name', 'penicillin']], ['cas_id', 'molecular_formula']);
is(scalar @$results, 1, 'get_data length test 2');
my $result = $results->[0];
is($result->[0], '61-33-6', 'get_data field 1 test');
is($result->[1], 'C16H18N2O4S', 'get_data field 2 test');
# Test get_data for fancy filters and selects.
my $rows = ROWS;
my @rowCopy = @$rows;
shift @rowCopy; # Now we have pure genomes, no header.
my @genomeIDs = map { $_->[0] } @rowCopy;
@ARGV = ('--in', join(',', 'genome_id', @genomeIDs), '--gt', 'genome_length,4700000',
         '--attr', 'genome_id,genome_name', '--attr', 'genome_length', '--input', $inFile, '--col', 'id',
         '--delim', 'semi');
$opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::ih_options(), P3Utils::col_options());
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, genome => $opt);
is(scalar @$newHeaders, 3, 'select clause length test');
is($newHeaders->[0], 'genome.genome_id', 'select clause field 1 test');
is($newHeaders->[1], 'genome.genome_name', 'select clause field 2 test');
is($newHeaders->[2], 'genome.genome_length', 'select clause field 3 test');
my $filterList = P3Utils::form_filter($p3, $opt);
$results = P3Utils::get_data($p3, genome => $filterList, $selectList);
my %map = map { $_->[0] => $_ } @$results;
for my $row (@rowCopy) {
    my ($id, $name, $length) = @$row;
    my $found = $map{$id};
    if ($length < 4700000) {
        if ($found) {
            fail("Genome $id of length $length was returned by query.");
        }
    } elsif (! $found) {
        fail("Genome $id of length $length was not returned by query.");
    } else {
        my ($fid, $fname, $flength) = @$found;
        is($fid, $id, "id test for genome $id");
        is($fname, $name, "name test for genome $id");
        is($flength, $length, "length test for genome $id");
    }
}
# Test a full get-genome-data suite.
my $outFile = "$workDir/out.tbl";
open(my $oh, '>', $outFile) || die "Could not open test output file.\n";
@ARGV = ('--col', 'id', '--input', $inFile, '--delim', 'semi', '--attr', 'taxon_lineage_names');
$opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(), P3Utils::data_options());
($selectList, $newHeaders) = P3Utils::select_clause($p3, genome => $opt);
$filterList = P3Utils::form_filter($p3, $opt);
$ih = P3Utils::ih($opt);
($headers, $keyCol) = P3Utils::process_headers($ih, $opt);
push @$headers, @$newHeaders;
P3Utils::print_cols($headers, oh => $oh);
while (! eof $ih) {
    $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    my $resultList = P3Utils::get_data_batch($p3, genome => $filterList, $selectList, $couplets);
    for my $result (@$resultList) {
        P3Utils::print_cols($result, opt => $opt, oh => $oh);
    }
}
close $ih;
undef $ih;
close $oh;
undef $oh;
open($oh, '<', $outFile) || die "Could not re-open output file: $!";
my ($header) = P3Utils::process_headers($oh, $opt, 1);
is_deeply($header, EXPECTED->{header}, 'get_genomes header test');
while (! eof $oh) {
    $couplets = P3Utils::get_couplets($oh, 0, $opt);
    for my $couplet (@$couplets) {
        my ($id, $list) = @$couplet;
        is_deeply($list, EXPECTED->{$id}, "get_genomes test for $id");
    }
}
close $oh;
undef $oh;
my @matches = (['7', '7'], ['hardly', 'this is hardly working'], ['hypothetical protein', 'FIG00001: hypothetical protein in putative thing'], ['100', '100']);
my @fails = (['7', '8'], ['hardly', 'this is working'], ['hypothetical protein', 'this is a hypothetical fail protein'], ['frog', 'toad']);
for my $match (@matches) {
    ok(P3Utils::match($match->[0], $match->[1]), "match test for $match->[0]");
}
for my $fail (@fails) {
    ok(! P3Utils::match($fail->[0], $fail->[1]), "fail test for $fail->[0]");
}
my @want = qw(0 cas_id genome.type);
@headers = qw(name genome.type dummy1 feature.patric_id drug.cas_id dummy2 dummy3);
open($oh, ">$outFile") || die "Could not open output file: $!";
P3Utils::print_cols(\@headers, oh => $oh);
P3Utils::print_cols([9, 2, 9, 9, 1, 9, 0], oh => $oh);
close $oh;
undef $oh;
open($oh, "<$outFile") || die "Could not re-open output file: $!";
my ($tHeaders, $tCols) = P3Utils::find_headers($oh, testFile => @want);
my @found = P3Utils::get_cols($oh, $tCols);
is_deeply(\@found, [0, 1, 2], 'find_headers / get_cols test');
my $line = "a\tb\tc\r\n";
@found = P3Utils::get_fields($line);
is_deeply(\@found, ['a','b','c'], 'get_fields test');
close $oh;
undef $oh;
# Now the feature test, which is our most complex. We get EC, ID, and DNA for a whole genome.
@want = qw(patric_id ec na_sequence);
my $fTest = P3Utils::get_data($p3, feature => [['eq', 'genome_id', FTEST->[1]]], \@want);
my %fTestH = map { $_->[0] => $_ } @$fTest;
# Compare to the file.
open($ih, '<', FTEST->[0]) || die "Could not open ftest.tbl: $!";
($tHeaders, $tCols) = P3Utils::find_headers($ih, ftestFile => @want);
while (! eof $ih) {
    my ($id, $ec, $seq) = P3Utils::get_cols($ih, $tCols);
    $ec = [sort split /::/, $ec];
    my $expected = $fTestH{$id} // ['not-found', [], ''];
    is_deeply($expected, [$id, $ec, $seq], "ftest for $id");
}
close $ih; undef $ih;
#
done_testing();

######### UTILITY METHODS

sub CreateInFile {
    my ($fileName) = @_;
    open(my $oh, ">$fileName") || die "Could not create input file $fileName: $!";
    my $rows = ROWS;
    for my $row (@$rows) {
        P3Utils::print_cols($row, oh => $oh);
    }
}
