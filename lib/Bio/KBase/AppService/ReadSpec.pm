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


package Bio::KBase::AppService::ReadSpec;

    use strict;
    use warnings;
    use File::Basename;

=head1 Object for Generating Read Input Specifications in P3 CLI Scripts

This object handles input specifications for reads.  The user can specify multiple read sources, including paired-end libraries,
IDs from the NCBI Sequence Read Archive, interleaved single-end libraries, and simple single-end libraries.  This object generates
the L<GetopT::Long/GetOptions> specifications for the four input types as well as their modifiers and provides a method to parse
the options into a parameter object.

Note that because L<Getopt::Long> suppresses errors, this method collects errors in a queue instead of calling C<die>.
When L</check_for_reads> or L</store_libs> is called, this queue is interrogated and the C<die> is thrown an that time.

The parameters handled by this object are as follows.

=over 4

=item --workspace-path-prefix

Base workspace directory for relative workspace paths.

=item --workspace-upload-path

Name of workspace directory to which local files should be uplaoded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --paired-end-lib

Two paired-end libraries containing reads.  These are coded with a single invocation, e.g. C<--paired-end-lib left.fa right.fa>.  The
libraries must be paired FASTQ files.  A prefix of C<ws:> indicates a file is in the PATRIC workspace; otherwise they are uploaded
from the local file system.  This parameter may be specified multiple times.

=item --single-end-lib

A library of single reads.  This must be a FASTQ file.  A prefix of C<ws:> indicates a file is in the PATRIC workspace; otherwise they are
uploaded from the local file system.  This parameter may be specified multiple times.

=item --srr-id

A run ID from the NCBI sequence read archive.  The run will be downloaded from the NCBI for processing.  This parameter may be specified
multiple times.

=back

The following options are available for assembly mode.

These options modify the way reads are processed during assembly, so they should precede any library specifications to which they apply.
For example,

    --platform illumina --paired-end-lib S1.fq S2.fq --platform pacbio --single-end-lib ERR12345.fq  --srr-id SRR54321

means that the local files C<S1.fq> and C<S2.fq> are from the illumina platform, but the single-end library C<ERR12345.fq> comes
from the pacbio platform.  These options B<only> apply to FASTQ libraries, and not to libraries accessed via na NBCI ID.  Thus
C<SRR54321> above will use the default mode of having its platform inferred from the data.

=over 4

=item --platform

The sequencing platform for the subsequent read library or libraries.  Valid values are C<infer>, C<illumina>, C<pacbio>, or <nanopore>.
The default is C<infer>.

=item --insert-size-mean

The average size of an insert in all subsequent read libraries, used for optimization.

=item --insert-size-stdev

The standard deviation of the insert sizes in all subsequent read libraries, used for optimization.

=item --read-orientation-inward

Indicates that all subsequent read libraries have the standard read orientation, with the paired ends facing inward.  This is the default.

=item --read-orientation-outward

Indicates that all subseqyent read libraries have reverse read orientation, with the paired ends facing outward.

=back

The following options are provided for analysis mode.  These modify the way the reads are analyzed, and should precede any library specifications
to which they apply.  For example,

    --date 01/12/2024 --primers midnight,V1 --paired-end-lib S1.fq S2.fq --primers ARTIC,V5.3.2 --single-end-lib ERR12345.fq  --srr-id SRR54321

means that the local files C<S1.fq> and C<S2.fq> used V1 of the midnight primers, but the single-end library C<ERR12345.fq> and
the NCBI library SRR54321 use the ARTIC V5.3.2 primers.  All of the samples are dated 01/12/2024.

=over 4

=item date

Date of the subsequent samples, in I<MM/DD/YYYY> format.

=item primers

Name and version of the primer set used, separated by a comma.  The default is C<ARTIC,V5.3.2>.  Note that the C<V> is required in the version.

=back

The following options are available in RNA Seq mode.

These options modify the way reads are labelled during processing, so they must precede the library specifications to which
they apply.  So, for example

    --condition low_temp --srr-id SRR12345 --condition high_temp --srr-id SRR67890

Means that sample SRR12345 was tested in the C<low_temp> condition and SRR67890 was tested in the C<high_temp> condition.

=over 4

=item --condition

Name of a condition that applies to this library.

=back

=cut

use constant LEGAL_PLATFORMS => { infer => 1, illumina => 1, pacbio => 1, nanopore => 1 };
use constant LEGAL_PRIMERS => {
        'ARTIC,V5.3.2' => 1, 'ARTIC,V4.1' => 1, 'ARTIC,V4' => 1, 'ARTIC,V3' => 1,  'ARTIC,V2' => 1, 'ARTIC,V1' => 1,
        'midnight,V1' => 1, 'qiagen,V1' => 1, 'swift,V1' => 1, 'varskip,V2' => 1, 'varskip,V1a' => 1, 'varskip-long,V1a' => 1
     };

=head2 Special Methods

=head3 new

    my $reader = Bio::KBase::AppService::ReadSpec->new($uploader);

Create a new read input specification handler.

=over 4

=item uploader

L<Bio::KBase::AppService::UploadSpec> object for processing files.

=item options

A hash of options, including zero or more of the following.

=over 8

=item assembling

If TRUE, then it is presumed the reads are being assembled, and additional options are allowed.  The default is FALSE.

=item rnaseq

If TRUE, this it is presumed the reads contain RNA Seq expression data.  The default is FALSE.

=item srrAlt

If TRUE, the SRR IDs will be coded as structures instead of lists.

=item simple

If TRUE, the read library structures will be simplified.

=item single

If TRUE, only one read library can be specified.

=item samples

If specified, default sample IDs will be added to all the libraries (counting each paired set as a single library).  This automatically
implies C<srrAlt> and changes the SRR parameter label to "srr_libs".

=item analysis

If specified, special analysis metadata can be specified.  This automatically implies C<srrAlt> and changes the SRR parameter label to "srr_libs".

=back

=back

=cut

sub new {
    my ($class, $uploader, %options) = @_;
    my $retVal = {
        uploader => $uploader,
        platform => undef,
        read_orientation_outward => undef,
        insert_size_mean => undef,
        insert_size_stdev => undef,
        paired_end_libs => [],
        single_end_libs => [],
        simple => ($options{simple} // 0),
        srr_ids => [],
        saved_file => undef,
        errors => [],
        conditions => {},
        curr_condition => undef,
        sample_date => undef,
        sample_primers => 'ARTIC/V5.3.2',
        assembling => ($options{assembling} // 0),
        srrAlt => ($options{srrAlt} // 0),
        single => ($options{single} // 0),
        rnaseq => ($options{rnaseq} // 0),
        samples => ($options{samples} // 0),
        analysis => ($options{analysis} // 0),
        srr_label => 'srr_ids'
    };
    if ($retVal->{samples} || $retVal->{analysis}) {
        $retVal->{srrAlt} = 1;
    }
    if ($retVal->{samples} || $retVal->{analysis} || $retVal->{rnaseq}) {
        $retVal->{srr_label} = 'srr_libs';
    }

    bless $retVal, $class;
    return $retVal;
}

=head3 lib_options

This method returns a list of L<Getopt::Long> option specifications for the different parameters involved in read input
specification.  This includes the input libraries by type as well as the sequencing platform identifier and
tweaks such as the mean insert size.  The file upload options from L<Bio::KBase::AppService::UploadSpec> are automatically
incorporated in the list.

    my @options = $reader->lib_options();

=cut

sub lib_options {
    my ($self) = @_;
    my @parms =  ("paired-end-lib|paired-end-libs=s{2}" => sub { $self->_pairedLib($_[1]); },
            "single-end-lib=s" => sub { $self->_singleLib($_[1]); },
            "srr-id=s" => sub { $self->_srrDownload($_[1]); });
    if ($self->{assembling}) {
        push @parms,
            "platform=s" => sub { $self->_setPlatform($_[1]); },
            "read-orientation-outward" => sub { $self->{read_orientation_outward} = 1; },
            "read-orientation-inward" => sub { $self->{read_orientation_outward} = 0; },
            "insert-size-mean=i" => sub { $self->{insert_size_mean} = $_[1]; },
            "insert-size-stdev=i" => sub { $self->{insert_size_stdev} = $_[1]; };
        $self->{platform} = 'infer';
    }
    if ($self->{rnaseq}) {
        push @parms,
            "condition=s" => sub { $self->_setCondition($_[1]); };
    }
    if ($self->{analysis}) {
        push @parms,
            "date=s" => sub { $self->_setDate($_[1])},
            "primers=s" => sub { $self->_setPrimers($_[1])};
    }
    return @parms;
}

=head3 _pairedLib

    $reader->_pairedLib($fileName);

This method processes a file specification for a paired-end library.  We expect two of these to come in one at a time.  When the
first one is processed, we add it to the saved-file queue.  When the second one is processed, we create a parameter specification
for the two libraries and save it in C<paired_end_libs> list.

=over 4

=item fileName

Name of the file to put in a paired-end library.

=back

=cut

sub _pairedLib {
    my ($self, $fileName) = @_;
    eval {
        # Verify that the user has not put an option in the file list.
        my $saved = $self->{saved_file};
        if ($saved && substr($fileName, 0, 1) eq '-') {
            die "paired_end_libs requires two parameters, but $fileName found.";
        }
        # Get the uploader and convert the file name.
        my $uploader = $self->{uploader};
        my $wsFile = $uploader->fix_file_name($fileName, 'reads');
        if (! $saved) {
            # Here we have the first file of a pair.
            $self->{saved_file} = $wsFile;
        } else {
            # Here it is the second file. Create the libraries spec.
            my $lib = {
                read1 => $saved,
                read2 => $wsFile
            };
            # If we are not simple, we need more.
            if (! $self->{simple}) {
                # Add the optional parameters.
                $self->_processTweaks($lib);
            }
            # If we are doing samples, compute the default sample ID.
            if ($self->{samples}) {
                # Get the base file names.
                my $read1Base = basename($saved);
                my $read2Base = basename($wsFile);
                # The default is to use the common prefix.  Otherwise, we use single-file
                # technology on the left reads.
                my $i = 1;
                while (substr($read1Base, 0, $i) eq substr($read2Base, 0, $i)) { $i++; }
                if ($i >= 5) {
                    $lib->{sample_id} = _remove_suffixes(substr($read1Base, 0, $i-1));
                } else {
                    $lib->{sample_id} = _compute_sample_id($saved);
                }

            }
            # Queue the library pair.
            push @{$self->{paired_end_libs}}, $lib;
            # Denote we are starting over.
            $self->{saved_file} = undef;
        }
    };
    if ($@) {
        push @{$self->{errors}}, $@;
    }
}

=head3 _interleavedLib

    $reader->_interleavedLib($fileName);

Store a file as an interleaved paired-end library.  In this case, only a single library is specified.

NOTE that this is a placeholder for the future, since BV-BRC doesn't support this yet.

=over 4

=item fileName

Name of the file containing interleaved pair-end reads.

=back

=cut

sub _interleavedLib {
    my ($self, $fileName) = @_;
    eval {
        # Get the uploader and convert the file name.
        my $uploader = $self->{uploader};
        my $wsFile = $uploader->fix_file_name($fileName, 'reads');
        # Create the library specification.
        my $lib = {
            read1 => $wsFile,
            interleaved => 1
        };
        # Add the optional parameters.
        $self->_processTweaks($lib);
        # If we are doing samples, compute the default sample ID.
        if ($self->{samples}) {
            $lib->{sample_id} = _compute_sample_id($wsFile);
        }
        # Add it to the paired-end queue.
        push @{$self->{paired_end_libs}}, $lib;
    };
    if ($@) {
        push @{$self->{errors}}, $@;
    }
}

=head3 _singleLib

    $reader->_singleLib($fileName);

Here we have a file name for a single-end read library.  Add it to the single-end queue.

=over 4

=item fileName

Name of the file containing interleaved pair-end reads.

=back

=cut

sub _singleLib {
    my ($self, $fileName) = @_;
    eval {
        # Get the uploader and convert the file name.
        my $uploader = $self->{uploader};
        my $wsFile = $uploader->fix_file_name($fileName, 'reads');
        # Create the library specification.  Note that the platform is the only tweak allowed.
        my $lib = {
            read => $wsFile
        };
        # Add the optional parameters if we are not simple.
        if (! $self->{simple}) {
            $self->_processTweaks($lib);
        }
        # Compute the sample ID if needed.
        if ($self->{samples}) {
            $lib->{sample_id} = _compute_sample_id($wsFile);
        }
        # Add it to the single-end queue.
        push @{$self->{single_end_libs}}, $lib;
    };
    if ($@) {
        push @{$self->{errors}}, $@;
    }
}

=head3 _srrDownload

    $reader->_srrDownload($srr_id);

Here we have an SRA accession ID and we want to queue a download of the sample from the NCBI.

=over 4

=item srr_id

SRA accession ID for the sample to download.

=back

=cut

sub _srrDownload {
    my ($self, $srr_id) = @_;
    my $srrSpec = $srr_id;
    if ($self->{rnaseq}) {
        # Format the SRA accession with a condition.
        $srrSpec = { srr_accession => $srr_id };
        if (defined $self->{condition}) {
            $srrSpec->{condition} = $self->{condition};
        }
    } elsif ($self->{srrAlt}) {
        # Format the SRA accession without a condition.
        $srrSpec = { srr_accession => $srr_id };
    }
    if ($self->{samples}) {
        $srrSpec->{sample_id} = $srr_id;
    }
    if ($self->{analysis}) {
        $self->_tweakLibs2($srrSpec);
    }
    push @{$self->{srr_ids}}, $srrSpec;
}

=head3 _setPlatform

    $reader->_setPlatform($platform);

Specify the platform for subsequent read libraries.  This throws an error if the platform is invalid.

=over 4

=item platform

Platform name to use.

=back

=cut

sub _setPlatform {
    my ($self, $platform) = @_;
    if (! LEGAL_PLATFORMS->{$platform}) {
        push @{$self->{errors}}, "Invalid platform name \"$platform\" specified.";
    } else {
        $self->{platform} = $platform;
    }
}

=head3 _setPrimers

    $reader->_setPrimers($spec);

Specify the primer type and version for subsequent read libraries.  This throws an error if the specification is invalid.

=over 4

=item spec

Primer type Platform name to use.

=back

=cut

sub _setPrimers {
    my ($self, $spec) = @_;
    if (! LEGAL_PRIMERS->{$spec}) {
        push @{$self->{errors}}, "Invalid primer spec \"$spec\" specified.";
    } else {
        $self->{primers} = $spec;
    }
}

=head3 _setDate

    $reader->_setDate($date);

Specify the sample level date for subsequent read libraries.  The date must be a valid date string.

=over 4

=item date

Sample level date to use, in I<MM/DD/YYYY> format.

=back

=cut

sub _setDate {
    my ($self, $date) = @_;
    if ($date =~ /^([0-1][0-9])\/([0-3][0-9])\/([1-2][0-9][0-9][0-9])/) {
        if ($1 > 12 || $1 <= 0 || $2 <= 0 || $2 > 31) {
            push @{$self->{errors}}, "Invalid sample date \"$date\".";
        } else {
            $self->{date} = $date;
        }
    } else {
        push @{$self->{errors}}, "Invalid format for date \"$date\".  Should be MM/DD/YYYY.";
    }
}

=head3 _setCondition

    $reader->_setCondition($condition);

Specify the condition for subsequent read libraries.  The condition can be any string.

=over 4

=item condition

Condition name to use.

=back

=cut

sub _setCondition {
    my ($self, $condition) = @_;
    my $conditionH = $self->{conditions};
    if (! $conditionH->{$condition}) {
        # Here we need to add this condition.
        $conditionH->{$condition} = scalar(keys %$conditionH) + 1;
    }
    $self->{condition} = $conditionH->{$condition};
}

=head2 Query Methods

=head3 check_for_reads

    my $flag = $uploader->check_for_reads();

Return TRUE if there are read files specified, else FALSE.

=cut

sub check_for_reads {
    my ($self) = @_;
    $self->_errCheck();
    my $retVal;
    if (scalar @{$self->{paired_end_libs}}) {
        $retVal = 1;
    } elsif (scalar @{$self->{single_end_libs}}) {
        $retVal = 1;
    } elsif (scalar @{$self->{srr_ids}}) {
        $retVal = 1;
    }
    return $retVal;
}

=head3 store_libs

    $reader->store_libs($params);

Store the read-library parameters in the specified parameter structure.

=over 4

=item params

Parameter structure into which the read libraries specified on the command line should be stored.

=back

=cut

sub store_libs {
    my ($self, $params) = @_;
    $self->_errCheck();
    if ($self->{single}) {
        my @libs = (@{$self->{paired_end_libs}}, @{$self->{single_end_libs}},
            @{$self->{srr_ids}});
        if (scalar @libs > 1) {
            die "Too many read libraries specified.  Only one is allowed.";
        }
    }
    if (scalar @{$self->{paired_end_libs}}) {
        $params->{paired_end_libs} = $self->{paired_end_libs};
    }
    if (scalar @{$self->{single_end_libs}}) {
        $params->{single_end_libs} = $self->{single_end_libs};
    }
    if (scalar @{$self->{srr_ids}}) {
        $params->{$self->{srr_label}} = $self->{srr_ids};
    }
    if ($self->{rnaseq}) {
        my $conditionH = $self->{conditions};
        my @conditions;
        for my $cond (keys %$conditionH) {
            $conditions[$conditionH->{$cond} - 1] = $cond;
        }
        $params->{experimental_conditions} = \@conditions;
    }
}

=head2 Internal Utilities

=head3 _errCheck

    $reader->_errCheck();

This method will throw an error if one of the read libraries is invalid.

=cut

sub _errCheck {
    my ($self) = @_;
    my $errors = $self->{errors};
    if (@$errors) {
        print join("\n", @$errors) . "\n";
        die "Error preparing read libraries.";
    }
}

=head3 _processTweaks

    $reader->_processTweaks($lib);

Add the optional parameters to a library specification.

=over 4

=item lib

Hash reference containing the current library specification.  Optional parameters with values will be added to it.

=back

=cut

sub _processTweaks {
    my ($self, $lib) = @_;
    if (! $self->{assembling}) {
        for my $parm (qw(insert_size_mean insert_size_stdev condition platform read_orientation_outward)) {
            if ( defined $self->{$parm} ) {
                $lib->{$parm} = $self->{$parm};
            }
        }
    }
    if ($self->{analysis}) {
        $self->_tweakLibs2($lib);
    }
}

=head3 _tweakLibs2

    $reader->_tweakLibs2($lib);

Add analysis parameters to the read-library specification.

=over 4

=item lib

Library specification to modify.

=back

=cut

sub _tweakLibs2 {
    my ($self, $lib) = @_;
    my ($type, $v) = split /,/, $self->{primers};
    $lib->{primers} = $type;
    $lib->{primer_version} = $v;
    if ($self->{date}) {
        $lib->{sample_level_date} = $self->{date};
    }
}

=head3 _compute_sample_id

    my $sample_id = _compute_sample_id($fileName);

Compute the default sample ID for a filename.

=over 4

=item fileName		name of the file containing the sample's reads

=item RETURN

Returns the desired default sample ID.

=back

=cut

sub _compute_sample_id {
    my ($fileName) = @_;
    # Get the base name.
    my $readBase = basename($fileName);
    my $retVal = $readBase;
    # Remove the extension, if possible.
    if ($readBase =~ /^(.+)\.[a-z]+\.gz$/i) {
        $retVal = $1;
    } elsif ($readBase =~ /^(.+)\.[a-z]+$/i) {
        $retVal = $1;
    }
    $retVal = _remove_suffixes($retVal);
    return $retVal;
}

=head3 _remove_suffixes

    my $fixed = _remove_suffixes($name);

Remove common suffixes from a sample ID.

=over 4

=item name

Sample ID name to process.

=item RETURN

Returns a slightly friendlier version of the sample ID name.

=cut

sub _remove_suffixes {
    my ($name) = @_;
    my $retVal;
    # Remove common suffixes.
    if ($name =~ /^(.+)_[a-z]?$/i) {
        $retVal = $1;
    } else {
        $retVal = $name;
    }
    return $retVal;

}

1;
