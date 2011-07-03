package Endvance::Base;

use strict;
use warnings;
use autodie;

use FindBin;
use Cwd qw/realpath/;

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
        'indexes_cache' => {},
    }, $class;
    return $self;
}

# Object method
# Backs up a base into a file
# Takes     :   n/a
# Returns   :   operation result
sub backup {
    my $self    = shift;
    my $fh      = $self->open_file;
    my $dump_fh = $self->open_dump;
    $self->passthru( $dump_fh => $fh );
}

# Object method
# Writes line by line from read handle to write handle
# Takes     :   read and write handles
# Returns   :   n/a
sub passthru {
    my ( $self, $read => $write ) = @_;
    my $db_fields = $$self{ 'db_fields' };
    my $parser    = $$self{ 'endvance' }{ 'parser' };
    while ( my $str = <$read> ) {
        chomp $str;
        my $parsed = $parser->parse($str);
        if ( ( keys(%$db_fields) > 0 ) and defined $parsed ) {
            my ( $insert => $table, $keys => $values ) = @$parsed;
            if ( defined $$db_fields{ $table } ) {

                # If configured hash
                if ( ref $$db_fields{ $table } ) {
                    my $columns_to_skip = $$db_fields{ $table };

                    $self->skip_columns(
                        $table => $columns_to_skip,
                        $keys  => $values,
                    );

                    # Changes the $str string
                    $str = implode_insert(
                        $insert => $table,
                        $keys   => $values,
                    );
                }
                else {next}    # skip the whole insert
            }
        }

        # say STDOUT $str;
        say $write $str;
    }
    close $read;
    close $write;
}

# Object method
# Opens file to dump sql out to
# Takes     :   n/a
# Depends   :   on 'name' attribute and 'edvance's 'config'ured 'dir'
# Throws    :   if file can not be opened
# Returns   :   file handle
sub open_file {
    my $self = shift;
    my $dir  = $$self{ 'endvance' }{ 'dir' };
    my $name = $$self{ 'name' };
    my $fn   = "$dir/$name.sql";
    open my $fh, '>' => $fn;    # with 'autodie' pragma
    return $fh;
}

# Object method
# Opens dump command to read sql
# Takes     :   n/a
# Depends   :   on 'edvance's 'config'ured 'dump' and 'db'
# Throws    :   if command can not be executed
# Returns   :   file handle to read sql dump from
sub open_dump {
    my $self = shift;
    my @cmd  = ( @{ $$self{ 'endvance' }{ 'conf' }{ 'config' }{ 'dump' } } );
    my $db_conf = $$self{ 'endvance' }{ 'conf' }{ 'config' }{ 'db' };
    if ( defined $$db_conf{ 'user' } ) {
        foreach (@cmd) {s/^%u$/$$db_conf{ 'user' }/g}
    }
    if ( defined $$db_conf{ 'pass' } ) {
        foreach (@cmd) {s/^(-p)?%p$/$1$$db_conf{ 'pass' }/g}
    }
    if ( defined $$db_conf{ 'host' } ) {
        splice @cmd, 1, 0, '-h' => $$db_conf{ 'host' };
    }
    elsif ( defined $$db_conf{ 'socket' } ) {
        splice @cmd, 1, 0, '-S' => $$db_conf{ 'socket' };
    }
    else {
        croak("No host or socket configured for database connection");
    }
    my $name = $$self{ 'name' };
    push @cmd, $name;
    open my $fh, '-|' => @cmd;
    return $fh;
}

# Object method
# Changes values and optionally keys according to the columns to be skipped
# Takes     :   HashRefs: of columns to skip, of values and of keys of the sql
# Changes   :   values and keys arguments, if any
# Returns   :   n/a
sub skip_columns {
    my $self = shift;
    my ( $table => $columns_to_skip, $keys => $values ) = @_;
    my $indexes = $self->indexes_to_skip( $table => $columns_to_skip, $keys );
    if ( @$keys > 0 ) {
        foreach my $i (@$indexes) {
            splice @$keys,   $i => 1;
            splice @$values, $i => 1;
        }
    }
    else {
        foreach my $i (@$indexes) {
            $$values[$i] = 'null';    # timestamps to be accepted without keys
        }
    }
}

# Object method
# Finds indexes of table's columns to skip from keys and values arrays
# Seeks cache first, then database
# Takes     :   Str table name, HashRef columns to skip, perhaps empty
#               ArrayRef keys from the insert sql statement
# Depends   :   on 'indexes_cache' attribute
# Returns   :   ArrayRef reverse sorted list of keys and values arrays indexes
sub indexes_to_skip {
    my $self = shift;
    my ( $table => $cols, $keys ) = @_;
    my $cache = $$self{ 'indexes_cache' };
    my $idx   = [];
    if ( defined $$cache{ $table } ) {
        $idx = $$cache{ $table };
    }
    else {    # Not cached
        if ( @$keys == 0 ) {    # No columns in insert statement
            $keys = $self->db_get_columns($table);
        }
        for ( my $i = 0; $i < @$keys; $i++ ) {
            my $key = $$keys[$i];

            # If such a column is configured than push its index into list
            if ( defined $$cols{ $key } and $$cols{ $key } ) {
                push @$idx, $i;
            }
        }

        # Reverse sort for splicing from the end
        @$idx = sort { $b <=> $a } @$idx;
        $$cache{ $table } = $idx;
    }
    return $idx;
}

# Object method
# Gets columns list from database for the specified table
# Takes     :   Str table name
# Throws    :   if nop columns or no table in database
# Returns   :   ArrayRef list of columns
sub db_get_columns {
    my ( $self => $table ) = @_;
    my $dbh     = $$self{ 'endvance' }{ 'dbh' };
    my $db_name = $$self{ 'name' };
    my $cols =
        $dbh->selectall_arrayref("show columns from `$db_name`.`$table`");
    foreach (@$cols) { $_ = shift @$_ }
    croak("No columns for table: $table")
        unless defined($cols)
            and @$cols > 0;
    return $cols;
}

# Function
# Joins the sql insert statement back from 4 arguments
# Takes     :   Str table name,
#               HashRef columns to skip as keys and values are 1,
#               ArrayRef optional columns names to skip from and values are 1
#               ArrayRef values to skip from
# Depends   :   on the attributes: the 'table's layout shown from 'endvance's
#               'db' in the case if columns names are empty
# Returns   :   array of ArrayRef oprionally  keys and the ArrayRef values to
#               join into sql
sub implode_insert {
    my ( $insert => $table, $keys => $values ) = @_;
    my $sql = "$insert`$table` ";
    if ( @$keys > 0 ) { $sql .= "(`" . join( "`, `", @$keys ) . "`) " }
    $sql .= "VALUES (" . join( ",", @$values ) . ");";
    return $sql;
}

1;
