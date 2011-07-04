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

use Endvance;

my $conf = realpath( dirname(__FILE__) . '/../etc' ) . '/endvance.sample.json';
{
    try {
        my $hash     = Endvance->configure($conf);
        my $ref_hash = ref $hash;
        croak("Undefined ref") unless $ref_hash;
        is( 'HASH' => $ref_hash, 'Reading config into hash' );
    }
    catch {
        ok( 0 => "Not parsed $conf: $_" );
    }
}

done_testing;
