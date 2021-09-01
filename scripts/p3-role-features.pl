=head1 Find Features for One or More Roles

    p3-role-features.pl [options]

This script takes as input a list of role descriptions and outputs the relevant feature records.  It can optionally accept
a file of genome IDs to which the features must belong.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.  It should contain a role description in
the key column identified by the L<P3Utils/col_options>.

Additional command-line options are those given in L<P3Utils/data_options> plus the following options.

=over 4

=item genomes

If specified, a tab-delimited file containing genome IDs in the first column.

=item verbose

Display progress messages on STDERR.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use RoleParse;
use SeedUtils;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::data_options(), P3Utils::col_options(), P3Utils::ih_options(),
        ['genomes|G=s', 'name of a file containing genome IDs in the first column'],
        ['verbose|v', 'display status messages on STDERR']
        );
my $debug = $opt->verbose;
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
# Compute the output columns.
my ($selectList, $newHeaders) = P3Utils::select_clause($p3, feature => $opt);
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
# Check for genome filtering.
my $genomeH;
if ($opt->genomes) {
    open(my $gh, '<', $opt->genomes) || die "Could not open genome file: $!";
    # Read past the headers.
    if (! $opt->nohead) {
        my $line = <$gh>;
    }
    # Read the genome IDs and put them in a hash.
    my $genomes = P3Utils::get_col($gh, 0);
    $genomeH = { map { $_ => 1 } @$genomes };
    print STDERR scalar(keys %$genomeH) . " genome IDs found in filter file.\n" if $debug;
}
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    print STDERR scalar(@$couplets) . " roles found in batch.\n" if $debug;
    # Because we have potentially one or more copies of a role per genome and we have a lot of genomes, we process the
    # roles one at a time.
    for my $couplet (@$couplets) {
        my ($role, $line) = @$couplet;
        # Get the role's checksum.  We use this to verify we have the correct role.
        my $checksum = RoleParse::Checksum($role);
        # Clean the role for the query.
        my $role2 = P3Utils::clean_value($role);
        print STDERR "Query for: $role.\n" if $debug;
        # Get all the occurrences of the role.  Note we explicitly ask for genome ID and product.
        my $results = P3Utils::get_data($p3, feature => [['eq', 'product', $role2], @$filterList], ['genome_id', 'product', @$selectList]);
        print STDERR scalar(@$results) . " found for $role.\n" if $debug;
        # Loop through the results.  We filter by genome (if requested) and by the role checksum, then write the output
        # if it passes.
        my ($count, $gCount, $rCount) = (0, 0, 0);
        for my $result (@$results) {
            my ($genomeID, $function, @fields) = @$result;
            # Filter by genomeID.
            if (! $genomeH || $genomeH->{$genomeID}) {
                $gCount++;
                # Process all the roles, looking for ours.
                my @foundR = SeedUtils::roles_of_function($function);
                for my $foundR (@foundR) {
                    $rCount++;
                    my $fcheck = RoleParse::Checksum($foundR);
                    if ($fcheck eq $checksum) {
                        P3Utils::print_cols([@$line, @fields]);
                        $count++;
                    }
                }
            }
        }
        print STDERR "$count features kept. $gCount found in genomes, $rCount roles checked.\n" if $debug;
    }
}
# All done.