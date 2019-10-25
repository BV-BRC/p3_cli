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


package TabFile;

    use strict;
    use warnings;
    use P3Utils;

=head1 Simple Sequential File with FastA Compatability

This is a simple sequential file processor.  It takes as input an open file handle and a pair of column indices (a
sequence column and an ID column). It then exposes methods L</next>, L<at_end>, L</left>, and L</id>.  This allows a
tab-delimited sequential file to be dropped in place of a FASTA file.

The object contains the following fields.

=over 4

=item ih

The input file handle.

=item id

The ID from the current record, or C<undef> if we are at end-of-file.

=item seq

The sequence from the current record.

=item idCol

The column index of the ID column.

=item seqCol

The column index of the sequence column.

=back

=head2 Special Methods

=head3 new

    my $hndl = TabFile->new($ih, $idCol, $seqCol);

Create a new tab-file handle.

=over 4

=item ih

An open input file handle.

=item idCol

The index (0-based) of the ID column.

=item seqCol

The index (0-based) of the sequence column.

=back

=cut

sub new {
    my ($class, $ih, $idCol, $seqCol) = @_;
    # Create the object.
    my $retVal = {
        idCol => $idCol,
        seqCol => $seqCol,
        ih => $ih,
        id => '',
        seq => ''
    };
    # Bless and return it.
    bless $retVal, $class;
    return $retVal;
}

=head2 Query Methods

=head2 Public Manipulation Methods

=head3 next

    my $found = $hndl->next;

Move forward to the next record, returning TRUE if one was found.

=cut

sub next {
    my ($self) = @_;
    # This will be set to TRUE if everything works.
    my $retVal;
    # Get the file handle.
    my $ih = $self->{ih};
    # Read a record.
    my $line = <$ih>;
    if (! defined $line) {
        $self->{id} = undef;
        $self->{seq} = undef;
    } else {
        my @fields = P3Utils::get_fields($line);
        $self->{id} = $fields[$self->{idCol}];
        $self->{seq} = $fields[$self->{seqCol}];
        $retVal = 1;
    }
    # Return the success indication.
    return $retVal;
}

=head3 at_end

    my $eofFlag = $hndl->at_end();

Return TRUE if the current sequence is the last one in the file, else FALSE.

=cut

sub at_end {
    my ($self) = @_;
    return (eof $self->{ih});
}

=head2 Data Access Methods

=head3 id

    my $id = $hndl->id;

Return the current sequence ID.

=cut

sub id {
    my ($self) = @_;
    return $self->{id};
}

=head3 left

    my $dna = $hndl->left;

Return the left data string.

=cut

sub left {
    my ($self) = @_;
    return $self->{seq};
}

=head3 lqual

    my $dna = $hndl->lqual;

Return the left quality string.

=cut

sub lqual {
    my ($self) = @_;
    return '';
}



1;