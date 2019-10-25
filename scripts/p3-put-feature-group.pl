=head1 Push ids to a Patric genome-group

    p3-put-feature-group groupname [options] < feature-ids

Push ids to a Patric feature-group. The standard input should be a tab-delimited file containing feature IDs.
The standard input can be specified using L<P3Utils/ih_options> and the input column using L<P3Utils/col_options>.
Specify C<--show-error> to get verbose error messages. The specified feature IDs will be replace whatever is in the
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
my $group_path = "$home/Feature Groups/$group";

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


