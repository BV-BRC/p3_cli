=head1 Push ids to a Patric genome-group

    p3-put-genome-group groupname [options] < genome-ids

Push ids to a Patric genome-group. The standard input should be a tab-delimited file containing genome IDs.
The standard input can be specified using L<P3Utils/ih_options> and the input column using L<P3Utils/col_options>.
Specify C<--show-error> to get verbose error messages. The specified genome IDs will be replace whatever is in the
named group. If the group does not exist, it will be created.

=cut


use strict;
use Getopt::Long::Descriptive;
use P3WorkspaceClient;
use Data::Dumper;
use JSON::XS;
use P3Utils;

my $opt = P3Utils::script_opts('groupName', P3Utils::col_options(), P3Utils::ih_options());

my $group = shift;
if (! $group) {
    die "No group name specified.";
}
my $ws = P3WorkspaceClientExt->new();
if (! $ws->{token}) {
    die "You must login with p3-login.";
}

my $home = $ws->home_workspace;
my $group_path = "$home/Genome Groups/$group";

my $lines = 0;
my $ih = P3Utils::ih($opt);
my (undef, $keyCol) = P3Utils::process_headers($ih, $opt);
my $group_list = P3Utils::get_col($ih, $keyCol);
my $group_data = { id_list => { genome_id => $group_list } };
my $group_txt = encode_json($group_data);

my $res;

eval {
    $res = $ws->create({
        objects => [[$group_path, "genome_group", {}, $group_txt]],
        permission => "w",
        overwrite => 1,
    });
};
if (!$res)
{
    die "Error creating genome group: $@";
}


