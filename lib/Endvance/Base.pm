package Endvance::Base;

use strict;
use warnings;
use autodie;

use Carp;

use FindBin;
use Cwd qw/realpath/;

use Endvance::Table;

# Static method
# Constructor
# Takes     :   name of base, Object of Endvance and a HashRef of database
#               name and 1 or a HashRef table and 1 or HashRef of fields and
#               1 to skip fields in them
# Returns   :   object able to backup
sub new {
    my ( $class => $endvance, $name => $hash ) = @_;
    my $self = bless {
        'db_fields'     => $hash,
        'endvance'      => $endvance,
        'name'          => $name,
    }, $class;
    $$self{ 'filename' } = $self->filename;
    return $self;
}

# Object method
# Backs up a base into a file
# Takes     :   n/a
# Returns   :   n/a
sub backup {
    my $self = shift;
    my $write_fh   = $self->open_file;
    $self->backup_db_definition($write_fh);
    my $tables = $self->tables;
    while( my ($table_name => $table_hash) = each %$tables ) {
        my $table = Endvance::Table->new(
            $self => $write_fh, $table_name => $table_hash,
        );
        $table->backup;
    }
    close $write_fh;
}

# Object method
# Backs up a database definition and writes a USE statement
# Takes     :   write file handle
# Depends   :   on 'autodie' pragma
# Throws    :   on output error
# Returns   :   n/a
sub backup_db_definition {
    my($self => $write_fh) = @_;
    my $name = $$self{ 'name' };
    my $dbh = $$self{ 'endvance' }{ 'dbh' };
    my $sql = "show create database `$name`";
    my ($ret_name => $definition) = @{ $dbh->selectall_arrayref($sql)->[0] };
    $definition = "DROP DATABASE IF EXISTS `$name`;\n\n"
        ."$definition;\n";
    say $write_fh $definition;
    say $write_fh "USE `$name`;\n";
}


# Object method
# Opens file to dump sql out to
# Takes     :   n/a
# Depends   :   on 'name' attribute and 'edvance's 'config'ured 'dir'
#               on 'autodie' pragma
# Throws    :   if file can not be opened
# Returns   :   file handle
sub open_file {
    my $self = shift;
    my $fn = $$self{ 'filename' };
    open my $fh, '>' => $fn;
    return $fh;
}

# Object method
# Calculates backup file name
# Takes     :   n/a
# Depends   :   on 'name' and 'endvance's 'dir' attributes
# Returns   :   Str file name to backup
sub filename {
    my $self = shift;
    my $dir  = $$self{ 'endvance' }{ 'dir' };
    my $name = $$self{ 'name' };
    my $fn   = "$dir/$name.sql";
    return $fn;
}

# Onject method
# Removes file that was backed up
# Takes     :   n/a
# Depends   :   on 'autodie' pragma
# Throws    :   if file does not exist or was not deleted here
# Returns   :   n/a
sub file_remove {
    my $self = shift;
    my $fn = $$self{ 'filename' };
    unlink $fn;
}

# Object method
# Returns tables and optionally fields to be backed up
# Takes     :   n/a
# Depends   :   on 'name', 'db_fields', 'endvance' attributes
# Throws    :   on non-existent table configured
# Returns   :   HashRef of tables
sub tables {
    my $self = shift;

    # Two hashes: from database and from config
    my $tables = $self->tables_all;
    my $tables_conf = $$self{ 'db_fields' };

    # Throw on non-existent table
    while( my ($table => $fields) = each %$tables_conf ) {
        croak(
            "Non-existent table `$$self{ 'name' }`.`$table` is configured"
        ) unless defined $$tables{$table};
    }

    # Merge
    $tables = { %$tables, %$tables_conf };

    # TODO: delete this
    # Delete the tables noted as 1 ( for skipping ) in config
    # my @tables_names = keys %$tables;
    # foreach (@tables_names){ if( $$tables{$_} eq 1 ) { delete $$tables{$_} } }

    return $tables;
}

# Object method
# Returns tables that can be backed up
# Takes     :   n/a
# Depends   :   on 'name', 'endvance' attributes
# Returns   :   HashRef of tables and empty HashRefs
sub tables_all {
    my $self = shift;
    my $name = $$self{ 'name' };
    my $sql = "show tables from `$name`";
    my $dbh = $$self{ 'endvance' }{ 'dbh' };
    my $tables_raw = $dbh->selectall_hashref( $sql => "Tables_in_$name" );
    my $tables = {};
    while ( my( $table => $hash ) = each %$tables_raw ) {
        $$tables{ $table } = {};
    }
    return $tables;
}

1;
