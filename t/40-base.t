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

unshift @ARGV, realpath( dirname(__FILE__).'/../etc' ).'/endvance.json';

{
    try {
        use_ok( 'Endvance' );
        my $endvance = Endvance->new;

        my $bases = $endvance->bases;
        ok( $bases => 'Bases are present on Endvance' );

        my($base_name => $base_hash) =
            ($BASE_TO_DUMP => $$bases{$BASE_TO_DUMP});

        use_ok( 'Endvance::Base' );
        my $base = Endvance::Base->new(
                $endvance, $base_name => $base_hash,
        );
        ok( $base => "Base $base_name constructor" );

        my $write_fh = $base->open_file;
        ok( $write_fh => "Opening file for base: $$base{ 'name'}" );
        close $write_fh;
    }
    catch {
        ok( 0 => "Not opened file for db $BASE_TO_DUMP: $_" );
    }
}

done_testing;
