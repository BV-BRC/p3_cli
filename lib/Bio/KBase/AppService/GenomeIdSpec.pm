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


package Bio::KBase::AppService::GenomeIdSpec;

    use strict;
    use warnings;
    use P3DataAPI;
    use P3Utils;

=head1 Service Module for Genome ID Lists

This module provides methods for validating PATRIC genome IDs.  It makes sure the genome is found in PATRIC.  This is important
when submitting long-running jobs where an error detected after several hours is really annoying.

=head2 Special Methods

=sub validate_genomes

    my $gList = Bio::KBase::AppService::GenomeIdSpec::validate_genomes($ids);

=over 4

=item ids

Either a single genome ID, a local file name, or a comma-delimited list of genome IDs.

=item RETURN

The list of IDs if it is valid, else C<undef>, indicating an error.

=back

=cut

sub validate_genomes {
    my ($ids) = @_;
    my $retVal;
    # Insure if we have input.
    if (! defined $ids) {
        print "No genome IDs specified.\n";
    } else {
        # First, check for a local file.
        if (-s $ids) {
            open(my $ih, '<', $ids) || die "Could not open genome ID file $ids: $!";
            # Skip the header line.
            my $line = <$ih>;
            $retVal = P3Utils::get_col($ih, 0);
            # In case this is a group downloaded from PATRIC, strip off quotes.
            map { $_ =~ s/"//g } @$retVal;
            close $ih;
        } else {
            # Split the IDs using a comma.
            $retVal = [split /,/, $ids];
        }
        # Get rid of the badly-formatted IDs.
        my @bads = grep { $_ !~ /^\d+\.\d+$/ } @$retVal;
        if (scalar @bads) {
            print "Invalid genome ID strings specified: " . join(", ", map { "\"$_\"" } @bads) . "\n";
            undef $retVal;
        } else {
            # Ask PATRIC about the genome IDs.
            my $p3 = P3DataAPI->new();
            my @rows = $p3->query(genome => ['select', 'genome_id', 'domain'], ['in', 'genome_id', "(" . join(",", @$retVal) . ")"]);
            # This will hold all the genome IDs we haven't found yet.
            my %missing = map { $_ => 1 } @$retVal;
            for my $row (@rows) {
                if ($row->{genome_id}) {
                    $missing{$row->{genome_id}} = 0;
                }
            }
            # Output the missing genome IDs.
            for my $genome (sort keys %missing) {
                if ($missing{$genome}) {
                    print "Could not find genome ID $genome in PATRIC.\n";
                    undef $retVal;
                }
            }
        }
    }
    return $retVal;
}

=head3 validate_genome

    my $genomeId = Bio::KBase::AppService::GenomeIdSpec::validate_genome($parmName => $proposedGenomeId);

This method verifies a single genome ID.  It will return C<undef> if the genome ID is invalid, otherwise it will
return the incoming ID.

=over 4

=back

=cut

sub validate_genome {
    my ($parmName, $proposedGenomeId) = @_;
    my $gList = validate_genomes($proposedGenomeId);
    if ($gList && scalar @$gList != 1) {
        die "Must specify a single genome ID for $parmName.";
    }
    return $gList->[0];
}

=head3 process_taxid

    $scientificName = Bio::KBase::AppService::GenomeIdSpec::process_taxid($taxonomyId, $scientificName);

Compute the scientific name using the taxonomy ID, if necessary.

=over 4

=item taxonomyID

Taxonomy ID specified by the client.

=item scientificName

Scientific name specified by the client.

=item RETURN

Returns the real scientific name to use.

=back

=cut

sub process_taxid {
    my ($taxonomyId, $scientificName) = @_;
    my $retVal = $scientificName;
    if (! $taxonomyId) {
        die "Taxonomy ID is required.";
    } elsif (! $scientificName) {
        # Here we have to compute the scientific name.
        require P3DataAPI;
        my $p3 = P3DataAPI->new();
        my @results = $p3->query("taxonomy",
                      ["select", "taxon_name"],
                      ["eq", "taxon_id", $taxonomyId]);
        if (! @results) {
            die "Could not find taxonomy ID $taxonomyId in PATRIC.";
        } else {
            $retVal = $results[0]->{taxon_name};
        }
    }
    return $retVal;
}

1;


