=head1 Create a PATRIC login token.

    p3-login [options] username

Create a PATRIC login token, used with workspace operations. To use this script, specify your user name on
the command line as a positional parameter. You will be asked for your password.

The following command-line options are supported.

=over 4

=item logout

The current user is logged out. If this option is specified, the user name is not required.

=item status

Display the name of the user currently logged in. If this option is specified, the user name is not required.

=back

If the command-line option C<--logout> is specified, you will be logged out. In this case, the user name is not required.

=cut

#
# Create a PATRIC login token.
#

use strict;
use LWP::UserAgent;
use Getopt::Long::Descriptive;
use Term::ReadKey;
use Data::Dumper;
use P3DataAPI;
use P3Utils;
use Crypt::RC4;

our $have_config_simple;
eval {
    require Config::Simple;
    $have_config_simple = 1;
};

my $auth_url = "https://user.patricbrc.org/authenticate";
my $token_path = $P3DataAPI::token_path || "$ENV{HOME}/.patric_token";
my $max_tries = 3;

my $opt = P3Utils::script_opts('username', ['logout|logoff', 'log out of PATRIC'],
        ['verbose|v', 'display debugging info'],
        ['status|whoami|s', 'display login status']);

my ($username) = @ARGV;
if ($opt->verbose) {
    print "Token path is $token_path.\n";
}
if ($opt->status || $opt->verbose) {
    if (! -f $token_path) {
        print "You are currently logged out of PATRIC.\n";
    } else {
        open(my $ih, '<', $token_path) || die "Could not open token file: $!";
        my $token = <$ih>;
        if ($token =~ /un=([^\|\@]+\@patricbrc\.org)/) {
            print "You are logged in as $1.\n";
        } else {
            die "Your PATRIC login token is improperly formatted. Please log out and try again.";
        }
    }
}
if ($opt->logout) {
    if (-f $token_path) {
        unlink($token_path) || die "Could not delete login file $token_path: $!";
        print "Logged out of PATRIC.\n";
    } else {
        print "You are already logged out of PATRIC.\n";
    }
}
if (! $opt->status && ! $opt->logout) {
    if (! $username) {
        die "A user name is required.\n";
    }
    # Insure we have the patricbrc.org suffix.
    $username =~ s/\@patricbrc.org$//;

    my $ua = LWP::UserAgent->new;

    for my $try (1..$max_tries)
    {
        my $password = get_pass();

        my $req = {
            username => $username,
            password => $password,
        };
        open(my $oh, ">$token_path-code") || die "Could not open code file: $!";
        my $ref = Crypt::RC4->new($username);
        my $encrypted = $ref->RC4($password);
        my $unpacked = unpack('H*', $encrypted);
        print $oh $unpacked;
        close $oh;
        my $res = $ua->post($auth_url, $req);
        if ($res->is_success)
        {
            my $token = $res->content;
            if ($token =~ /un=([^|]+)/)
            {
                my $un = $1;
                open(T, ">", $token_path) or die "Cannot write token file $token_path: $!\n";
                print T "$token\n";
                # Protect the chmod with eval so it won't blow up in Windows.
                eval { chmod 0600, \*T; };
                close(T);

                #
                # Write to our config files too.
                #
                if ($have_config_simple)
                {
                    write_config("$ENV{HOME}/.patric_config", "P3Client.token", $token, "P3Client.user_id", $un);
                    write_config("$ENV{HOME}/.kbase_config", "authentication.token", $token, "authentication.user_id", $un);
                }
                else
                {
                    warn "Perl library Config::Simple not available; not updating .patric_config or .kbase_config\n";
                }
                print "Logged in with username $un\n";
                exit 0;
            }
            else
            {
                die "Token has unexpected format\n";
            }
        }
        else
        {
            print "Sorry, try again.\n";
        }
    }

    die "Too many incorrect login attempts; exiting.\n";
}

sub write_config
{
    my($file, @pairs) = @_;
    my $cfg = Config::Simple->new(syntax => 'ini');
    if (-f $file)
    {
        $cfg->read($file);
    }
    while (@pairs)
    {
        my($key, $val) = splice(@pairs, 0, 2);
        $cfg->param($key, $val);
    }
    $cfg->save($file);
}

sub get_pass {
    if ($^O eq 'MSWin32')
    {
        $| = 1;
        print "Password: ";
        ReadMode('noecho');
        my $password = <STDIN>;
        chomp($password);
        print "\n";
        ReadMode(0);
        return $password;
    }
    else
    {
        my $key  = 0;
        my $pass = "";
        print "Password: ";
        ReadMode(4);
        while ( ord($key = ReadKey(0)) != 10 ) {
            # While Enter has not been pressed
            if (ord($key) == 127 || ord($key) == 8) {
                chop $pass;
                print "\b \b";
            } elsif (ord($key) < 32) {
                # Do nothing with control chars
            } else {
                $pass .= $key;
                print "*";
            }
        }
        ReadMode(0);
        print "\n";
        return $pass;
    }
}

