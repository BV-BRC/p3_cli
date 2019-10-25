=head1 Convert Functions to Roles in a Tab-Delimited File

    p3-function-to-role [options] <features.with.functions.tbl >features.with.roles.tbl

This script takes a file of features with functional assignments (products) included and
replaces the functions with roles. Hypothetical roles are not considered real, so some features
may be deleted. Conversely, some functions have multiple roles, so other features may be
replicated.

If a strict subset of roles is desired, the C<--roles> option should be used.

=head2 Parameters

There are no positional parameters.

The standard input can be overriddn using the options in L<P3Utils/ih_options>.

The command-line options in L<P3Utils/col_options> can be used to select the input column. The
input column should contain functional assignments. This column will be replaced with role
descriptions in the output.

The additional command-line options are

=over 4

=item roles

A tab-delimited file of roles. Each record consists of (0) a role ID, (1) the role checksum, and
(2) the role description. Specify this file if you want a role-filtering scheme other than
official PATRIC roles.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use SeedUtils;
use RoleParse;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(),
    ['roles|R=s', 'name of role file']);

# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
if (! $opt->nohead) {
    # Form the full header set and write it out.
    $outHeaders->[$keyCol] = 'feature.role';
    P3Utils::print_cols($outHeaders);
}
# Now we need to get the role database. If opt->roles is specified, the role
# database is strict and cannot be expanded.
my $strict = ($opt->roles ? 1 : 0);
my %roleDB;
if ($strict) {
    open(my $rh, '<', $opt->roles) || die "Could not open role file: $!";
    while (! eof $rh) {
        my $line = <$rh>;
        if ($line =~ /^(\S+)\t(\S+)\t(.+)/) {
            $roleDB{$2} = $3;
        }
    }
}
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    # Loop through the couplets.
    for my $couplet (@$couplets) {
        my ($function, $line) = @$couplet;
        # Convert the function to a list of roles.
        my @roles = SeedUtils::roles_of_function($function);
        # Loop through the roles.
        for my $role (@roles) {
            my $checkSum = RoleParse::Checksum($role);
            if (! exists $roleDB{$checkSum} && ! $strict & ! SeedUtils::hypo($role)) {
                # We need to add this role.
                $roleDB{$checkSum} = $role;
            }
            if (exists $roleDB{$checkSum}) {
                # We can use this role.
                $line->[$keyCol] = $roleDB{$checkSum};
                print join("\t", @$line) . "\n";
            }
        }
    }
}
# All done.