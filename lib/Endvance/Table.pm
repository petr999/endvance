package Endvance::Table;

use strict;
use warnings;
use autodie;
use feature ':5.14';

use Carp;

# Static method
# Constructor
# Takes: name, database handle
# Returns: table object
sub new {
    my ($class, $base => $write_fh, $name => $hash) = @_;

    my $th_ref = ref $hash;
    croak( "No table hash for $name" )
        unless ( $hash eq 1 )
            or ( defined( $th_ref ) and 'HASH' eq $th_ref );

    my $self = bless {
        'name'    => $name, 'base' => $base, 'write_fh' => $write_fh,
        'columns' => $hash, 'indexes_cache' => {},
    }, $class;
    return $self;
}

# Object method
# Opens dump command to read sql
# Takes     :   n/a
# Depends   :   on 'edvance's 'config'ured 'dump' and 'db'
#               on 'autodie' pragma
# Throws    :   if command can not be executed
# Returns   :   file handle to read sql dump from
sub open_dump {
    my $self = shift;

    # Get config
    my $columns  = $$self{ 'columns' };
    my $base     = $$self{ 'base' };
    my $endvance = $$base{ 'endvance' };
    my $config   = $$endvance{ 'conf' }{ 'config' };
    my @cmd      = ( @{ $$config{ 'dump' } } );
    my $db_conf  =      $$config{ 'db' };

    # Set arguments for dump command
    # Connection
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

    # Skip data ( optional )
    my $is_col_hashref = ( 'HASH' eq ref $columns );
    if( not( $is_col_hashref ) and ( $columns eq 1 ) ) {
        splice @cmd, 1, 0, '-d';  # -d for no data tables
    }

    my $db_name = $$base{ 'name' }; push @cmd, $db_name;
    my $name    = $$self{ 'name' }; push @cmd, $name;
    open my $fh, '-|' => @cmd;
    return $fh;
}

# Object method
# Changes values and optionally keys according to the columns to be skipped
# Takes     :   ArrayRef of 4-elements parsed sql insert statement
# Changes   :   HashRefs values and keys inside argument
# Returns   :   n/a
sub skip_columns {
    my ($self => $parsed) = @_;
    my ( $insert => $table, $keys => $values ) = @$parsed;
    my $columns = $$self{ 'columns' };
    my $indexes = $self->indexes_to_skip( $parsed );
    if ( @$keys > 0 ) {

        # sql statement with keys
        foreach my $index (@$indexes) {

            # If column is configured for :{"value":"to replace"}
            if( 'HASH' eq ref $index ) {
                my ($i =>$value)
                    = map{ $$index{ $_ } } qw/index value/;
                splice @$values, $i => 1,  $value;
            }

            # If column is configured as :true value
            else {
                splice @$keys,   $index => 1;
                splice @$values, $index => 1;
            }
        }
    }
    else {

        # timestamps to be accepted without values
        foreach my $i (@$indexes) { $$values[$i] = 'null' }
    }
}

# Object method
# Finds indexes of table's columns to skip from keys and values arrays
# Seeks cache first, then database
# Takes     :   ArrayRef 4-elements parsed insert sql statement
# Depends   :   on 'indexes_cache' and 'columns' attributes
# Throws    :   if columns configured are not in sql statement, nor in
#               database
# Returns   :   ArrayRef reverse sorted list of keys and values arrays indexes
#               or of ArrayRefs as index => value to replace
sub indexes_to_skip {
    my ($self => $parsed) = @_;
    my ( $insert => $table, $keys => $values ) = @$parsed;
    my $columns = $$self{ 'columns' };
    my $cache   = $$self{ 'indexes_cache' };
    my $idx   = [];
    if ( defined $$cache{ $table } ) { $idx = $$cache{ $table } }
    else {    # Not cached

        # Columnless insert statement - take columns from database
        if ( @$keys == 0 ) { $keys = $self->db_get_columns }

        # Not-existent keys in a config
        foreach my $col ( keys %$columns ) {
            croak( "Wrong column configured: "
                ."`$$self{ 'base' }{ 'name' }`.`$$self{ 'name' }`.`$col`"
            ) unless grep { $col eq $_ } @$keys
        }

        # Calculate indexes
        for ( my $i = 0; $i < @$keys; $i++ ) {
            my $key = $$keys[$i];

            # If such a column is configured than push its index into list
            if ( defined $$columns{$key} ) {
                if ( 'HASH' eq ref $$columns{$key} ) {
                    if( defined $$columns{$key}{ 'value' } ) {
                        push @$idx, { 'value' => $$columns{$key}{ 'value' },
                                      'index' => $i,
                                    };
                    }
                }
                elsif ( $$columns{$key} ) { push @$idx, $i }
            }
        }

        # Reverse sort for splicing from the end
        @$idx = sort { ( ref( $b ) ? $$b{ 'index' } : $b )
                   <=> ( ref( $a ) ? $$a{ 'index' } : $a ) } @$idx;

        # Write to cache
        $$cache{ $table } = $idx;
    }
    return $idx;
}

# Object method
# Gets columns list from database for the specified table
# Takes     :   n/a
# Throws    :   if no columns or no table in database
# Returns   :   ArrayRef list of columns
sub db_get_columns {
    my $self = shift;
    my $base    = $$self{ 'base' };
    my $dbh     = $$base{ 'endvance' }{ 'dbh' };
    my $db_name = $$base{ 'name' };
    my $name    = $$self{ 'name' };
    my $cols =
        $dbh->selectall_arrayref("show columns from `$db_name`.`$name`");
    foreach (@$cols) { $_ = shift @$_ }
    croak("No columns for table: $name")
        unless defined($cols) and @$cols > 0;
    return $cols;
}

# Function
# Joins the sql insert statement back from 4 arguments
# Takes     :   ArrayRef 4-element parsed insert sql statement
# Depends   :   on the attributes: the 'table's layout shown from 'endvance's
#               'db' in the case if columns names are empty
# Returns   :   array of ArrayRef oprionally  keys and the ArrayRef values to
#               join into sql
sub implode_insert {
    my $parsed = shift;
    my ( $insert => $table, $keys => $values ) = @$parsed;
    my $sql = "$insert`$table` ";
    if ( @$keys > 0 ) { $sql .= "(`" . join( "`, `", @$keys ) . "`) " }
    $sql .= "VALUES (" . join( ",", @$values ) . ");";
    return $sql;
}

# Object method
# Writes line by line from read handle to write handle
# Takes     :   read handle
# Depends   :   on 'autodie' pragma
# Throws    :   on i/o error or wrong config for table
# Returns   :   n/a
sub passthru {
    my ($self => $read_fh) = @_;
    my($columns => $write_fh)
        = map{ $$self{$_} } qw/columns write_fh/;
    my $col_ref = ref $columns;
    my $is_col_hashref = ( 'HASH' eq $col_ref );
    my $parser    = $$self{ 'base' }{ 'endvance' }{ 'parser' };

    # If columns configured undef or empty hash or 0
    if ( not( defined $columns ) or ( $columns eq 0 )
            or ( $is_col_hashref and ( keys( %$columns ) == 0 ) )
        ) {

        # No parsing needed
        while ( my $str = <$read_fh> ) { print $write_fh $str }
    }
    elsif ( $columns eq 1 ) {

        # If columns configured as 1
        while ( my $str = <$read_fh> ) {
            my $parsed = $parser->parse($str);
            unless( $parsed ) { print $write_fh $str }
        }
    }
    elsif ( $is_col_hashref and ( keys( %$columns ) > 0 ) ) {

        # If columns configured as not-empty hash
        while (my $str = <$read_fh>) {
            chomp $str;
            my $parsed = $parser->parse($str);

            # Parser returns '' if not an insert sql statement
            if ( $parsed ) {

                # Skip columns
                $str = $self->skip_from_parsed( $parsed );

            }

            # say STDOUT $str;
            say $write_fh $str;
        }
    }
    else {
        croak( "Columns: $columns: not supported yet" );
    }
}

# Object method
# Makes new sql insert statement from the parsed array
# Takes     :   ArrayRef 4-elements parsed insert sql statement
# Returns   :   Str sql statement with columns skipped if it is insert
sub skip_from_parsed {
    my ($self => $parsed) = @_;
    my ( $insert => $table, $keys => $values ) = @$parsed;
    my $columns = $$self{ 'columns' };

    # Change ArrayRefs $values and optionally $keys
    $self->skip_columns( $parsed );

    # Glue insert back
    my $str = implode_insert( $parsed );
    return $str;
}

# Object method
# Performs table's backup
# Takes     :   n/a
# Depends   :   on all attributes
# Returns   :   n/a
sub backup {
    my $self = shift;
    my $read_fh = $self->open_dump;
    $self->passthru( $read_fh );
    close $read_fh;
}

1;
