package Endvance;

use strict;
use warnings;
use autodie;
use feature ':5.14';

use Carp;

use POSIX qw/LC_ALL LC_MESSAGES setlocale strftime/;
use locale;

setlocale LC_ALL,      'ru_RU.UTF-8';
setlocale LC_MESSAGES, 'C';

use Cwd qw/realpath/;
use FindBin;
use JSON;
use Const::Fast;
use DBI;

use Endvance::Base;
use Endvance::Parser;

# Default commands for VCS
const my @GIT => [qw/git add */], [qw/git commit -a -m/];

# Comment the commit with strftime();
const my $COMMENT => 'Endvance backed up this at %F %T';

# Function
# Performs all tasks pending, main entry point
# Takes     :   n/a
# Returns   :   n/a
sub perform {
    my $self = shift || __PACKAGE__->new();
    my $bases = $self->bases;
    while ( my ( $base_name => $base_hash ) = each(%$bases) ) {
        my $base = Endvance::Base->new( $self, $base_name => $base_hash );
        $base->backup;
    }
    $self->commit;
}

# Object method
# Reads bases list and their exclusions from storage and config
# Takes     :   n/a
# Throws    :   if configured base is absent from the storage
# Returns   :   Hash of bases' names and their exclusions
sub bases {
    my $self = shift;

    # Get bases hash from storage
    my $bases = $self->bases_all;

    # Bases list from config

    my $bases_conf = $$self{ 'conf' }{ 'bases' };

    # Wrong bases in config
    my $bases_absent =
        [ grep { not defined $$bases{ $_ } } keys %$bases_conf ];
    croak( "Configured bases are absent in storage: " . join ', ',
        @$bases_absent )
        if @$bases_absent > 0;

    # Merge storage and config bases hashes
    $bases = { %$bases, %$bases_conf };

    # Purge bases configured as 1
    while ( my ( $base => $base_val ) = each(%$bases_conf) ) {
        unless ( ref $base_val ) {
            if ($base_val) { delete $$bases{ $base }; }
        }
    }

    return $bases;
}

# Object method
# Reads bases list from storage
# Takes     :   n/a
# Returns   :   Hash of bases' names and empty hashes
sub bases_all {
    my $self  = shift;
    my $dbh   = $$self{ 'dbh' };
    my $bases = $dbh->selectall_hashref( 'show databases' => 'Database' );
    croak("No databases: $!") unless @{ [%$bases] } > 0;
    return $bases;
}

# Object method
# Commits changes to VCS
# Takes     :   n/a
# Returns   :   n/a
sub commit {
    my $self = shift;
    my @cmd  = map { my @command = @$_; \@command; } $self->vcs_cmd;
    push @{ $cmd[ @cmd - 1 ] }, $self->vcs_msg;
    foreach (@cmd) { &eval_cmd($_) }
}

# Function
# Executes the command given and croaks if it fails.
# Takes     :   ArrayRef command
# Throws    :   if command failed
# Returns   :   n/a
sub eval_cmd {
    my $cmd = shift;
    system @$cmd;
    if ( $? == -1 ) {
        croak("failed to execute: $!");
    }
    elsif ( $? & 127 ) {
        croak(
            sprintf "child died with signal %d, %s coredump",
            ( $? & 127 ),
            ( $? & 128 ) ? 'with' : 'without'
        );
    }
    else {
        # warn( sprintf "child exited with value %d\n", $? >> 8 );
    }
}

# Object method
# Provides commit message for VCS, via strftime()
# Takes     :   n/a
# Depends   :   on $COMMENT lexical constant
# Returns   :   Str a message for the commit
sub vcs_msg {
    my $self = shift;
    return strftime( $COMMENT => localtime );
}

# Static method
# Constructor
# Takes     :   n/a
# Returns   :   Endvance object
sub new {
    my $class  = shift;
    my $conf   = $class->configure;
    my $parser = &parser;
    my $dbh    = &db_connect( $$conf{ 'config' }{ 'db' } );
    my $dir    = $class->dir($conf);
    my $self   = bless {
        'conf'   => $conf,
        'parser' => $parser,
        'dbh'    => $dbh,
        'dir'    => $dir,
    }, $class;
    croak("Chdir $dir: $!") unless chdir $dir;
    return $self;
}

# Function
# Connects to database as stated in the configuration argument
# Takes     :   database configuration
# Returns   :   database_handle
sub db_connect {
    my $db_conf = shift;
    my @args = map { $$db_conf{ $_ } } qw/dsn user pass/;
    if ( defined $$db_conf{ 'host' } ) {
        $args[0] .= "host=$$db_conf{ 'host' }";
    }
    elsif ( defined $$db_conf{ 'socket' } ) {
        $args[0] .= "mysql_socket=$$db_conf{ 'socket' }";
    }
    else {
        croak("No host or socket configured for database connection");
    }
    my $dbh = DBI->connect(@args);
    croak("Connect to database: $!") unless $dbh;
}

# Static method
# Reads configuration file
# Takes     :   n/a
# Depends   :   optional config file name given at @ARGV
# Returns   :   configuration hash, the keys are 'bases', 'config'
sub configure {
    my $self = shift;
    my $fn   = shift;
    $fn //= shift @ARGV;
    $fn //= realpath( $FindBin::Bin . '/../etc' ) . '/' . $FindBin::Script
        =~ s/\.[^\/\.]*$/.json/r;
    open my $fh, '<' => $fn;
    my $json = '';
    while (<$fh>) { $json .= $_ }
    my $conf = from_json($json);
    return $conf;
}

# Function
# Constructs the insert statement parser
# Takes     :   n/a
# Depends   :   on $grammar package variable (const)
# Returns   :   Parser::RecDescent object
sub parser {
    my $parser = Endvance::Parser->new;
    return $parser;
}

# Static or object method
# Gets the directory where the backup to reside
# Takes     :   optional 'config' hash, the object's 'config' attribute will
#               be used instead if omitted
# Depends   :   on 'dir' value of the 'config' setting
# Returns   :   Str directory name
sub dir {
    my $self   = shift;
    my $config = shift;
    $config //= $$self{ 'conf' }{ 'config' };
    my $dir =
        defined $$config{ 'dir' }
        ? $$config{ 'dir' }
        : realpath( $FindBin::Bin . '/../var' );
    return $dir;
}

# Object method
# Gets the VCS commands
# Takes     :   n/a
# Depends   :   on @GIT lexical constant
# Returns   :   Array of ArrayRefs of command and parameters, the last is
#               expected to be added the commit message as its argument
sub vcs_cmd {
    return @GIT;
}

1;
