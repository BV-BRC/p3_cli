=head1 Return All Features for Certain in BV-BRC

    p3-all-genome-features [options]

This script returns the IDs of all the features in the BV-BRC database associated with specific genomes. It supports standard 
feature-filtering parameters and the specification of additional columns if desired. The positional parameters specify a genome
field and a value to match against that field. The command will return all features for genomes that match the specified criteria.
Note that while this script supports views, the views are only applied to feature fields, not the genome field. (This may change
in the distant future.)

=head2 Parameters

The positional parameters are the name of a genome field and the value to match against that field. An initial genome query
will get the genome IDs for the genomes matching that criteria, and then a second query will retrieve all features for those genomes.

The command-line options are those given in L<P3Utils/data_options> plus the following.

=over 4

=item fields

List the names of the available feature fields.

=item keyNames

List the name of the available genome fields.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('genomeFieldName genomeFieldValue', P3Utils::data_options(),
        ['fields|f', 'show available feature fields'],
        ['keyNames|keynames', 'show available genome filtering fields']);
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
if ($opt->fields) {
    my $fieldList = P3Utils::list_object_fields($p3, 'feature');
    print join("\n", @$fieldList, "");
} elsif ($opt->keynames) {
    my $keyList = P3Utils::list_object_fields($p3, 'genome');
    print join("\n", @$keyList, "");
} else {
    # First, we need to get the genome IDs for the genomes matching the criteria. We do this with a direct
    # query. The key field and value are specified in the positional parameters.
    my ($keyName, $keyValue) = @ARGV;
    if (! $keyName || ! $keyValue) {
        die "You must specify a genome field and value to match against.\n";
    }
    my @q = ([eq => $keyName, $keyValue], [select => 'genome_id']);
    # If there is a hard limit, we limit the number of genomes returned, since the number of features
    # is always much greater than the number of genomes.
    if ($opt->limit) {
        push @q, [limit => $opt->limit];
    }
    # Get the genome IDs. If we get none, we print a header with no results rather than an error.
    my @results = $p3->query('genome', @q);
    my @genomeIDs = map { $_->{genome_id} } @results;
    # Compute the output columns. Since this is an all-type method, we are ID-oriented, and
    # require the feature ID to be present. The feature ID is also the default output column.
    my ($selectList, $newHeaders) = P3Utils::select_clause($p3, feature => $opt, 1);
    # Compute the filter.
    my $filterList = P3Utils::form_filter($p3, $opt);
    # Write the headers.
    P3Utils::print_cols($newHeaders);
    # Loop through the genome IDs and get the features for each one.    
    for my $genomeID (@genomeIDs) {
        # We need to add the genome ID to the filter.
        my $newFilter = [[eq => 'genome_id', $genomeID], @$filterList];
        # Now we can query for the features.
        my $features = P3Utils::get_data($p3, 'feature', $newFilter, $selectList);
        for my $feature (@$features) {
            P3Utils::print_cols($feature, opt => $opt);
        }
    }
}
