package Endvance::Parser;

use strict;
use warnings;
use autodie;
use feature ':5.14';

use base qw/Parse::RecDescent/;

use Carp;

use Const::Fast;

# Grammar
# Takes     :   sql insert stratement
# Returns   :   array consisting of 4 elements:
#               Str insert into `
#               Str table
#               ArrayRef of keys, if any: field0 field1 ...
#               ArrayRef of values: value0 'value1' ...
const my $grammar => <<EOT;
parse_str: insert table keys(?) values_keyword values
# ';'
    { \$return = \\\%item }
# parse_str: /.*/
insert: /^\\s*(insert|replace)\\s[^`]*/i
table: key
    { \$return = \$item{ 'key' }[3] }
keys: '(' key(s /,\\s?/) ')'
    { \$return = [ map{\$\$_[3] }
            \@{ \$item{ 'key(s)' } }
        ];
    }
values_keyword: /values/i
values: '(' value(s /,/) ')'
    { \$return = \$item{ 'value(s)' } }

value: /\\d+|null/i | quoted
    { \$return = \$item[1] }
quoted: <skip:''> apostroph val apostroph
    { \$return = join '', \@item[ 2..4 ] }
key: <skip:''> backtick key_unquoted backtick
    { \$return = \\\@item }
apostroph: "'"
backtick: "`"
val: /([^'\\\\]|\\\\[\\w\\d'\\\\])*/
key_unquoted: /([^`\\\\]|\\\\[\\w\\d`\\\\])*/
EOT

# Static method
# Constructor
# Takes     :   n/a
# Depends   :   on $grammar lexical constant
# Throws    :   if $grammar does not provide a parser
# Returns   :   parser object
sub new {
    my $class  = shift;
    my $parser = $class->SUPER::new($grammar);
    croak("Wrong grammar: $grammar") unless defined $parser;
    return $parser;
}

# Object method
# Parses sql insert statement into the 4 elements ArrayRef
# Takes     :   Str or Ref(Str) to parse
# Returns   :   ArrayRefs of insert, table, keys and values rules
sub parse {
    my $self      = shift;
    my $hash      = $self->parse_str(@_);
    my @hash_keys = ( qw/insert table/, 'keys(?)', 'values' );
    my $rv        = undef;
    if ( defined $hash ) {
        foreach (@hash_keys) {
            croak("not defined: $_") unless defined $$hash{ $_ };
        }
        my @arr = map { $$hash{ $_ } } @hash_keys;

        # Columns' names
        if ( @{ $arr[2] } > 0 ) { $arr[2] = shift @{ $arr[2] } }
        $rv = \@arr;
    }
    return $rv;
}

1;
