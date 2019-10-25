=head1 Analyze Genome Typed Objects

    p3-gto-scan.pl [options] gto1 gto2 ... gtoN

This script produces a report about the role profile of one or more L<GenomeTypeObject> instances. The GTOs must be
provided as files in JSON format. Each role will be converted to an MD5 role ID and counted. The counts are then
compared. Finally, there will be statistics on the number of features and the DNA sequence length. These are
normally placed at the end of the report, but can be rerouted to the standard error output.

Status of the script is written to the standard error output. The standard output contains the actual report.

=head2 Parameters

The positional parameters are the names of the GTO files.  There must be at least one (although a comparison of
one is trivial and just gives you a summary of the one). All files must encode the
GTO in JSON format. (This is consistent with the output from L<p3-rast.pl> and L<p3-gto.pl>.)

The command-line options are those in L<P3Utils/delim_options> plus the following.

=over 4

=item features

If specified, the features containing each role will be listed on the output.

=item peg

If specified, only protein-encoding features will be processed.

=item verbose

If specified, all roles will be displayed, rather than only the roles that differ between genomes.

=back

=cut

use strict;
use P3Utils;
use GenomeTypeObject;
use RoleParse;
use SeedUtils;
use Stats;

# Get the command-line options.
my $opt = P3Utils::script_opts('gto1 gto2 ... gtoN', P3Utils::delim_options(),
        ['features|f', 'display feature IDs'],
        ['peg|p', 'only process protein-encoding features'],
        ['verbose|v', 'display all roles']);
# Create the statistics object.
my $stats = Stats->new();
# Get the GTO files.
my @gtoFiles = @ARGV;
my $gtoCount = scalar(@gtoFiles);
if (! $gtoCount) {
    die "No GTO file names specified.";
}
# This hash counts role IDs.
my %roleCounts;
# This hash maps role IDs to names.
my %roles;
# This hash tracks feature IDs for each role.
my %roleFeats;
# This hash remembers the ID for each function.
my %funHash;
# This array counts the DNA.
my @dna;
# This array counts the features.
my @feats;
# This is the index of the current GTO.
my $i = 0;
# Loop through the GTO files.
for my $gtoFile (@gtoFiles) {
    # Get the actual GTO.
    if (! -s $gtoFile) {
        die "$gtoFile not found or empty.";
    }
    my $gto = GenomeTypeObject->create_from_file($gtoFile);
    print STDERR "Processing contigs of $gtoFile.\n";
    # Read through the contigs to get the DNA length.
    my $dnaLen = 0;
    my $contigsL = $gto->{contigs};
    for my $contig (@$contigsL) {
        my $len = length($contig->{dna});
        $dnaLen += $len;
        $stats->Add(contigs => 1);
        $stats->Add(dna => $len);
    }
    $dna[$i] = $dnaLen;
    # Read through the features to get the roles.
    print STDERR "Processing features of $gtoFile.\n";
    my $featCount = 0;
    my $featuresL = $gto->{features};
    for my $feature (@$featuresL) {
        if ($feature->{type} ne 'CDS' && $opt->peg) {
            $stats->Add(nonPegSkipped => 1);
        } else {
            $featCount++;
            $stats->Add(features => 1);
            # Compute the function ID. The function ID will be a list of role IDs, which
            # are computed using the role checksum function.
            my $funID;
            my $function = $feature->{function};
            if (! $function) {
                $stats->Add(functionMissing => 1);
            } else {
                $stats->Add(functionRead => 1);
                if (exists $funHash{$function}) {
                    # Here we already know the function.
                    $funID = $funHash{$function};
                    $stats->Add(functionReused => 1);
                } else {
                    # Here we must compute it.
                    $stats->Add(functionAnalyzed => 1);
                    my @roles = SeedUtils::roles_of_function($function);
                    $funID = [];
                    for my $role (@roles) {
                        my $roleID = RoleParse::Checksum($role);
                        $roles{$roleID} = $role;
                        push @$funID, $roleID;
                    }
                    $funHash{$function} = $funID;
                }
                for my $roleID (@$funID) {
                    $stats->Add(roleProcessed => 1);
                    Increment(\%roleCounts, $roleID, $i);
                    push @{$roleFeats{$roleID}}, $feature->{id};
                }
            }
        }
    }
    # Record the feature count.
    $feats[$i] = $featCount;
    # Position forward in the GTO list.
    $i++;
}
# Compute the display options.
my $showF = $opt->features;
my $showAll = $opt->verbose;
my @colTitles = ('Role name', @gtoFiles);
if ($showF) {
    push @colTitles, 'Features containing role';
}
my $titled;
my $delim = P3Utils::delim($opt);
# Loop through the role table, producing output.
my @roleList = sort { $roles{$a} cmp $roles{$b} } keys %roleCounts;
for my $role (@roleList) {
    my $array = $roleCounts{$role};
    push @$array, 0 while (scalar(@$array) < $i);
    my $count = $array->[0];
    my $j = 1;
    while ($j < $i && $array->[$j] == $count) {
        $j++;
    }
    my $printRole = $showAll;
    if ($j < $i) {
        $printRole = 1;
        $stats->Add(roleMismatch => 1);
    } else {
        $stats->Add(roleMatch => 1);
    }
    if ($printRole) {
        # Here we want to print this role. If there is a feature list, it goes in here.
        my @flist;
        if ($showF) {
            my $features = $roleFeats{$role} // [];
            push @flist, [sort @$features];
        }
        # Print the counts and the features.
        print_line([$roles{$role}, @$array, @flist], \@colTitles, \*STDOUT, \$titled);
    }
}
# Write the feature and DNA statistics. If we are in pure mode, they go to STDERR, not STDOUT. Only do this if there are multiple genomes.
if (scalar(@gtoFiles) > 1) {
    P3Utils::print_cols(['* Features', @feats], oh => \*STDERR);
    P3Utils::print_cols(['* DNA', @dna], oh => \*STDERR);
}
# Write the run statistics.
print STDERR "All done.\n" . $stats->Show();

## Print a line, showing titles if it is the first.
sub print_line {
    my ($list, $titles, $oh, $flagPointer) = @_;
    if (! $$flagPointer) {
        P3Utils::print_cols($titles, oh => $oh);
        $$flagPointer = 1;
    }
    P3Utils::print_cols($list, oh => $oh, opt => $opt);
}

## Increment an entry in an array inside a hash. Fill zeroes into the missing spaces.
sub Increment {
    my ($hash, $key, $i) = @_;
    # Get the array for the specified key.
    my $array;
    if (exists $hash->{$key}) {
        $array = $hash->{$key};
    } else {
        $array = [];
        $hash->{$key} = $array;
    }
    # Grow it until it is big enough to hold us.
    push @$array, 0 while (scalar(@$array) <= $i);
    # Increment the indexed item.
    $array->[$i]++;
}