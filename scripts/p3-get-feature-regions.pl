=head1 Display DNA Regions for Features

    p3-get-feature-regions.pl [options]

This script takes as input a list of feature IDs and displays the DNA region surrounding each feature.  The portion of each region
occupied by the feature itself and the feature's neighbors will be shown in upper case, the rest in lower case.  The output will be
in FASTA format.

=head2 Parameters

There are no positional parameters

The standard input can be overridden using the options in L<P3Utils/ih_options>.

The input column can be specified using L<P3Utils/col_options>.  Additional command-line options are as follows.

=over 4

=item distance

The distance in base pairs to show around the specified feature.  The default is C<100>.

=item comment

If specified, a field to put in the FASTA comments.  If multiple fields are desired, the option should be specified multiple
times.

=item consolidated

If a requested feature's region includes another requested feature, the region will be expanded to include it.  If this is
done, a description of the features in each sequence and their locations will be appended to the comment field.  Note that
there will still be one output sequence per incoming feature; however, some may be duplicated.

=back

=cut

use strict;
use P3DataAPI;
use P3Utils;
use P3Sequences;

# Get the command-line options.
my $opt = P3Utils::script_opts('', P3Utils::col_options(), P3Utils::ih_options(),
        ['distance|dist|margin|d=i', 'distance to show around specified feature', { default => 100 }],
        ['comment|c=s@', 'field to put in FASTA comment (implies FASTA)'],
        ['consolidated|K', 'extend regions to include other requested features that overlap']
        );
# Extract the key options.
my $distance = $opt->distance;
my $consolidated = $opt->consolidated;
# Get access to BV-BRC.
my $p3 = P3DataAPI->new();
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Check for comment requirements.
my $commentFields = $opt->comment;
my $commentSpec = P3Utils::find_headers($outHeaders, inputFile => @$commentFields);
# Create the sequence manager.
my $p3seqs = P3Sequences->new($p3);
# Loop through the input.  We will create a hash of feature IDs, mapping each one to its input line.
my %fidLines;
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    # Loop through the features, storing the tuples.
    for my $couplet (@$couplets) {
        my ($fid, $tuple) = @$couplet;
        $fidLines{$fid} = $tuple;
    }
}
# Now we have all our features.  We are going to get a hash of feature -> sequence and another of feature -> mapping.
# If we are not consolidated, the mapping will be empty.
my @fids = sort keys %fidLines;
my %options = (distance => $distance);
my ($fidSeqs, %fidMap);
if ($consolidated) {
    $fidSeqs = $p3seqs->FeatureConsolidatedRegions(\@fids, \%fidMap, %options);
} else {
    $fidSeqs = $p3seqs->FeatureRegions(\@fids, %options);
}
# Now we produce the FASTA output.
for my $fid (@fids) {
    # We need to form the comment.  We start with the command-line stuff.
    my $comment = join(' ', P3Utils::get_cols($fidLines{$fid}, $commentSpec));
    # Add the mapping, if any.
    my $map = $fidMap{$fid};
    if ($map) {
        $comment .= "\t" . join(', ', map { "$_->[0]=$_->[1]..$_->[2]" } @$map);
    }
    # Write the FASTA record.
    print ">$fid $comment\n$fidSeqs->{$fid}\n";
}