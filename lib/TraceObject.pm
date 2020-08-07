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


package TraceObject;

    use strict;
    use warnings;

=head1 Tracing Object

This object outputs trace messages to STDERR. The message is passed via the L/Progress> method.

=head2 Special Methods

=head3 new

    my $tracer = TraceObject->new($oh);

Create a new trace object.

=over 4

=item oh

Open file handle on which to write the progress messages. If omitted, STDERR is used.

=back

=cut

sub new {
    my ($class, $oh) = @_;
    $oh //= \*STDERR;
    my $retVal = { handle => $oh };
    bless $retVal, $class;
    return $retVal;
}

=head2 Public Methods

=head3 Progress

    $tracer->Progress($message);

Output the message.

=over 4

=item message

Message text to output.

=back

=cut

sub Progress {
    my ($self, $message) = @_;
    my $oh = $self->{handle};
    print $oh "$message\n";
}


1;