#
# Copyright (c) 2003-2015 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#
#
## This is a SAS component.
#



package Contigs;

    use strict;
    use warnings;
    use gjoseqlib;
    use SeedUtils;
    use BasicLocation;

=head1 Contig Management Object

This object contains the contigs for a specific genome. it provides methods for extracting
DNA and exporting the contigs in different forms.

Although it is designed with the idea of managing a genome in mind, in fact any set of DNA
sequences, even a single sequence, can be managed with this object. All that is required is
that each sequence be given an ID.

=over 4

=item genome

ID of the relevant genome.

=item triples

Reference to a hash mapping each contig ID to a 3-tuple consisting of (0) the contig ID, (1) the comment,
and (2) the DNA sequence.

=item lens

Reference to a hash mapping each contig ID to its length.

=item genetic_code

Genetic code for translating to proteins in these contigs.

=back

=head2 Special Methods

=head3 new

    my $contigObj = Contigs->new($contigFile, %options);
    my $contigObj = Contigs->new($ih, %options);
    my $contigObj = Contigs->new(\$fastaString, %options);
    my $contigObj = Contigs->new(undef, %options);
    my $contigObj = Contigs->new(\@triples, %options);
    my $contigObj = Contigs->new($gto, %options);

Create a contig object from a FASTA file or a list of triples.

=over 4

=item source

The source can be any one of the following.

=over 8

=item *

The name of a FASTA file containing the contig DNA.

=item *

An open file handle for the input FASTA file.

=item *

An undefined value (indicating the FASTA file is to be read from the standard input).

=item *

A string reference, indicating that the contents of a FASTA file are stored in the string.

=item *

A reference to an array of 3-tuples, each consisting of (0) a contig ID, (1) a comment, and
(2) the contig's DNA sequence.

=item *

A L<GenomeTypeObject> containing contig information.

=back

=item options

A hash of options, containing zero or more of the following keys.

=over 8

=item genomeID

ID of the relevant genome. If omitted, the default is C<unknown>.

=item genetic_code

Genetic code of the contigs. If omitted, the default is C<11>.

=back

=back

=cut

sub new {
    # Get the parameters.
    my ($class, $source, %options) = @_;
    # Get the options.
    my $genetic_code = $options{genetic_code} // 11;
    my $genomeID = $options{genomeID} // 'unknown';
    # Determine how to get the list of contig triples.
    my $triplesList;
    if (ref $source eq 'ARRAY') {
        # The parameter is already a list of triples.
        $triplesList = $source;
    } elsif (ref $source eq 'GenomeTypeObject') {
        # The parameter is a GenomeTypeObject.
        $triplesList = [];
        my $contigs = $source->{contigs};
        for my $contig (@$contigs) {
            push @$triplesList, [$contig->{id}, '', $contig->{dna}];
        }
    } else {
        # Here we have a FASTA source.
        $triplesList = gjoseqlib::read_fasta($source);
    }
    # Use the triplets we just read to build the object.
    my %triples = map { $_->[0] => $_ } @$triplesList;
    my %lens = map { $_->[0] => length($_->[2]) } @$triplesList;
    my $retVal = {
        genome => $genomeID,
        triples => \%triples,
        lens => \%lens,
        genetic_code => $genetic_code,
    };
    # Bless and return it.
    bless $retVal, $class;
    return $retVal;
}


=head2 Query Methods

=head3 ids

    my @ids = $contigs->ids();

Return a list of the contig IDs for the contigs in this object.

=cut

sub ids {
    # Get the parameters.
    my ($self) = @_;
    # Return the list of contig IDs.
    return sort keys %{$self->{triples}};
}

=head3 len

    my $len = $contigs->len($contigID);

Return the length of the specified contig.

=over 4

=item contigID

ID of the desired contig.

=item RETURN

Returns the length of the specified contig, or 0 if the contig does not exist
in this object.

=back

=cut

sub len {
    # Get the parameters.
    my ($self, $contigID) = @_;
    # Return the contig length.
    return ($self->{lens}{$contigID} // 0);
}


=head3 dna

    my $seq = $contigs->dna(@locs);

Return the DNA at the specified locations. The locations must be in this object's
genome.

=over 4

=item locs

A list of locations. These can be in the form of location strings, database
location 4-tuples, or L<BasicLocation> objects.

=item RETURN

Returns a DNA sequence corresponding to the specified locations.

=back

=cut

sub dna {
    # Get the parameters.
    my ($self, @locs) = @_;
    # We'll stash the DNA in here.
    my @retVal;
    # Loop through the locations, creating DNA. Note we convert each
    # one to a basic location object.
    for my $loc (map { BasicLocation->new($_) } @locs) {
        # Get the contig ID.
        my $contigID = $loc->Contig;
        # Does the contig exist?
        my $seqH = $self->{triples};
        if (! exists $seqH->{$contigID}) {
            # No. Return a bunch of hyphens.
            push @retVal, '-' x $loc->Length;
        } else {
            # Yes. Extract the dna.
            my $dna = substr($seqH->{$contigID}[2], $loc->Left - 1, $loc->Length);
            # If the direction is negative, reverse complement it.
            if ($loc->Dir eq '-') {
                SeedUtils::rev_comp(\$dna);
            }
            # Keep the result.
            push @retVal, $dna;
        }
    }
    # Return the DNA.
    return join("", @retVal);
}


=head3 kmer

    my $kmer = $contigs->kmer($contigID, $pos, $revFlag, \%options);

or

    my ($kmer, $kmerR) = $contigs->kmer($contigID, $pos, $revFlag, \%options);

Get the kmer at the specified position in the specified contig. The options indicate the
length and type of the kmer. An invalid kmer will come back as an empty string. A kmer
that falls off either end of the contig will come back undefined. Thus, when looping
through a contig you can use an undefined result to terminate the loop.

In scalar context, this method returns the desired kmer. In list context it returns
both the kmer and its reverse complement.

=over 4

=item contigID

ID of the contig whose kmer is desired.

=item pos

Position in the contig (1-based) of the kmer origin.

=item revFlag (optional)

TRUE if we want the reverse complement (minus strand) kmer, FALSE for the normal
(plus strand) kmer. The default is FALSE.

=item options (optional)

Reference to a hash of options describing the kmer. This includes the following keys.

=over 8

=item k

Length of the kmer. The default is C<30>.

=item style

Style of the kmer.

=over 12

=item normal

Normal kmer taken from the nucleotides at the current position.

=item 2of3

The kmer is constructed from the first two of every three nucleotides.
In this case, the output kmer will be 2/3 the length specified in the
C<k> option.

=back

=back

=item RETURN

In scalar context, returns the specified kmer. In list context, returns a 2-element
list consisting of the kmer and the kmer for the reverse complement of the same
region.

=back

=cut

sub kmer {
    # Get the parameters.
    my ($self, $contigID, $pos, $revflag, $options) = @_;
    # Adjust if the optional arguments are omitted.
    if ($revflag && ref $revflag eq 'HASH') {
        $options = $revflag;
        $revflag = 0;
    } elsif (! $options) {
        $options = {};
    }
    # The return values will go in here.
    my @retVal;
    # Compute the kmer type.
    my $k = $options->{k} // 30;
    my $style = $options->{style} // 'normal';
    # Create the kmer location.
    my $dir = ($revflag ? '-' : '+');
    my $kloc = BasicLocation->new($contigID, $pos, $dir, $k);
    # Verify that we're inside the contig.
    if ($kloc->Left > 0 && $kloc->Right <= $self->{lens}{$contigID}) {
        # Get the DNA.
        my @bases = uc $self->dna($kloc);
        # Only proceed if it's valid.
        if ($bases[0] =~ /[^AGCT]/) {
             # Invalid, so return empty strings.
             @retVal = ('', '');
        } else {
            # If the user wants an array, he wants the reverse complement.
            if (wantarray()) {
                push @bases, SeedUtils::rev_comp($bases[0]);
            }
            # Process according to the style.
            for my $base (@bases) {
                if ($style eq '2of3') {
                    push @retVal, join( '', $base =~ m/(..).?/g );
                } else {
                    push @retVal, $base;
                }
            }
        }
    }
    # Return the kmer in scalar mode, the list of kmers in list mode.
    if (wantarray()) {
        return @retVal;
    } else {
        return $retVal[0];
    }
}


=head3 xlate

    my $protSeq = $contigs->xlate(@locs, \%options);

Return the protein translation of a DNA sequence. The DNA can be passed in directly as a
scalar reference or computed from a list of locations.

=over 4

=item locs

List of locations. These can be location strings, database location 4-tuples,
or B<BasicLocation> objects.

=item options

Reference to a hash of options. The keys can be zero or more of the following.

=over 8

=item fix

If TRUE, the first triple is to get special treatment. A value of C<ATG>, C<TTG> or C<GTG>
in the first position is translated to C<M> regardless of the genetic code. If FALSE, the
first triple is translated normally.

=item code

If specified, reference to a hash that specifies the genetic code. If omitted, the genetic
code determined by the code number stored in this object is used.

=back

=item RETURN

Returns the protein sequence determined by the specified DNA sequence.

=back

=cut

sub xlate {
    # Get the parameters.
    my ($self, @locs) = @_;
    # This will be the return value.
    my $retVal = '';
    # Only proceed if we have locations.
    if (@locs) {
        # Check for options.
        my $options = {};
        if (ref $locs[$#locs] eq 'HASH') {
            $options = pop @locs;
        }
        # Compute the fix flag and the genetic code.
        my $fixFlag = $options->{fix} // 0;
        my $code = $options->{code} // SeedUtils::genetic_code($self->{genetic_code});
        # Extract the DNA.
        my $dna = $self->dna(@locs);
        # Perform the translation.
        $retVal = SeedUtils::translate($dna, $code, $fixFlag);
    }
    # Return the protein sequence.
    return $retVal;
}


=head3 tuples

    my @tuples = $contigs->tuples;

Return a list of 3-tuples representing these contigs. Each 3-tuple will consist of (0) the contig
ID, (1) the comment, and (2) the dna sequence.

=cut

sub tuples {
    # Get the parameters.
    my ($self) = @_;
    return map { $self->{triples}{$_} } sort keys %{$self->{triples}};
}

=head3 contig_dna

    my $dna = $contigs->contig_dna($contigID);

Return the entire DNA sequence of a single contig.

=over 4

=item contigID

ID of the desired contig.

=item RETURN

Returns the DNA sequence of the identified contig.

=back

=cut

sub contig_dna {
    my ($self, $contigID) = @_;
    return $self->{triples}{$contigID}[2];
}

=head3 fasta_out

    $contigs->fasta_out($oh);

Write the contigs as a FASTA file to an open output handle.

=over 4

=item oh

Open output handle to which the FASTA data should be written.

=back

=cut

sub fasta_out {
    my ($self, $oh) = @_;
    # Loop through the contig triples, printing them.
    my $triples = $self->{triples};
    for my $contigID (sort keys %$triples) {
        my $tuple = $triples->{$contigID};
        print $oh ">$tuple->[0] $tuple->[1]\n$tuple->[2]\n";
    }
}

=head3 present

    my $foundFlag = $contigs->present($contigID);

Return TRUE if the specified contig is present, else FALSE.

=over 4

=item contigID

The ID of the contig to check.

=item RETURN

Returns TRUE if the contig is in the object, else FALSE.

=back

=cut

sub present {
    my ($self, $contigID) = @_;
    my $retVal = 0;
    if ($self->{triples}{$contigID}) {
        $retVal = 1;
    }
    return $retVal;
}


=head2 Public Manipulation Methods

    $contigs->AddContig($id, $comment, $dna);

Add the specified contig to this object.

=over 4

=item id

ID of the contig to add.

=item comment

An optional comment. If undefined, an empty string is used.

=item dna

The DNA sequence for the contig.

=back

=cut

sub AddContig {
    my ($self, $id, $comment, $dna) = @_;
    $comment //= '';
    my $triplesH = $self->{triples};
    $triplesH->{$id} = [$id, $comment, $dna];
    $self->{lens}{$id} = length $dna;
}

1;
