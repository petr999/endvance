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

use FindBin;
use Test::More;
use Try::Tiny;

use Endvance;
use Endvance::Base;

my $conf = realpath( $FindBin::Bin . '/../etc' ) . '/endvance.json';
unshift @ARGV, $conf;

my $endvance;

{

    # Constructor
    try {
        $endvance = Endvance->new;
        ok(       $endvance => 'Constructor: db is connected, chdir '
                . $$endvance{ 'dir' }
                . ' is made ' );
    }
    catch {
        ok( 0 => "Not constructed: $_" );
    }
}

# Dump
if ($endvance) {
    my $name = ( keys %{ $endvance->bases } )[0];
    try {

        # Not a ::Base object but used instead
        my $dump_hash = bless {
            'endvance'  => $endvance,
            'name'      => $name,
            'db_fields' => $$endvance{ 'conf' }{ 'bases' }{ $name },
        } => 'Endvance::Base';

        # Opening handles
        my $dump_fh = Endvance::Base::open_dump($dump_hash);
        my $len     = 0;
        while (<$dump_fh>) {
            unless ($len) { $len = length $_ }
        }
        close $dump_fh;
        ok( $len     => "Database $name was dumped" );
        ok( $dump_fh => 'Sql dump handle opened for reading successfully' );
        my $bckp_fh = Endvance::Base::open_file($dump_hash);
        ok( $bckp_fh => 'Backup handle opened for writing successfully' );

        # Passing through
        $dump_fh = Endvance::Base::open_dump($dump_hash);
        Endvance::Base::passthru( $dump_hash, $dump_fh => $bckp_fh );
    }
    catch {
        ok( 0 => "Not dumped db $name: $_" );
    }
}

done_testing;
