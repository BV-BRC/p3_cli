=head1 Extract DNA from a GTO

    p3-gto-dna.pl [options] gtoFile

This script reads one or more locations from the standard input and outputs the corresponding DNA from the input L<GenomeTypeObject> file.

=head2 Parameters

The positional parameter should be the name of the L<GenomeTypeObject> file in JSON format.

The standard input can be overridden using the options in L<P3Utils/ih_options>. The standard input should contain location
strings in the key column (specified using L<P3Utils/col_options>) and the region name in the column identified by the
C<--label> parameter.

Location strings are of the form I<contigID>C<_>I<start>C<+>I<len> for the forward strand and I<contigID>C<_>I<start>C<->I<len> for
the backward strand.

Additional command-line options are as follows.

=over 4

=item fasta

Output should be in FASTA format, with the region name as the ID.

=item label

Index (1-based) or name of the column containing the region names. The default is the first column (C<1>).

=back

=cut

use strict;
use P3Utils;
use Contigs;
use GenomeTypeObject;


# Get the command-line options.
my $opt = P3Utils::script_opts('gtoFile', P3Utils::col_options(), P3Utils::ih_options(),
        ['label=s', 'index (1-based) or name of the label column', { default => 1 }],
        ['fasta', 'output should be in FASTA format'],
        );
# Get the GTO file.
my ($gtoFile) = @ARGV;
if (! $gtoFile) {
    die "No GTO file specified.";
} elsif (! -s $gtoFile) {
    die "Invalid, missing, or empty GTO file $gtoFile.";
}
my $gto = GenomeTypeObject->create_from_file($gtoFile);
# Get the GTO's contigs.
my $contigs = Contigs->new($gto);
# Release the GTO memory. We only need the contigs.
undef $gto;
# Open the input file.
my $ih = P3Utils::ih($opt);
# Read the incoming headers.
my ($outHeaders, $keyCol) = P3Utils::process_headers($ih, $opt);
# Check the options.
my $fasta = $opt->fasta;
# Determine the label column.
my $labelCol = P3Utils::find_column($opt->label, $outHeaders);
# Form the full header set and write it out.
if (! $opt->nohead && ! $fasta) {
    push @$outHeaders, 'dna';
    P3Utils::print_cols($outHeaders);
}
# Loop through the input.
while (! eof $ih) {
    my $couplets = P3Utils::get_couplets($ih, $keyCol, $opt);
    for my $couplet (@$couplets) {
        my ($loc, $data) = @$couplet;
        # Get the DNA.
        my $dna = $contigs->dna($loc);
        # Write it out according to the format.
        if (! $fasta) {
            push @$data, $dna;
            P3Utils::print_cols($data);
        } else {
            my $label = $data->[$labelCol];
            print ">$label\n$dna\n";
        }
    }
}