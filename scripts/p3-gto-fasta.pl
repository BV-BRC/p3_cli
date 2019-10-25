=head1 Convert Genome Typed Objects to FASTA

    p3-gto-fasta.pl [options] gtoFile

This script produces FASTA files from a L<GenomeTypeObject> instance. The GTO must be
provided as a file in JSON format.

=head2 Parameters

The positional parameter is the name of the GTO file. If none is specified, the GTO file is read from the standard input.

The command-line options are the following. All three are mutually exclusive.

=over 4

=item protein

If specified, the output will be a protein FASTA file.

=item feature

If specified, the output will be a feature DNA FASTA file.

=item contig

If specified, the output will be a contig DNA FASTA file. this is the default.

=back

=cut

use strict;
use P3Utils;
use GenomeTypeObject;
use SeedUtils;
use Contigs;

# Get the command-line options.
my $opt = P3Utils::script_opts('gtoFile',
        ['mode' => hidden => { one_of => [['protein', 'feature protein FASTA'],
                                          ['feature', 'feature DNA FASTA'],
                                          ['contig', 'contig DNA FASTA']],
                               default => 'contig' }],
        );
# Get the GTO file.
my ($gtoFile) = @ARGV;
if (! $gtoFile) {
    $gtoFile = \*STDIN;
} elsif (! -s $gtoFile) {
    die "GTO file $gtoFile not found or empty.";
}
# Read the GTO.
my $gto = GenomeTypeObject->create_from_file($gtoFile);
# Determine the output format.
my $mode = $opt->mode;
if ($mode eq 'contig') {
    # In contig mode, we want a list of [contig-id, sequence].
    my $contigs = $gto->{contigs};
    for my $contig (@$contigs) {
        fasta_print($contig->{id}, '', $contig->{dna});
    }
} elsif ($mode eq 'protein') {
    # Here we are getting all protein features for a genome.
    my $features = $gto->{features};
    for my $feature (@$features) {
        my $prot = $feature->{protein_translation};
        if ($prot) {
            fasta_print($feature->{id}, $feature->{function}, $prot);
        }
    }
} else {
    # Here we are getting all DNA features for a genome. First we need a contigs object.
    my @contigList = map { [$_->{id}, '', $_->{dna} ] } @{$gto->{contigs}};
    my $contigs = Contigs->new(\@contigList);
    my $features = $gto->{features};
    for my $feature (@$features) {
        my $loc = $feature->{location};
        my $dna = $contigs->dna(@$loc);
        fasta_print($feature->{id}, $feature->{function}, $dna);
    }
}

sub fasta_print {
    my ($id, $comment, $seq) = @_;
    my @chunks = ($seq =~ /(.{1,60})/g);
    print ">$id $comment\n";
    print join("\n", @chunks, "");
}

