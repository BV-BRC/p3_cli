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


package Category::EC;

    use strict;
    use warnings;
    use base qw(Category);

=head1 Category Object for EC Numbers

This is a subclass of L<Category> that is used to categorize features by EC Number.

=head2 Virtual Methods

=head3 name_to_id

    my $catID = $catHelper->name_to_id($catName);

Return the ID for a category given its name string. The ID is the actual EC number.

=over 4

=item catName

The displayable name for the category. This is also its input value in the category file.

=item RETURN

Returns the internal ID for the category.

=back

=cut

sub name_to_id {
    my ($self, $catName) = @_;
    my$retVal  = $catName;
    if ($self->{allMode}) {
        $self->{catH}{$retVal} = "EC $retVal";
    }
    return $retVal;
}


=head3 field_name

    my $field_name = $catHelper->field_name();

Return the name of the feature field used to extract the category name.

=cut

sub field_name {
    return 'ec';
}

=head3 all_cats

    my @cats = $catHelper->all_cats($dbString);

Return a list of all the categories in which a feature belongs. The database may return a list of EC numbers for a single feature.

=over 4

=item dbString

The value for the feature found in the field named by the L</field_name> method.

=item RETURN

Returns a list of category IDs.

=back

=cut

sub all_cats {
    my ($self, $dbString) = @_;
    my @retVal;
    if ($dbString) {
        my @names;
        if (ref $dbString eq 'ARRAY') {
            @names = @$dbString;
        } else {
            @names = ($dbString);
        }
        @retVal = map { $self->name_to_id($_) } @names;
    }
    return @retVal;
}


1;