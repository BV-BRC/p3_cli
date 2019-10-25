=head1 Produce a Table of Singly-Occurring Roles For Genomes

    p3-uni-roles.pl [options] outFile

Given an input list of genome IDs, this program produces a list of the roles that are singly-occurring. The output file will contain a genome
ID in the first column, the domain in the second column, the seed protein sequence in the third column, and the additional columns will contain
the IDs of the singly-occurring roles. The roles are taken from a typical B<roles.in.subsystems> file, which contains a role ID in the first
column, a role checksum in the second, and a role name in the third.

Status is displayed on the standard output.

=head2 Parameters

The positional parameter is the name of the output file.

The standard input can be overridden using the options in L<P3Utils/ih_options>. Use the options in L<P3Utils/col_options> to identify the
column containing genome IDs.

The following additional command-line options are supported.

=over 4

=item roleFile

The C<roles.in.subsystems> file containing the roles to process. This is a tab-delimited file with no headers. Each line contains
(0) a role ID, (1) a role checksum, and (2) a role name. The default is C<roles.unified> in the SEEDtk global data directory.

=item resume

Use this option to restart an interrupted job. It specifies the genome ID of the last genome processed in the previous run. New
results are appended to the output file.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use Stats;
use RoleParse;
use SeedUtils;
use IO::File;

$| = 1;
# Get the command-line options.
my $opt = P3Utils::script_opts('outFile', P3Utils::col_options(), P3Utils::ih_options(),
        ['roleFile|rolefile|r=s', 'roles.in.subsystems file containing the roles of interest',
                { default => "$FIG_Config::p3data/roles.unified" }],
        ['resume', 'restart an interrupted job']
        );
# Get the output file.
my ($outFile) = @ARGV;
if (! $outFile) {
    die "No output file specified.";
}
# Create the statistics object.
my $stats = Stats->new();
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# This hash maps a checksum to a role ID.
my %checksums;
# This tracks unique roles, an issue due to aliases.
my %roles;
my $nRoles;
# Verify that we have the role file.
my $roleFile = $opt->rolefile;
if (! -s $roleFile) {
    die "Role file $roleFile not found.";
} else {
    # Loop through the roles.
    print "Reading roles from $roleFile.\n";
    open(my $rh, "<$roleFile") || die "Could not open $roleFile: $!";
    while (! eof $rh) {
        my $line = <$rh>;
        my ($role, $checksum) = split /\t/, $line;
        $stats->Add(roleIn => 1);
        # Record this role.
        $checksums{$checksum} = $role;
        $roles{$role} = 1;
    }
    $nRoles = scalar keys %roles;
    print "$nRoles roles found in role file.\n";
}
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my (undef, $keyCol) = P3Utils::process_headers($ih, $opt);
# This will count how many times each role occurs singly.
my %totals;
# This will count the total number of genomes.
my $gCount = 0;
# Here we do the resume processing. We must get all the genome IDs to process and we must open
# the output file.
my $resume = $opt->resume;
my $genomes;
my $oh;
if (! $resume) {
    # Not resuming, get them all.
    $genomes = P3Utils::get_col($ih, $keyCol);
    # Open for replacement.
    $oh = IO::File->new(">$outFile") || die "Could not open $outFile: $!";
    # Form the full header set and write it out.
    if (! $opt->nohead) {
        P3Utils::print_cols(['genome', 'domain', 'seed_prot', 'roles'], oh => $oh);
    }
} else {
    # First, read the old file.
    print "Reading $outFile for resume processing.\n";
    open(my $xh, '<', $outFile) || die "Could not open $outFile for input: $!";
    # Skip the header.
    my $line = <$xh>;
    # Memorize the old genomes.
    my %skip;
    while (! eof $xh) {
        $line = <$xh>;
        chomp $line;
        my ($genome, undef, undef, @roles) = split /\t/, $line;
        $skip{$genome} = 1;
        $gCount++;
        for my $role (@roles) {
            $totals{$role}++;
        }
    }
    print scalar(keys %skip) . " genomes already processed.\n";
    close $xh;
    # Now get all the genomes.
    my $all = P3Utils::get_col($ih, $keyCol);
    # Keep the new ones.
    $genomes = [grep { ! $skip{$_} } @$all];
    # Open for appending.
    $oh = IO::File->new(">>$outFile") || die "Could not open $outFile: $!";
}
print scalar(@$genomes) . " genomes found in input.\n";
$stats->Add(genomesIn => scalar @$genomes);
# Insure we are single-buffered;
$oh->autoflush(1);
# Now we create a hash mapping every genome ID to its name. The name is only for status output.
print "Reading genome data.\n";
my $gHash = get_genome_data($genomes);
$genomes = [sort keys %$gHash];
my $total = scalar @$genomes;
$gCount += $total;
my $count = 0;
# Now we need to process the genomes one at a time. This is a slow process.
for my $genome (@$genomes) {
    my $domain = $gHash->{$genome}[0];
    my $name = $gHash->{$genome}[1];
    $count++;
    print "Processing $genome ($count of $total): $name\n";
    # This will hold the seed protein sequence.
    my $seedProt = '';
    # Read all the features. We will use them to fill the role hash.
    my %rCounts;
    my $features = P3Utils::get_data($p3, feature => [['eq', 'genome_id', $genome]], ['patric_id', 'product', 'aa_sequence_md5']);
    for my $feature (@$features) {
        $stats->Add(featureIn => 1);
        my ($id, $product, $md5) = @$feature;
        # Only process PATRIC features, as these have annotations we can parse.
        if ($id) {
            # Split the product into roles.
            my @roles = SeedUtils::roles_of_function($product);
            # Count the roles of interest.
            for my $role (@roles) {
                $stats->Add(roleIn => 1);
                my $checksum = RoleParse::Checksum($role);
                my $roleID = $checksums{$checksum};
                if (! $roleID) {
                    $stats->Add(roleUnknown => 1);
                } else {
                    $stats->Add(roleFound => 1);
                    $rCounts{$roleID}++;
                    if ($roleID eq 'PhenTrnaSyntAlph') {
                        my $protList = P3Utils::get_data($p3, sequence => [['eq', 'md5', $md5]], ['sequence']);
                        if (@$protList && length $protList->[0][0] > length $seedProt) {
                            $seedProt = $protList->[0][0];
                            $stats->Add(seedProt => 1);
                        }
                    }
                }
            }
        }
    }
    # Now %rCounts contains the number of occurrences of each role in this genome. We mark as found the roles that occur
    # exactly once.
    my @cols;
    for my $role (keys %rCounts) {
        if ($rCounts{$role} == 1) {
            $totals{$role}++;
            push @cols, $role;
        }
    }
    P3Utils::print_cols([$genome, $domain, $seedProt, @cols], oh => $oh);
    $stats->Add(genomesProcessed => 1);
    $stats->Add(seedProtOut => 1) if $seedProt;
}
print "Best roles.\n--------------------------------------------\n";
my $min = int($gCount * 0.90);
my @best = sort { $totals{$b} <=> $totals{$a} } grep { $totals{$_} >= $min } keys %totals;
for my $role (@best) {
    print "$role\t$totals{$role}\n";
}
print "\n";
print "All done.\n" . $stats->Show();

##
## Read the name of each genome and return a hash of id => [domain, name]
sub get_genome_data {
    my ($genomes) = @_;
    my $genomeData = P3Utils::get_data_keyed($p3, genome => [], ['genome_id', 'kingdom', 'genome_name'], $genomes, 'genome_id');
    print scalar(@$genomeData) . " genomes found in PATRIC.\n";
    my %retVal = map { $_->[0] => [$_->[1], $_->[2]] } @$genomeData;
    return \%retVal;
}
