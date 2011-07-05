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

our $VERSION = '0.01';

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

    my $config = $$self{ 'conf' }{ 'config' };
    if( defined($$config{ 'files_delete' }) and $$config{ 'files_delete' } ) {
        while ( my ( $base_name => $base_hash ) = each(%$bases) ) {
            my $base = Endvance::Base->new( $self, $base_name => $base_hash );
            $base->file_remove;
        }
    }
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
# Returns   :   HashRef of bases' names and empty hashes
sub bases_all {
    my $self  = shift;
    my $dbh   = $$self{ 'dbh' };
    my $bases = $dbh->selectall_hashref( 'show databases' => 'Database' );
    croak( "No databases: $!" ) unless keys( %$bases ) > 0;
    foreach my $base ( keys %$bases ) { $$bases{$base} = {} }
    return $bases;
}

# Object method
# Commits changes to VCS
# Takes     :   n/a
# Returns   :   n/a
sub commit {
    my $self = shift;
    my @cmd  = ( @{ $self->vcs_cmd } );
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
    my $attrs = { 'RaiseError' => 1 };
    if( defined $$db_conf{ 'attrs' } ) {
        $attrs = { %$attrs, %{ $$db_conf{ 'attrs' } } };
    }
    my $dbh = DBI->connect(@args, $attrs );
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
        =~ s/([^\/\.])(\.[^\/\.]*)?$/$1.json/r;
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
# Depends   :   on { 'conf' ]{ 'config' }{ 'vcs_commands' } attribute
# Returns   :   ArrayRef of ArrayRefs of command and parameters, the last is
#               expected to be added the commit message as its argument
sub vcs_cmd {
    my $self = shift;
    my $config = $$self{ 'conf' }{ 'config' };
    my $vcs_commands = $$config{ 'vcs_commands' };
    return $vcs_commands;
}

1;

__END__

=pod

=head1 NAME

C<Endvance> - backup mariadb/mysql databases to Git VCS/SCM

=head1 VERSION

Initial version 0.01 is described here.

=head1 SYNOPSIS

=head2 Binary script supplied

Suppose your archive or snapshot is called endvance.tar.gz and you have placed
it into the separate directory. Extract the archive:

    tar -zxvf endvance.tar.gz

Next you have to decide where to keep configs and backups I assume them all by
default here. Change working directory to a configuration one:

    cd endvance/etc

Take the sample config file and copy it to the working one:

    cp endvance.sample.json endvance.json

Edit the file according by your needs, at the least mysql credentials at the
very begin.

After that, change to the directory where to store the backups, you can set
the different one as C<"dir"> in the C<"config"> section of a config file:

    cd ../var

Initialize the git repository there:

    git init

This will be the repository to keep your dumps.

Run the C<Endvance> then:

    ../bin/endvance

As its first optional argument, C<Endvance> accepts the configuration file name.

It should finish with the commit output.

=head2 Perl module supplied

In procedural orientation:

    use Endvance;
    Endvance::perform();

Object-oriented:

    use Endvance;
    Endvance->perform;

More object-oriented:

    use Endvance;

    my $endvance = Endvance->new;
    $endvance->perform;

Even more object-oriented:

    ### Should be in MyBackup.pm
    package MyBackup;

    use base 'Endvance';

    # Some subs are overrideable here, 'vcs_cmd' and 'configure' for instance
    # They let you to change the VCS used and a configuration format/filename

    1;

    ### MAIN
    package main;
    use MyBackup;

    my $backup = MyBackup->new;
    $backup->perform;

    1;

=head1 DESCRIPTION

Database backup is a complicated task when it needs to meet some key
requirements like the tight storage and an ability to browse changes. Those
can be met by mean of a version control system appliance but there are
circumstances to trial over in the case if you track changes between sql
dumps.

Main of them is the C<timestamp> columns in the tables and that is why I
needed to make C<Endvance> for myself.

Those C<timestamp> database fields are not necessarily to be defined as a
C<sql> C<timestamp> columns but can carry out the same meaning. In my instance
this is a column in the C<IndexedSearch_docInfo> table keeping information
about the documents indexed for the full text search by mean of
L<DBIx::FullTextSearch> module used in L<http://WebGUI.org> content management
system (C<CMS>). Such a column is defined as:

    `dateIndexed` int(11) NOT NULL DEFAULT '0',

That's it: you can omit the timestamp field if you prefer C<sql> dumps without
columns' names in the C<INSERT> (or C<REPLACE>) statements and you can pass a
C<null> to it in the other case but this one is definitely the case to insert
the predefined content, the C<UNIX_TIMESTAMP()> C<sql> function.

For every other case the C<mysqldump> is taken as it is without any changes.
You can safely omit the databases and/or tables and/or fields that should be
backed up to C<Git> as they appear on a dump.

=head1 USAGE

From your command prompt, run:

    /path/to/your/endvance [</the/other/path/config.json>]

C<Endvance> is designed to be used as a regular cron job. Put it like this to
your C<crontab>:

    5 3 * * * /path/to/endvance  /config/path/config1.json
    # Another server or dir or other configured thing
    5 4 * * * /path/to/endvance  /config/path/config2.json

Care should be taken about configuration file, C<etc/endvance.json> by
default. This is a file in C<JSON> format, described like this:

    // Hash refernce to be Endvance's conf
    {

    // Constant info of the environment
    "config":{

        // Database settings
        "db":{
            "dsn":"dbi:mysql:mysql_enable_utf8=1;",

            // "socket":"/path/to/mysql.sock" can be passed instead of "host"
            "host":"127.0.0.1",
            "user":"endvance",
            "pass":"ecnavdne",

            // additional attributes for DBI->connect()
            "attrs":{
                "mysql_auto_reconnect":1
            }
        },

        // Dump command, no escaping but JSON's is needed
        // Substitutions are made: %u for user, %p for password
        // host/socket and a '-d' for no table's data needed are added
        // at the begin of the command
        // Database and a table name are added at the end
        // "-c" stands for columns names inclusion in the dump here.
        "dump":[
            "/usr/local/bin/mysqldump", "-u", "%u", "--opt", "--skip-extended-insert",
            "--skip-dump-date", "--skip-comments",
            "--skip-quick", "--skip-lock-tables", "--create-options", "-c", "-p%p"
        ]

        // Default commands for VCS
        "vcs_commands":[
            [
                "/usr/local/bin/git","add","*"
            ],
            [
                "/usr/local/bin/git","commit","-a","-m"
            ]
        ],

        // Delete files after commit
        "files_delete":1,
    },

    // Constant info about the databases
    "bases":{

        // For the typical WebGUI database...
        "webgui":{

            // in its "IndexedSearch_docInfo" table ...
            "IndexedSearch_docInfo":{

                // for its "dateIndexed" column ...
                "dateIndexed":{

                    // change its value to the sql statement
                    // any constant should be enclosed in '' here
                    "value":"unix_timestamp()"
                }
            }
        },

        // For the typical Skybill (http://skybill.sf.net) database ...
        "skybill":{

            // skip all those tables' data as they are changed too frequently
            "raw":1,
            "clients":1,
            "servers":1,
            "details_daily":1
        },

        // These databases are not needed (I think) to backup
        "information_schema":1,
        "performance_schema":1
    }
    }



=cut
