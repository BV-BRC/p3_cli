=head1 Retrieve a feature group from a patric workspace

    p3-get-feature-group [options] group-name

Retrieve a feature group from a patric workspace. Use the C<--title> option to specify the output column header.
A value of C<none> will omit the header; the default is the group name followed by C<genome_id>.

=cut

use strict;
use Getopt::Long::Descriptive;
use P3WorkspaceClient;
use Data::Dumper;
use JSON::XS;
use P3Utils;

my $opt = P3Utils::script_opts('groupName', ['title|t=s', 'output column title']);

my $group = shift;
if (! $group) {
    die "No group name specified.";
}

my $title = $opt->title;
if (! $title) {
    $title = "$group.patric_id";
} elsif ($title eq 'none') {
    $title = "";
}
if ($title) {
    print "$title\n";
}
my $ws = P3WorkspaceClientExt->new();
if (! $ws->{token}) {
    die "You must login with p3-login.";
}

my $home = $ws->home_workspace;
my $group_path = "$home/Feature Groups/$group";

my $raw_group = $ws->get({ objects => [$group_path] });
my($meta, $data_txt) = @{$raw_group->[0]};
my $data = decode_json($data_txt);
my $list = $data->{id_list}->{feature_id};
my @members;
if ($list) {
    @members = @$list;
}

my $api = P3DataAPI->new;
while (@members)
{
    my @chunk = splice(@members, 0, 500);
    my $qry = join(" OR ", map { "\"$_\"" } @chunk);
    my $res = $api->solr_query("genome_feature", { q => "feature_id:($qry)", fl => "feature_id,patric_id" });

    my %tmp;
    $tmp{$_->{feature_id}} = $_->{patric_id} foreach @$res;
    print "$tmp{$_}\n" foreach @chunk;
}
