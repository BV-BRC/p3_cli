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


package Category::Family;

    use strict;
    use warnings;
    use base qw(Category);

=head1 Category Object for Global Protein Families

This is a subclass of L<Category> that is used to categorize features by global PATRIC protein family.

=head2 Virtual Methods

=head3 field_name

    my $field_name = $catHelper->field_name();

Return the name of the feature field used to extract the category name.

=cut

sub field_name {
    return 'pgfam_id';
}


1;