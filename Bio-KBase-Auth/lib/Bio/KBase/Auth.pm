package Bio::KBase::Auth;
#
# Common information across the apps
#
# sychan 4/24/2012
use strict;
use Config::Simple;
use URI;
use Bio::KBase::AuthConstants qw(:kbase :globus);

our $VERSION = '0.7.0';

our $ConfPath = glob "~/.kbase_config";

if (defined($ENV{ KB_CLIENT_CONFIG })) {
    if ( -r $ENV{ KB_CLIENT_CONFIG }) {
	$ConfPath = $ENV{ KB_CLIENT_CONFIG };
    } else {
	die "\$ENV{KB_CLIENT_CONFIG} points to an unreadable file: ".$ENV{ KB_CLIENT_CONFIG };
    }
}

# We will have to work this back into the server side config eventually, but lets patch up the current
# mess ASAP - sychan 12/17/2013
#if (defined($ENV{ KB_DEPLOYMENT_CONFIG })) {
#    if ( -r $ENV{ KB_DEPLOYMENT_CONFIG }) {
#	$ConfPath = $ENV{ KB_DEPLOYMENT_CONFIG };
#    } else {
#	die "\$ENV{KB_DEPLOYMENT_CONFIG} points to an unreadable file: ".$ENV{ KB_DEPLOYMENT_CONFIG };
#    }
#}

my $c = Config::Simple->new( filename => $ConfPath);

our %Conf;
our %AuthConf;
our $AuthSvcHost;
our $AuthorizePath;

our $ProfilePath;
our $RoleSvcURL;

# handle to a MongoDB Connection
our $MongoDB = undef;

LoadConfig();

if ($@) {
    die "Invalid MongoDB connection declared in ".$ConfPath." authentication.mongodb = ".
	$Conf{'authentication.mongodb'};
}

# Load a new config file (or reload default config) to override the default settings
sub LoadConfig {
    my( $newConfPath) = $_[0] ? shift : $ConfPath; 

    my $c = Config::Simple->new( $newConfPath);
    %Conf = $c ? $c->vars() : ();
    if (defined( $Conf{'authentication.client_secret'})) {
	$Conf{'authentication.client_secret'} =~ s/\\n/\n/g;
    }

    my $token_url = URI->new(globus_token_url);
    my $profile_url = URI->new(globus_profile_url);

    my $bare = $token_url->clone();
    $bare->query(undef);
    $bare->path('/');

    $AuthSvcHost = $Conf{'authentication.servicehost'} ?
	$Conf{'authentication.servicehost'} : $bare->as_string;
    
    $AuthorizePath = $Conf{'authentication.authpath'} ?
	$Conf{'authentication.authpath'} : $token_url->path;
    
    $ProfilePath = $Conf{'authentication.profilepath'} ?
	$Conf{'authentication.profilepath'} : $profile_url->path;
    
    $RoleSvcURL = $Conf{'authentication.rolesvcurl'} ?
	$Conf{'authentication.rolesvcurl'} : role_service_url;

    eval {
	if ($Conf{'authentication.mongodb'} ) {
	    require MongoDB;
	    $MongoDB = MongoDB::Connection->new( host => $Conf{'authentication.mongodb'});
	}
    };
    
    if ($@) {
	die "Invalid MongoDB connection declared in ".$ConfPath." authentication.mongodb = ".
	    $Conf{'authentication.mongodb'};
    }

    %AuthConf = map { $_, $Conf{ $_} } grep /^authentication\./, keys( %Conf);

}

# This function takes a hash and uses the keys and values as
# settings to be updated in the INI file in $ConfPath
# Values that are not passed into the hash are left
# unmolested. A hash key with an undef value will result
# in that setting being deleted from the INI file.
# Keys must be an alphanumeric string beginning with an alphabetic character
# Values must be either a string(number) or an array reference of strings
#
# The keys will be inserted into authentication section
# of the file specified in $ConfPath

sub SetConfigs {
    my(%params) = @_;
    my $c;

    eval {
	$c = Config::Simple->new( filename => $ConfPath);
	unless ( $c ) {
	    # Config::Simple is a little too simple, it won't create the
	    # file on the fly if you reference it using normal constructor
	    $c = Config::Simple->new( syntax => 'ini');
	    $c->set_block('authentication', {});
	    $c->write( $ConfPath);
	    $c = Config::Simple->new( filename => $ConfPath);
	}
	$c->autosave( 0 ); # disable autosaving so that update is "atomic"
	for my $key (keys %params) {
	    unless ($key =~ /^[a-zA-Z]\w*$/) {
		die "Parameter key '$key' is not a legitimate key value";
	    }
	    unless ((ref $params{$key} eq '') ||
		    (ref $params{$key} eq 'ARRAY')) {
		die "Parameter value for $key is not a legal value: ".$params{$key};
	    }
	    my $fullkey = "authentication." . $key;
	    if (! defined($params{$key})) {
		if (defined($c->param($fullkey))) {
		    $c->delete($fullkey);
		}
	    } else {
		$c->param($fullkey, $params{$key});
	    }
	}
	$c->save($ConfPath);
	chmod 0600, $ConfPath;
	LoadConfig();
    };
    if ($@) {
	die $@;
    }
    return( 1);   
}


# This function looks up the stashed kbase config file, and if it
# exists it pulls out the user_id and token information and returns
# the info.
#
sub GetConfigs {
    my(%params) = @_;
    my $c;
    my $configs = {user_id=>'',token=>''};
    eval {
	$c = Config::Simple->new( filename => $ConfPath);
	if ( $c ) {
	    my $user  = $c->param('authentication.user_id');
	    my $token = $c->param('authentication.token');
	    if (defined($user))  { $configs->{user_id} = $user; } 
	    if (defined($token)) { $configs->{token}   = $token; }
	}
    };
    if ($@) {
	die $@;
    }
    return $configs;
}


1;

__END__
=pod

=head1 Bio::KBase::Auth

OAuth based authentication for Bio::KBase::* libraries.

This is a helper class that stores shared configuration information.

=head2 Class Variables

=over

=item B<$ConfPath>

The path to the INI formatted configuration file. Defaults to ~/.kbase_config, can be overriden by the shell environment variable $KB_CLIENT_CONFIG. Configuration directives for the Bio::KBase::Auth, Bio::KBase::AuthToken and Bio::KBase::AuthUser classes are loaded from the "authentication" section of the INI file.

=item B<%Conf>

A hash containing the full contents loaded from ConfPath (if any). This includes stuff outside of the authentication section.

=item B<%AuthConf>

A hash containing only the directives that begin with "authentication." in %Conf

=item B<$VERSION>

The version of the libraries.

=item B<$AuthSvcHost>

A string specifying the base URL for the authentication and profile service. It defaults to "https://nexus.api.globusonline.org/". Set by 'authentication.servicehost' entry in .kbase_config

=item B<%AuthorizePath>

The path beneath $AuthSvcHost that supports authentication token requests, defaults to "/goauth/token". Set by 'authentication.authpath' in .kbase_config

=item B<$ProfilePath>

The path under $AuthSvcHost that returns user profile information, defaults to "users". Set by 'authentication.profilepath' in .kbase_config

=item B<$RoleSvcURL>

The URL used to query for roles/groups information, defaults to "https://kbase.us/services/authorization/Roles". Set by 'authentication.rolesvcurl' in .kbase_config

=item B<$MongoDB>

A MongoDB::Connection reference that can be activated by defining authentication.mongodb in the configuration file. The value of authentication.mongodb is passed in as the value of the host parameter in the MongoDB::Connection->new() call. The MongoDB connection is used for access to server-side caching features and is not needed for normal operation.

=back

=head2 Class Methods

=over

=item B<LoadConfig( [config path])>

Loads the default INI format file so that the class variables are updated to new values. If no file is passed in, then the default config file is used - if a path is given then it is treated as an INI file and read, and class variables are updated accordingly.

=item B<SetConfigs(%config)>

This function takes a hash and uses the keys and values as settings to be updated in the INI file in $ConfPath. Values that are not passed into the hash are left unmolested. A hash key with an undef value will result in that setting being deleted from the INI file.
Keys must be an alphanumeric string beginning with an alphabetic character.
Values must be either a string(number) or an array reference of strings.

The keys will be inserted into authentication section.

=item B<GetConfigs()>

This function looks up the stashed kbase config file, and if it exists it pulls out the user_id and
token information and returns the info in a hash with keys 'user_id' and 'token' defined. If the user or
token is not set, then the values for 'user_id' and 'token' are set to the empty string.

=back

=cut

