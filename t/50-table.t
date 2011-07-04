#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

BEGIN {
    use File::Basename qw/dirname/;
    use Cwd qw/realpath/;
    use lib realpath( dirname(__FILE__) . '/../lib' );
}

use Carp;

use Test::More;
use Try::Tiny;
use Const::Fast;

const my $BASE_TO_DUMP => 'test04';
const my $TABLE_TO_DUMP => 'test01';

unless( @ARGV > 0 ) {
    unshift @ARGV, realpath( dirname(__FILE__).'/../etc' ).'/endvance.json';
}

{
    try {
        use_ok( 'Endvance' );
        my $endvance = Endvance->new;

        my $bases = $endvance->bases;
        my($base_name => $base_hash) =
            ($BASE_TO_DUMP => $$bases{$BASE_TO_DUMP});

        use_ok( 'Endvance::Base' );
        my $base = Endvance::Base->new(
            $endvance, $base_name => $base_hash,
        );
        my $write_fh = $base->open_file;
        my $tables   = $base->tables;

        my($table_name => $table_hash) = (
            $TABLE_TO_DUMP => $$tables{$TABLE_TO_DUMP},
        );
        use_ok( 'Endvance::Table' );
        my $table = Endvance::Table->new(
            $base => $write_fh, $table_name => $table_hash
        );
        ok( $table => "Table constructor" );

        # Dump
        my $read_fh = $table->open_dump;
        ok( $read_fh => "Opening dump handle" );
        my $len = 0;
        while (<$read_fh>) {
            unless ($len) { $len = length $_ }
        }
        close $read_fh;
        ok( $len     => "Table $table_name dump was read" );

        my $rv = $table->backup;
        ok( $rv => "Backup was made" );
    }
    catch {
        ok( 0 => "Not dumped table $BASE_TO_DUMP.$TABLE_TO_DUMP: $_" );
    }
}

done_testing;
