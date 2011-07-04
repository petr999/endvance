#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

BEGIN {
    use File::Basename qw/dirname/;
    use Cwd qw/realpath/;
    use lib realpath( dirname(__FILE__) . '/../lib' );
}

use Test::More;
use Try::Tiny;

unless( @ARGV > 0 ) {
    unshift @ARGV, realpath( dirname(__FILE__).'/../etc' ).'/endvance.json';
}

{

    try {
        use_ok( 'Endvance' );

        # Constructor
        my $endvance = Endvance->new;
        ok(       $endvance => 'Constructor: db is connected, chdir '
                . $$endvance{ 'dir' }
                . ' is made ' );
    }
    catch {
        ok( 0 => "Not constructed: $_" );
    }
}

done_testing;
