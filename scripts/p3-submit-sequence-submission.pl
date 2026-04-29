=head1 Submit an Viral Sequence Submission Job

This script submits a request to validate a viral GENBANK sequence submission. The sequences
are validated and annotated along with the associated metadata and submission information. 
The output is a folder in the specified workspace directory that will contain an error report
or, if the submission is valid, a validation report.

=head1 Usage Synopsis

    p3-submit-sequence-submission [options] output-path output-name

Start a viral sequence submission job, producing output in the specified workspace path, using the specified name
for the folder containing the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Base workspace directory for relative workspace paths.

=item --workspace-upload-path

Name of workspace directory to which local files should be uploaded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --fasta

The name of a FASTA input file. The file must consist of individual viral DNA sequences for validation and annotation.
B<Currently, only influenza A, B, and C sequences are supported.> If the file name starts with C<ws:>, it is presumed 
to be a workspace file, and it will be used directly without uploading.

=item --metadata

The name of a CSV file containing the metadata for the submission. Information on the required format of this file can be found
at L<https://www.bv-brc.org/workspace/BVBRC@patricbrc.org/BV-BRC%20Templates/sequence_submission_metadata_template.csv>.
If the file name starts with C<ws:>, it is presumed to be a workspace file, and it will be used directly without uploading.

=back

The following options are used to specify the submitter.

=over 4

=item --affiliation

The name of the submitter's affiliated institution.

=item --first-name

First name of the submitter. (required)

=item --last-name

Last name of the submitter. (required)

=item --email

Email address of the submitter. (required)

=item --consortium

The name of the consortium on behalf of which the submission is being made, if any.

=item --country

The country in which the submitter is located.

=item --phone

The submitter's phone number.

=item --street

The submitter's street address.

=item --postal-code

The submitter's postal code.

=item --city

City in which the submitter is located.

=item --state

State or province in which the submitter is located.

=back

The following options are used for assistance and debugging.

=over 4

=item --help

Display the command-line usage and exit.

=item --dry-run

Display the JSON submission string and exit without invoking the service or uploading files.

=back

=cut

use strict;
use Getopt::Long;
use Bio::KBase::AppService::Client;
use P3AuthToken;
use Data::Dumper;
use Bio::KBase::AppService::CommonSpec;
use Bio::KBase::AppService::GenomeIdSpec;
use Bio::KBase::AppService::UploadSpec;


# Insure we're logged in.
my $p3token = P3AuthToken->new();
if (! $p3token->token()) {
    die "You must be logged into BV-BRC to use this script.";
}
# Get a common-specification processor, an uploader, and a reads-processor.
my $commoner = Bio::KBase::AppService::CommonSpec->new();
my $uploader = Bio::KBase::AppService::UploadSpec->new($p3token);

# Get the application service helper.
my $app_service = Bio::KBase::AppService::Client->new();

# Declare the option variables and their defaults.
my $fasta;
my $metadata;
my $affiliation;
my $firstName;
my $lastName;
my $email;
my $consortium;
my $country;
my $phone;
my $street;
my $postalCode;
my $city;
my $state;
# Now we parse the options.
GetOptions($commoner->options(),
    "fasta=s" => \$fasta,
    "metadata=s" => \$metadata,
    "affiliation=s" => \$affiliation,
    "first-name=s" => \$firstName,
    "last-name=s" => \$lastName,
    "email=s" => \$email,
    "consortium=s" => \$consortium,
    "country=s" => \$country,
    "phone=s" => \$phone,
    "street=s" => \$street,
    "postal-code=s" => \$postalCode,
    "city=s" => \$city,
    "state=s" => \$state
);

# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}
if (! $fasta) {
    die "A FASTA file is required.";
} elsif (! $metadata) {
    die "A metadata file is required.";
}
if (! $firstName || ! $lastName || ! $email) {
    die "First name, last name, and email are required submitter information.";
}

# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);

# Initialize the parameter structure.
my $params = {
    output_path => $outputPath,
    output_file => $outputFile,
    affiliation => $affiliation,
    first_name => $firstName,
    last_name => $lastName,
    email => $email,
    consortium => $consortium,
    country => $country,
    phoneNumber => $phone,
    street => $street,
    postal_code => $postalCode,
    city => $city,
    state => $state
};

# Validate and upload (if necessary) the FASTA input file.
$params->{input_fasta_file} = $uploader->fix_file_name($fasta, 'contigs');
$params->{input_source} = 'fasta_file';

# Validate and upload (if necessary) the metadata input file.
$params->{metadata} = $uploader->fix_file_name($metadata, 'csv');

# Submit the job.
$commoner->submit($app_service, $uploader, $params, SequenceSubmission => 'viral sequence validation and annotation');