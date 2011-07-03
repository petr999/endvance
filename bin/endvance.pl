#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

BEGIN {
    use File::Basename qw/dirname/;
    use Cwd qw/realpath/;
    use lib realpath( dirname(__FILE__) . '/../lib' );
}

use Endvance;

Endvance::perform();
