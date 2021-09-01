=head1 Find Roles That Occur Close Together

    p3-generate-close-roles.pl [options] <roles.tbl >pairs.tbl

This script is part of a pipeline to compute functionally-coupled roles. It takes a file of locations and roles, then
outputs a file of pairs of roles with the number of times features containing those two roles occur close together on
the chromosome. Such roles typically have related functions in a genome.

The input file must contain the following four fields.

=over 4

=item 1

genome ID

=item 2

contig (sequence) ID

=item 3

location in the sequence

=item 4

functional role

=back

The default script assumes the four columns are in that order. This can all be overridden with command-line options.

The input file must be sorted by genome ID and then by sequence ID within genome ID. Otherwise, the results will be
incorrect. Use L<p3-sort.pl> to sort the file.

The location is a BV-BRC location string, either of the form I<start>C<..>I<end> or C<complement(>I<left>C<..>I<right>C<)>.
Given a set of genome IDs in the file C<genomes.tbl>, you can generate the proper file using the following pipe.

    p3-get-genome-features --attr sequence_id --attr location --attr product <genomes.tbl | p3-function-to-role

(If BV-BRC does not yet have roles defined, you will need to use an additional command-line option on L<p3-function-to-role.pl>.)

=head2 Parameters

There are no positional parameters.

The standard input can be overriddn using the options in L<P3Utils/ih_options>.

Additional command-line options are

=over 4

=item genome

The index (1-based) or name of the column containing the genome ID. The default is C<1>.

=item sequence

The index (1-based) or name of the column containing the sequence ID. The default is C<2>.

=item location

The index (1-based) or name of the column containing the location string. The default is C<3>.

=item role

The index (1-based) or name of the column containing the role description. The default is C<4>.

=item maxGap

The maximum space between two features considered close. The default is C<2000>.

=item minOcc

The minimum number of occurrences for a pair to be considered significant. The default is C<4>.

=back

=head3 Example

This command is shown in the tutorial p3_common_tasks.html

p3-get-genome-features --eq feature_type,CDS --attr sequence_id --attr location --attr product &lt;genomes.tbl | p3-function-to-role | p3-generate-close-roles
    role1   role2   count
    Transposase, IS3/IS911 family   Mobile element protein  33
    Mobile element protein  Mobile element protein  29
    Lead, cadmium, zinc and mercury transporting ATPase (EC 3.6.3.3) (EC 3.6.3.5)   Copper-translocating P-type ATPase (EC 3.6.3.4) 25
    Potassium efflux system KefA protein    Small-conductance mechanosensitive channel  13
    ...

=cut

use strict;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::ih_options(),
        ['genome|g=s', 'index (1-based) or name of the genome ID column', { default => 1 }],
        ['sequence|seq|s=s', 'index (1-based) or name of the sequence ID column', { default => 2 }],
        ['location|loc|l=s', 'index (1-based) or name of the location column', { default => 3 }],
        ['role|R=s', 'index (1-based) or name of the role column', { default => 4 }],
        ['maxGap|max-gap|gap=i', 'maximum permissible gap between close features', { default => 2000 }],
        ['minOcc|min-occ|occ=i', 'minimum number of occurrences for a significant pair', { default => 4 }],
        );
# Get the options.
my $maxGap = $opt->maxgap;
my $minOcc = $opt->minocc;
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers and compute the critical column indices.
my ($headers, $cols) = P3Utils::find_headers($ih, roles => $opt->genome, $opt->sequence, $opt->location, $opt->role);
# This hash maps a role description to a role index. The list maps the other direction.
my %roleMap;
my @roleList;
# This hash maps a role pair (represented as a comma-separate list of role indices) to a count.
my %pairCounts;
# This is a list of [roleIndex, start, end] tuples for the current contig.
my @roleTuples;
# This is the current genome ID.
my $genomeID = '';
# This is the current sequence ID.
my $sequenceID = '';
# Loop through the input.
while (! eof $ih) {
    my ($genome, $sequence, $loc, $role) = P3Utils::get_cols($ih, $cols);
    if ($genomeID ne $genome || $sequenceID ne $sequence) {
        if ($genomeID) {
            # We have finished the previous contig, so process it.
            process_batch(\@roleTuples, \%pairCounts, $maxGap);
        }
        # Restart for a new contig.
        ($genomeID, $sequenceID) = ($genome, $sequence);
        @roleTuples = ();
    }
    # Compute the role index.
    my $roleID = $roleMap{$role};
    if (! defined $roleID) {
        $roleID = scalar @roleList;
        $roleMap{$role} = scalar @roleList;
        push @roleList, $role;
    }
    # Parse the location and store the tuple.
    if ($loc =~ /(\d+)[><]?\.\.[><]?(\d+)/) {
        push @roleTuples, [$roleID, $1, $2];
    } else {
        die "Invalid location string \"$loc\".";
    }
}
# Process the residual batch.
process_batch(\@roleTuples, \%pairCounts, $maxGap);
# Sort to compute the significant pairs.
my @pairs = sort { $pairCounts{$b} <=> $pairCounts{$a} } keys %pairCounts;
# Now we can output the results.
P3Utils::print_cols(['role1', 'role2', 'count']);
for my $pair (@pairs) {
    my ($role1, $role2) = map { $roleList[$_] } split /,/, $pair;
    my $count = $pairCounts{$pair};
    if ($count >= $minOcc) {
        P3Utils::print_cols([$role1, $role2, $count]);
    }
}

# Process a batch of role tuples to produce pair counts.
sub process_batch {
    my ($roleTuples, $pairCounts, $maxGap) = @_;
    # Sort the role tuples by start location.
    my @sorted = sort { $a->[1] <=> $b->[1] } @$roleTuples;
    # Loop through the sorted list.
    while (@sorted) {
        my $first = shift @sorted;
        my ($role1, undef, $end) = @$first;
        # We now know for a fact that every feature left in sorted starts to the right of the $role1 feature.
        # We pair with everything that starts before the gap distance after our end.
        $end += $maxGap;
        for my $other (@sorted) { last if $other->[1] > $end;
            my $pair = join(',', sort ($role1, $other->[0]));
            $pairCounts{$pair}++;
        }
    }
}