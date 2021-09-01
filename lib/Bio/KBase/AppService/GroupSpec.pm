#
# Copyright (c) 2003-2019 University of Chicago and Fellowship
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


package Bio::KBase::AppService::GroupSpec;

    use strict;
    use warnings;
    use P3DataAPI;
    use P3Utils;

=head1 Service Module for Group Lists

This module provides methods for validating lists of genome or feature groups.  Such groups exist as workspace
objects, so we need to put in a prefix on relative names.  Unlike files, there is no need to worry about loca
files.

=head2 Special Methods

=sub validate_groups

    my $okFlag = Bio::KBase::AppService::GroupSpec::validate_groups($ids, $prefix);

=over 4

=item ids

Reference to a list of group names or a comma-delimited string of group names.

=item prefix

Workspace path prefix to use for relative path names.

=item RETURN

A reference to the list of normalized group names.  The result is always a list, regardless of whether the incoming value
is a list or scalar, and it is normalized with the path prefix.

=back

=cut

sub validate_groups {
    my ($ids, $prefix) = @_;
    my $retVal;
    # Insure if we have input.
    if (! defined $ids) {
        die "No group names specified.";
    } elsif (! ref $ids) {
        # Here we have a comma-delimited name list.
        $ids = [ split /,/, $ids ];
    }
    # Insure the prefix has a terminating slash.
    if ($prefix && substr($prefix,-1,1) ne '/') {
        $prefix .= '/';
    }
    # Loop through the IDs, normalizing.
    my @retVal;
    for my $id (@$ids) {
        if (substr($id,0,1) ne '/') {
            if (! $prefix) {
                die "Relative group name specified, but no workspace-path-prefix provided.";
            }
            $id = $prefix . $id;
        }
        push @retVal, $id;
    }
    return \@retVal;
}


1;


