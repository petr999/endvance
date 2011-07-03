package Endvance::Table;

use strict;
use warnings;
use autodie;

# Static method
# Constructor
# Takes: name, database handle
# Returns: table object
sub new {
    my ( $class, $name, $dbh ) = @_;
    my $columns_arr = $dbh->selectall_arrayref("show columns from `$name`");
    my $columns     = {};
    for ( my $i = 0; $i < @$columns_arr; $i++ ) {
        $column = $$columns_arr[$i];
        $$columns{ $column } = $i;
    }
    bless {
        'name'    => $name,
        'columns' => $columns,
    }, $class;
}

1;
