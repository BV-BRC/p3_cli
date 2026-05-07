=head1 Submit a Protein Docking Job

This script submits a request to attempt docking of ligands against a protein. The protein is specified as a PDB file or a PDB ID, and the ligands
can either be in a SMILES file or one of three pre-defined named libraries.

=head1 Usage Synopsis

    p3-submit-docking [options] output-path output-name

Start a protein-ligand docking job, producing output in the specified workspace path, using the specified name
for the base filename of the output files.

=head2 Command-Line Options

=over 4

=item --workspace-path-prefix

Base workspace directory for relative workspace paths.

=item --workspace-upload-path

Name of workspace directory to which local files should be uploaded.

=item --overwrite

If a file to be uploaded already exists and this parameter is specified, it will be overwritten; otherwise, the script will error out.

=item --pdb-file

The name of a PDB input file for the protein. The file is presumed to be on your local drive, in which case it
will be uploaded to your BV-BRC workspace (or the workspace specified by C<--workspace-upload-path>) and then used as 
input to the service. If the file name starts with C<ws:>, it is presumed to be a workspace file, and it will be used directly 
without uploading. This parameter is required if C<--pdb-id> is not specified, and must be a file of type I<pdb>.

=item --pdb-id

The PDB ID of the protein to be used for docking. The service will retrieve the structure from the PDB and use it as input. 
This parameter is required if C<--pdb-file> is not specified.

=item --ligands-file

The name of the SMILES file for the ligands. The file is presumed to be on your local drive, in which case it will be uploaded 
to your BV-BRC workspace (or the workspace specified by C<--workspace-upload-path>) and then used as input to the service. 
If the file name starts with C<ws:>, it is presumed to be a workspace file, and it will be used directly without uploading. 
This parameter is required if C<--ligands-lib> is not specified, and must be a file of type I<txt>.

=item --ligands-lib

The name of a pre-defined ligand library. The options are C<exemplar>, C<approved>, and C<experimental>. These correspond to the
options on the web interface. This parameter is required if C<--ligands-file> is not specified.

=item --samples-per-complex

Number of pose samples to generate for each protein-ligand pair. The default is 10. Higher values may improve results but will increase runtime.

=item --inference-steps

Number of diffusion steps for pose generation. Higher values may improve accuracy but will increase runtime. The default is 20.

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
use List::Util;

use constant LIGAND_LIB_MAP => { 
    exemplar => "small_db",
    approved => "approved-drugs",
    experimental => "experimental_drugs"
};

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
my $ligandsFile;
my $ligandsLib;
my $pdbFile;
my $pdbId;
my $samplesPerComplex = 10;
my $inferenceSteps = 20;
# Now we parse the options.
GetOptions($commoner->options(),
    "ligands-file=s" => \$ligandsFile,
    "ligands-lib=s" => \$ligandsLib,
    "pdb-file=s" => \$pdbFile,
    "pdb-id=s" => \$pdbId,
    "samples-per-complex=i" => \$samplesPerComplex,
    "inference-steps=i" => \$inferenceSteps
        );
# Verify the argument count.
if (! $ARGV[0] || ! $ARGV[1]) {
    die "Too few parameters-- output path and output name are required.";
} elsif (scalar @ARGV > 2) {
    die "Too many parameters-- only output path and output name should be specified.  Found : \"" . join('", "', @ARGV) . '"';
}

# Validate the tuning parameters.

if ($samplesPerComplex < 1) {
    die "Invalid samples per complex specified-- must be greater than 0.";
}
if ($inferenceSteps < 1) {
    die "Invalid inference steps specified-- must be greater than 0.";
}

# Handle the output path and name.
my ($outputPath, $outputFile) = $uploader->output_spec(@ARGV);

# Build the parameter structure.
my $params = {
    samples_per_complex => $samplesPerComplex,
    inference_steps => $inferenceSteps,
    batch_size => 10,
    output_path => $outputPath,
    output_file => $outputFile  
};

# Now we handle the inputs. There are two options for each-- a file or a named library.

if ($pdbFile) {
    $params->{user_pdb_file} = [ $uploader->fix_file_name($pdbFile, 'pdb') ];
    $params->{protein_input_type} = 'user_pdb_file';
} elsif ($pdbId) {
    $params->{input_pdb} = [ $pdbId ];
    $params->{protein_input_type} = 'input_pdb';
} else {
    die "No protein specified-- either --pdb-file or --pdb-id must be provided.";
}

if ($ligandsFile) {
    $params->{ligand_ws_file} = $uploader->fix_file_name($ligandsFile, 'txt');
    $params->{ligand_library_type} = 'ws_file';
} elsif ($ligandsLib) {
    my $libId = LIGAND_LIB_MAP->{$ligandsLib};
    if (! $libId) {
        die "Invalid ligand library specified-- must be one of " . join(', ', keys %{LIGAND_LIB_MAP()}) . ".";
    }
    $params->{ligand_named_library} = $libId;
    $params->{ligand_library_type} = 'named_library';
} else {
    die "No ligands specified-- either --ligands-file or --ligands-lib must be provided.";
}

# Submit the job.
$commoner->submit($app_service, $uploader, $params, Docking => 'protein-ligand docking');