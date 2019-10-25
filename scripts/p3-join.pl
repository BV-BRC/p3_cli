=head1 Join Two Files on a Key Field

    p3-join.pl [options] file1 file2

Join two files together on a single key field. Each record in the output will contain the fields from the first
file followed by the fields from the second file except for its key field. For each record in the first file,
every matching record in the second file will be appended. If no second-file records match, the first-file record
will be skipped.

=head2 Parameters

The positional parameters are the names of the two files. If only one file is specified, the second file
will be taken from the standard input.  If a hyphen C<-> is used for the first parameter, the first file
will be taken from the standard input.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are the following.

=over 4

=item key1

The index (1-based) or name of the key column in the first file. The default C<0>, indicating the last column.

=item key2

The index (1-based) or name of the key column in the second file. The default is the value of C<--key1>.

=item nohead

If specified, the files are assumed to not have headers.

=item batchSize

The number of records to read in each group from the first file.  The default is C<10>.

=item only

If specified, a comma-delimited list of column names or indices (1-based) from the second file.  Only these fields will be included in
the output.

=item nonblank

If specified, lines with blank keys will be removed from the files.

=item left

If specified, all lines from the first file will be included in the output, even if there is not a matching copy of the second file.

=back

=cut

use strict;
use P3Utils;

# Get the command-line options.
my $opt = P3Utils::script_opts('file1 file2', P3Utils::ih_options(),
        ['nohead', 'input files have no headers'],
        ['batchSize=i', 'hidden', { default => 10 }],
        ['key1|k1|1=s', 'key field for file 1', { default => 0 }],
        ['key2|k2|2=s', 'key field for file 2'],
        ['only=s', 'columns for file 2'],
        ['nonblank', 'ignore lines with missing keys'],
        ['left', 'include all lines from first file']
        );
# Get the key field parameters.
my $key1 = $opt->key1;
my $key2 = $opt->key2 // $key1;
# Get the nonblank option.
my $blankOK = ! $opt->nonblank;
# Get the two file names.
my ($file1, $file2) = @ARGV;
if (! $file1) {
    die "At least one file name is required.";
} elsif (! -f $file1) {
    die "File $file1 not found or invalid.";
}
# Get the second file. We will read this into memory.
my %file2;
my $ih;
if ($file2) {
    open($ih, '<', $file2) || die "Could not open second file $file2: $!";
} else {
    $ih = P3Utils::ih($opt);
}
# Compute the key column for file 2.
my ($headers2) = P3Utils::process_headers($ih, $opt, 1);
my $col2 = P3Utils::find_column($key2, $headers2);
my $file2Cols = [];
if (! $opt->only) {
    for (my $i = 0; $i < @$headers2; $i++) {
        if ($i != $col2) {
            push @$file2Cols, $i;
        }
    }
} else {
    my @cols2 = split /,/, $opt->only;
    (undef, $file2Cols) = P3Utils::find_headers($headers2, file2 => @cols2);
}
# Form the second file's kept headers.
my @head2;
for my $i (@$file2Cols) {
    push @head2, $headers2->[$i];
}
my (@extra, $left);
if ($opt->left) {
    @extra = map { '' } @head2;
    $left = 1;
}
# Loop through the file, filling the hash.
while (! eof $ih) {
    my $line = <$ih>;
    my @fields = P3Utils::get_fields($line);
    my $key = $fields[$col2];
    if ($key || $blankOK) {
        my @cols2;
        for my $i (@$file2Cols) {
            push @cols2, $fields[$i];
        }
        push @{$file2{$key}}, \@cols2;
    }
}
close $ih; undef $ih;
# Now we open up the first file and get the headers.
if ($file1 eq '-') {
    $ih = \*STDIN;
} else {
    open($ih, '<', $file1) || die "Could not open $file1: $!";
}
my ($headers1) = P3Utils::process_headers($ih, $opt, 1);
my $col1 = P3Utils::find_column($key1, $headers1);
# Output the headers.
if (! $opt->nohead) {
    my @outHeaders = (@$headers1, @head2);
    P3Utils::print_cols(\@outHeaders);
}
# Loop through the first file, joining with the second file.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $col1, $opt);
    for my $couplet (@$couplets) {
        my ($key, $line) = @$couplet;
        # We now need the list of file2 records matching this key.
        my $joinList = $file2{$key} // [];
        for my $joinLine (@$joinList) {
            P3Utils::print_cols([@$line, @$joinLine]);
        }
        # Check to see if we want to print this line even if there are no corresponding file2 lines.
        if ($left && ! @$joinList) {
            P3Utils::print_cols([@$line, @extra]);
        }
    }
}
