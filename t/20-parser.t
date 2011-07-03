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
use Const::Fast;
use Try::Tiny;

use Endvance;
use Endvance::Base;

const my $tseq => [
    <<EOT,
INSERT INTO `test` VALUES (1,'abcd');
INSERT INTO `test` VALUES (2,'efgh');
INSERT INTO `test` VALUES (6,'`');
INSERT INTO `test` VALUES (7,'\\'');
INSERT INTO `test` VALUES (8,'\\\\\\'');
INSERT INTO `test` VALUES (9,'\\\\');
INSERT INTO `test` VALUES (10,' \\\\ ');
EOT
    <<EOT,
INSERT INTO `test03` (`id`, `descr`) VALUES (1,'abcd');
INSERT INTO `test03` (`id`, `descr`) VALUES (2,'efgh');
INSERT INTO `test03` (`id`, `descr`) VALUES (3,'ijkl');
INSERT INTO `test03` (`id`, `descr`) VALUES (4,'mnop');
INSERT INTO `test03` (`id`, `descr`) VALUES (5,'qrst');
INSERT INTO `test03` (`id`, `descr`) VALUES (6,'`');
INSERT INTO `test03` (`id`, `descr`) VALUES (7,'\\'');
INSERT INTO `test03` (`id`, `descr`) VALUES (8,'\\\\\\'');
INSERT INTO `test03` (`id`, `descr`) VALUES (9,'\\\\');
INSERT INTO `test03` (`id`, `descr`) VALUES (10,' \\\\ ');
EOT
];

my $parser = Endvance::parser();
for ( my $i = 0; $i < @$tseq; $i++ ) {
    my $seq = $$tseq[$i];
    my $rv  = 0;
    my @arr = split "\n" => $seq;
    for ( my $j = 0; $j < @arr; $j++ ) {
        my $str = $arr[$j];
        try {
            my ( $insert, $table, $keys, $values ) =
                @{ $parser->parse($str) };
            croak("Not parsed: $str") unless defined $insert;
            my $cmp = Endvance::Base::implode_insert(
                $insert => $table,
                $keys   => $values,
            );
            $rv = is(
                $str => $cmp,
                "SQL Parser test "
                    . ( $i + 1 ) . "/"
                    . @$tseq . ": "
                    . ( $j + 1 ) . "/"
                    . @arr
            );
            unless ($rv) { diag("Compared:\n\t$str\n\t$cmp") }
        }
        catch {
            ok( 0 => "Failed to parse: $_" );
        }
    }
}

done_testing;
