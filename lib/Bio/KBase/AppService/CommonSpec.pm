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


package Bio::KBase::AppService::CommonSpec;

    use strict;
    use warnings;
    use Pod::Usage;

=head1 Common Options for Command-Line Scripts

This object processes options common to all command-line scripts.  Use L</options> to include these options in the
L<Getopt::Long/GetOptions> parameter list.

There are also common methods for script management in here.

The parameters handled by this library include the following.

=over 4

=item --help

Display the command-line usage and exit. The usage will be taken from a level-1 POD section called "Usage Synopsis".

=item --dry-run

Upload the files, display the resulting parameters, and exit without invoking the service.

=item --container_id (internal use only)

ID of the container to run the service job.

=item --reservation (internal use only)

Name of a reservation queue for scheduling the service job.

=back

=head2 Methods

=head3 new

    my $commoner = Bio::KBase::AppService::CommonSpec->new();

Create the common-options object.

=cut

sub new {
    my ($class) = @_;
    my $retVal = { dry => 0 };
    bless $retVal, $class;
    return $retVal;
}

=head3 options

    my @options = $commoner->option();

Return the options list for the common options.

=cut

sub options {
    my ($self) = @_;
    return ("dry-run" => sub { $self->{dry} = 1; },
            "help|h" => sub { print pod2usage({-verbose => 99, '-sections' => 'Usage Synopsis', -exitVal => 0}); },
            "reservation=s" => sub { $self->{reservation} = $_[1] },
            "container-id=s" => sub { $self->{container_id} = $_[1] },
            );
}

=head3 check_dry_run

    $commoner->check_dry_run($param);

If this is a dry run, outputs the JSON and exits.

=over 4

=item param

Parameter object built for execution.

=cut

sub check_dry_run {
    my ($self, $param) = @_;
    if ($self->{dry}) {
        print "Data submitted would be:\n\n";
        print JSON::XS->new->pretty(1)->encode($param);
        exit(0);
    }
}

=head3 submit

    $commoner->submit($app_service, $uploader, $params, $serviceName => $messageName);

Submit a job request to PATRIC.  This also does uploads and a dry-run check.

=over 4

=item app_service

Application service helper.

=item uploader

L<Bio::KBase::AppService::UploadSpec> object for file management, or C<undef> if no files need to be uploaded.

=item params

Parameter structure for the service.

=item serviceName

Formal name of the service.

=item messageName

Informal service name for messages.

=back

=cut

sub submit {
    my ($self, $app_service, $uploader, $params, $serviceName, $messageName) = @_;
    # Add the container ID and reservation.
    if (exists $self->{container_id}) {
        $params->{container_id} = $self->{container_id};
    }
    if (exists $self->{reservation}) {
        $params->{reservation} = $self->{reservation};
    }
    # Do the dry-run check.
    $self->check_dry_run($params);
    # Process uploads.
    if ($uploader) {
        $uploader->process_uploads();
    }
    # Now submit the job request.
    my $task = eval { $app_service->start_app($serviceName, $params, ''); };
    if ($@) {
        die "Error submitting $messageName to PATRIC: $@";
    } elsif (! $task) {
        die "Unknown error submitting $messageName to PATRIC.";
    } else {
        print "Submitted $messageName with id $task->{id}\n";
    }
}

1;


