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


package Category::Role;

    use strict;
    use warnings;
    use base qw(Category);
    use RoleParse;
    use SeedUtils;

=head1 Role Category Object

This is a subclass of L<Category> for the situation where a feature's categories are determined by its roles.

=head3 name_to_id

    my $catID = $catHelper->name_to_id($catName);

Return the ID for a category given its name string. The ID is its checksum.

=over 4

=item catName

The displayable name for the category. This is also its input value in the category file.

=item RETURN

Returns the internal ID for the category.

=back

=cut

sub name_to_id {
    my ($self, $catName) = @_;
    my $retVal = RoleParse::Checksum($catName);
    if ($self->{allMode}) {
        $self->{catH}{$retVal} = $catName;
    }
    return $retVal;
}


=head3 all_cats

    my @cats = $catHelper->all_cats($dbString);

Return a list of all the categories in which a feature belongs. The functional assignment may contain multiple roles.

=over 4

=item dbString

The value for the feature found in the field named by the L</field_name> method.

=item RETURN

Returns a list of category IDs.

=back

=cut

sub all_cats {
    my ($self, $dbString) = @_;
    my @roles = SeedUtils::roles_of_function($dbString);
    my @retVal;
    for my $role (@roles) {
        push @retVal, $self->name_to_id($role);
    }
    return @retVal;
}

=head3 field_name

    my $field_name = $catHelper->field_name();

Return the name of the feature field used to extract the category name.

=cut

sub field_name {
    return 'product';
}


1;