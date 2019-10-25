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


package Category;

    use strict;
    use warnings;
    use BasicLocation;
    use P3Utils;

=head1 Protein Category

This is a base class for scripts that categorize proteins. The functions performed are

=over 4

=item 1

Reading all the categories from a file.

=item 2

Categorizing all the proteins in a genome.

=item 3

Converting a category value to a printable name.

=back

Each category has an ID and a name. Often these are the same. Most of the time the category IDs are passed around.

The following fields are in this object.

=over 4

=item catH

Reference to a hash that maps each category ID to its display name.

=item p3

The L<P3DataAPI> object for accessing the PATRIC database.

=item allMode

If specified, all categories are accepted, rather than just the ones in a list.

=back

=head2 Special Methods

=head3 new

    my $catHelper = Category->new($p3, $type, $catFile, $nohead);

Create a new category helper for the specified category using the specified source file.

=over 4

=item p3

The L<P3DataAPI> object for accessing the PATRIC database.

=item type

The type of category.

=item catFile

The input file containing the desired category names in the first column, or C<*>, indicating that all categories are to be counted.

=item nohead

TRUE if the input file lacks headers, else FALSE.

=back

=cut

use constant CLASSES => { role => 'Category::Role', family => 'Category::Family', ecnum => 'Category::EC' };

sub new {
    my ($class, $p3, $type, $catFile, $nohead) = @_;
    # Compute the blessing class.
    $class = CLASSES->{$type};
    if (! $class) {
        die "Invalid Category type $type.";
    }
    # Create the object.
    my %catH;
    my $retVal = { p3 => $p3, catH => \%catH };
    bless $retVal, $class;
    # Are we in all-mode?
    if ($catFile eq '*') {
        $retVal->{allMode} = 1;
    } else {
        $retVal->{allMode} = 0;
        # Open the input file and skip the header.
        open(my $ih, "<$catFile") || die "Could not open category file: $!";
        my $line;
        if (! $nohead) {
            $line = <$ih>;
        }
        # Loop through the categories.
        while (! eof $ih) {
            my $line = <$ih>;
            chomp $line;
            my ($catName) = split /\t/, $line;
            my $catID = $retVal->name_to_id($catName);
            $catH{$catID} = $catName;
        }
        close $ih;
    }
    # All done. Return the object.
    return $retVal;
}

=head2 Virtual Methods

=head3 name_to_id

    my $catID = $catHelper->name_to_id($catName);

Return the ID for a category given its name string. The default is to return the name unchanged.

=over 4

=item catName

The displayable name for the category. This is also its input value in the category file.

=item RETURN

Returns the internal ID for the category.

=back

=cut

sub name_to_id {
    my ($self, $catName) = @_;
    return $catName;
}

=head3 all_cats

    my @cats = $catHelper->all_cats($dbString);

Return a list of all the categories in which a feature belongs. The default is to assume there is a single name and convert it to an ID.

=over 4

=item dbString

The value for the feature found in the field named by the L</field_name> method.

=item RETURN

Returns a list of category IDs.

=back

=cut

sub all_cats {
    my ($self, $dbString) = @_;
    my $retVal = $self->name_to_id($dbString);
    return ($retVal);
}

=head3 field_name

    my $field_name = $catHelper->field_name();

Return the name of the feature field used to extract the category name.

=cut

sub field_name {
    die "Pure virtual field_name called.";
}

=head2 Query Methods

=head3 id_to_name

    my $catName = $catHelper->id_to_name($catID);

Return the name for an identified category, or C<undef> if the category is not of interest.

=over 4

=item catID

ID of the category whose name is desired.

=item RETURN

Returns the name of the category with the specified ID.

=back

=cut

sub id_to_name {
    my ($self, $catID) = @_;
    return $self->{catH}{$catID} // $catID;
}


=head3 get_cats

    my $catHash = $catHelper->get_cats($genome);

This is the basic workhorse method for this object. It reads all the features for a genome and returns the location for each feature that is the sole
representative of a category.

=over 4

=item genome

The ID of the genome of interest.

=item RETURN

Returns a reference to a hash that maps the ID of each singly-occurring category to a L<BasicLocation> object for its location on the genome. Only
categories in the category ID hash will be considered.

=back

=cut

sub get_cats {
    my ($self, $genome) = @_;
    # Get the P3DataAPI object.
    my $p3 = $self->{p3};
    # Get the category ID hash and the all-mode switch.
    my $catH = $self->{catH};
    my $allMode = $self->{allMode};
    # Read all the genome features.
    my $catField = $self->field_name();
    my $results = P3Utils::get_data($p3, feature => [['eq', 'genome_id', $genome]], [$catField, 'sequence_id', 'start', 'strand', 'end']);
    # This will hold the number of times each category ID is found.
    my %count;
    # This will hold the location of each category's feature.
    my %retVal;
    for my $result (@$results) {
        # Get the category name and the feature location. Note that sometimes the end-location is missing.
        my ($catName, $contig, $start, $strand, $end) = @$result;
        $end ||= $start;
        my $len = $end + 1 - $start;
        # Compute the location.
        my $loc = BasicLocation->new([$contig, $start, $strand, $len]);
        # Get the category IDs.
        my @cats = $self->all_cats($catName);
        for my $cat (@cats) {
            if ($allMode || $catH->{$cat}) {
                # Here the category is of interest.
                $count{$cat}++;
                $retVal{$cat} = $loc;
            }
        }
    }
    # Remove multiply-occurring categories.
    my @cats = keys %retVal;
    for my $cat (@cats) {
        if ($count{$cat} != 1) {
            delete $retVal{$cat};
        }
    }
    # Return the hash.
    return \%retVal;
}


1;