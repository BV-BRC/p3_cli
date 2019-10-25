=head1 Create Subsystem Role File

    p3-subsys-roles.pl [options]

Create a subsystem role file for L<p3-function-to-role.pl>.  The file will be created on the standard output.  It will be headerless and
tab-delimited, with three columns: (0) the role ID, (1)  the role checksum, and (2) the role name.

=head2 Parameters

The are no positional parameters.

The following command-line options are supported.

=over 4

=item verbose

If specified, progress messages will be written to STDERR.

=item roleFile

If specified, the name of a tab-delimited file with role names in the last column.  Rather than the output being for all roles
in subsystems, it will be for all roles in the specified file.  The file should have headers.

=item col

If specified, the index (1-based) of the column containing the role name.  The default is C<0>, indicating the last column.

=item nohead

If specified, the role file is presumed to not have headers.  Note that the output file never has headers, for compatibility
with older software.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use RoleParse;


# Get the command-line options.
my $opt = P3Utils::script_opts('',
        ['verbose|debug|v', 'display progress messages on STDERR'],
        ['roleFile|roles|R=s', 'name of a file containing role names'],
        ['col|c=s', 'index (1-based) of the input role column', { default => 0 }],
        ['nohead', 'if specified, the role file is presumed to not have headers']
        );
my $debug = $opt->verbose;
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# This hash will hold the role checksums.  Each checksum is mapped to an ID, checksum, and name.
my %hash;
# We need to get a list of all the roles.
my $results;
if (! $opt->rolefile) {
    print STDERR "Retrieving subsystem roles.\n" if $debug;
    $results = P3Utils::get_data($p3, subsystem => [['ne', 'subsystem_id', 'x']], ['role_name']);
} else {
    print STDERR "Retrieving roles from input file.\n" if $debug;
    open(my $ih, '<', $opt->rolefile) || die "Could not open role input file: $!";
    my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
    # Create a result list from the specified column.  For subsystems, we have a list of role lists.
    # We simulate that as a singleton list of the list of all the roles, effectively acting as if the
    # role list is one giant subsystem.
    my $column = P3Utils::get_col($ih, $keyCol);
    $results = [[$column]];
}
# Get all the subsystem roles from the subsystems.
my $idNum = 0;
for my $result (@$results) {
    my ($roles) = @$result;
    for my $role (@$roles) {
        my $checksum = RoleParse::Checksum($role);
        if (! $hash{$checksum}) {
            $idNum++;
            $hash{$checksum} = [$idNum, $checksum, $role];
        }
    }
}
print STDERR "Writing output.\n" if $debug;
for my $checksum (sort keys %hash) {
    my $roleData = $hash{$checksum};
    P3Utils::print_cols($roleData);
}
