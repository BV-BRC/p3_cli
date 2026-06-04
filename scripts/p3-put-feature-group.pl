=head1 Push ids to a Patric genome-group

    p3-put-feature-group groupname [options] < feature-ids

Push ids to a Patric feature-group. The standard input should be a tab-delimited file containing feature IDs.
The standard input can be specified using L<P3Utils/ih_options> and the input column using L<P3Utils/col_options>.
Specify C<--show-error> to get verbose error messages. The specified feature IDs will be replace whatever is in the
named group. If the group does not exist, it will be created.

If groupname starts with a /, the genome group will be created using that path. Otherwise it will be 
created in the folder Feature Groups in the user's default workspace.

=cut


use strict;
use Getopt::Long::Descriptive;
use P3WorkspaceClient;
use Data::Dumper;
use JSON::XS;
use P3Utils;

my $opt = P3Utils::script_opts('groupName',
        { _input_spec => P3Utils::input_spec(
            input   => 'tab-delimited feature IDs on stdin (or --input file)',
            output  => 'creates/updates a workspace feature group',
            example => 'p3-get-genome-features | p3-put-feature-group MyFeatures',
        )}, P3Utils::col_options(), P3Utils::ih_options());

my $group = shift;
if (! $group) {
    die "No group name specified.";
}
my $ws = P3WorkspaceClientExt->new();
if (! $ws->{token}) {
    die "You must login with p3-login.";
}

#
# If feature group is a full path, use that path instead of
# defaulting to the Feature Groups folder.
#
my $group_path;
if ($group =~ m,^/,)
{
    $group_path = $group;
}
else
{
    my $home = $ws->home_workspace;
    $group_path = "$home/Feature Groups/$group";
}


my $lines = 0;
my $ih = P3Utils::ih($opt);
my (undef, $keyCol) = P3Utils::process_headers($ih, $opt);
my $patric_ids = P3Utils::get_col($ih, $keyCol);
my $feature_list;

my $api = P3DataAPI->new;
while (@$patric_ids)
{
    my @chunk = splice(@$patric_ids, 0, 500);
    my $qry = join(" OR ", map { "\"$_\"" } @chunk);
    my $res = $api->solr_query("genome_feature", { q => "patric_id:($qry)", fl => "feature_id,patric_id" });

    my %tmp;
    $tmp{$_->{patric_id}} = $_->{feature_id} foreach @$res;

    push(@$feature_list, $tmp{$_}) foreach @chunk;
}

my $group_data = { id_list => { feature_id => $feature_list } };
my $group_txt = encode_json($group_data);

my $res;

eval {
    $res = $ws->create({
        objects => [[$group_path, "feature_group", {}, $group_txt]],
        permission => "w",
        overwrite => 1,
    });
};
if (!$res)
{
    die "Error creating feature group: $@";
}


