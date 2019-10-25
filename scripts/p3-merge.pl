=head1 Merge Two Files-- Union, Intersection, or Difference

    p3-merge.pl [options] file1 file2 ... fileN

This script reads one or more files and outputs a new one containing whole lines from those files. The output file can be the union (all lines from all files),
intersection (all lines present in all files), or difference (all lines in the first but not the others). All files must have the same header line.
This script has a function similar to L<p3-file-filter.pl>, except that script uses a single key field instead of whole lines and is limited to only two files.

Duplicate lines will be removed. That is, a line that occurs in multiple files or occurs more than once in any file will only appear once in the output.

Any one file can be replaced by the standard input.

=head2 Parameters

The positional parameters are the names of the files. A minus sign (C<->) can be used to represent the standard input.

The standard input can be overridden using the options in L<P3Utils/ih_options>.

Additional command-line options are the following.

=over 4

=item nohead

If specified, the files are presumed to have no headers.

=item and

The output should only contain lines found in both files. This is mutually exclusive with C<or> and C<diff>.

=item or

The output should contain all lines from either file. This is the default.

=item diff

The output should contain lines from the first file not found in the second. This is mutually exclusive with C<and> and C<diff>.

=item input

If specified, the name of a tab-delimited file containing the names of the files to merge in its first column.

=back

=cut

use strict;
use P3Utils;
use Digest::MD5;

# Get the command-line options.
my $opt = P3Utils::script_opts('file1 file2 ... fileN', P3Utils::ih_options(),
        ['nohead', 'input files do not have headers'],
        ['mode' => hidden => { one_of => [['and|all', 'output lines in both files'],
                                          ['or|union', 'output lines in either file'],
                                          ['diff|difference|minus', 'output lines only in first']],
                               default => 'or' }],
        ['input=s', 'name of file containing input file names']
        );
# Get the input file names.
my @files = @ARGV;
if ($opt->input) {
    open(my $ih, '<', $opt->input) || die "Could not open file-name input: $!";
    my $fileList = P3Utils::get_col($ih, 0);
    push @files, @$fileList;
}
# Validate the file names.
if (! @files) {
    die "At least one file name must be specified.";
} elsif ((grep { $_ eq '-' } @files) > 1) {
    die "The standard input (-) can only be specified once.";
}
# Compute the mode and the header option.
my $mode = $opt->mode;
my $nohead = $opt->nohead;
# This will hold the header line.
my $header;
# Now we open the files. The handles will be put in this list.
my @fh;
for my $file (@files) {
    my $fh;
    if ($file eq '-') {
        $fh = P3Utils::ih($opt);
    } else {
        open($fh, "<$file") || die "Could not open $file: $!";
    }
    if (! $nohead) {
        my $headLine = <$fh>;
        # We do this next bit everywhere. In Windows, the standard input comes in with CRLF and everything else with just LF,
        # so we have to normalize the input lines.
        $headLine =~ s/[\r\n]+//;
        if (! defined $header) {
            $header = $headLine;
            print "$header\n";
        } elsif ($headLine ne $header) {
            die "File $file has an incompatible header.";
        }
    }
    push @fh, $fh;
}
# Now the header has been processed and output, and we have the file handles.
# This hash tracks records we've seen.
my %seen;
if ($mode eq 'or') {
    # Here we're taking the union of the files. We read all files in order
    # and print the records we've not seen.
    for my $fh (@fh) {
        print_unseen($fh, \%seen);
    }
} elsif ($mode eq 'diff') {
    # Here we're taking the difference. We read the second and subsequent files and print the unseen ones in the first.
    my $fh = shift @fh;
    for my $fh2 (@fh) {
        print_none($fh2, \%seen);
    }
    print_unseen($fh, \%seen);
} elsif ($mode eq 'and') {
    # Here we're taking the intersection. We look for records in all the files but the first one, then filter the first one.
    my $fh1 = shift @fh;
    # Get the second file.
    my $fh2 = shift @fh;
    # Save the records in the second file.
    print_none($fh2, \%seen);
    # Filter the seen hash by the records in the other files.
    for my $fh (@fh) {
        my %new;
        print_none($fh, \%new);
        %seen = map { $_ => 1 } grep { $seen{$_} } keys %new;
    }
    # Print the records in the first file found in all the others.
    print_new_seen($fh1, \%seen);
}


# Read a line and get its key.
sub read_line {
    my ($fh) = @_;
    my $line = <$fh>;
    $line =~ s/[\n\r]+$//;
    my $key = Digest::MD5::md5_base64($line);
    $line .= "\n";
    return ($key, $line);
}

# Read a file into the seen-hash.
sub print_none {
    my ($fh, $seenH) = @_;
    while (! eof $fh) {
        my ($key, $line) = read_line($fh);
        $seenH->{$key} = 1;
    }
}

# Read a file and print unseen lines.
sub print_unseen {
    my ($fh, $seenH) = @_;
    while (! eof $fh) {
        my ($key, $line) = read_line($fh);
        if (! $seenH->{$key}) {
            print $line;
            $seenH->{$key} = 1;
        }
    }
}

# Read a file and print seen lines. We need a second hash here to prevent duplicates
# in the new file.
sub print_new_seen {
    my ($fh, $seenH) = @_;
    my %seen;
    while (! eof $fh) {
        my ($key, $line) = read_line($fh);
        if ($seenH->{$key} && ! $seen{$key}) {
            print $line;
            $seen{$key} = 1;
        }
    }
}