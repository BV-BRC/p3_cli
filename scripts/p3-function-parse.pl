=head1 Parse Functional Assignments to Convert them to Roles and Subsystems

    p3-function-parse.pl [options]

This script's default behavior is to split functional assignments into roles.  Unlike L<p3-function-to-role.pl>, it does
not convert the roles to IDs, so it captures all roles, even the ones that are not in the common role table.  Optionally,
you can request a list of the subsystems containing the role.  This is appended as a list (delimiter-separated) in an
extra column when available.

If a function has multiple roles, multiple output rows will be produced.

=head2 Parameters

There are no positional parameters.

The standard input can be overridden using the options in L<P3Utils/ih_options>.  The standard input should contain the
functional assignments.

Additional command-line options are those given in L<P3Utils/col_options> (to specify the column containing the functional
assignments), L<P3Utils/delim_options> (to specify the delimiter for the subsystem column), and the following options.

=over 4

=subsystems

If specified, an additional column will be added containing the subsystems for each role.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use RoleParse;
use SeedUtils;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(), P3Utils::delim_options(),
        ['subsystems|subs|subsystem|sub|s', 'include subsystems in output']
        );
# Get the options.
my $subsystems = $opt->subsystems;
# Get access to PATRIC.
my $p3 = P3DataAPI->new();
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Form the full header set and write it out.
if (! $opt->nohead) {
    push @$outHeaders, 'role';
    if ($subsystems) {
        push @$outHeaders, 'subsystems';
    }
    P3Utils::print_cols($outHeaders);
}
# This hash maps role checksums to subsystems.  If no subsystems are desired, we leave it empty.
# We have to fill it from the ENTIRE subsystem table, because the table is not searchable by role.
my %roleSubs;
if ($subsystems) {
    my $results = P3Utils::get_data($p3, subsystem => [['ne', 'subsystem_id', '0']], ['subsystem_name', 'role_name']);
    for my $result (@$results) {
        my ($subsystem, $roles) = @$result;
        if ($roles) {
            for my $role (@$roles) {
                my $checksum = RoleParse::Checksum($role);
                push @{$roleSubs{$checksum}}, $subsystem;
            }
        }
    }
}
# Get the delimiter.
my $delim = P3Utils::delim($opt);
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    for my $couplet (@$couplets) {
        my ($function, $line) = @$couplet;
        # Split the function into roles.
        my @roles = SeedUtils::roles_of_function($function);
        for my $role (@roles) {
            my @row = @$line;
            push @row, $role;
            if ($subsystems) {
                my $subString = '';
                my $checksum = RoleParse::Checksum($role);
                my $subs = $roleSubs{$checksum};
                if ($subs) {
                    $subString = join($delim, @$subs);
                }
                push @row, $subString;
            }
            P3Utils::print_cols(\@row);
        }
    }
}