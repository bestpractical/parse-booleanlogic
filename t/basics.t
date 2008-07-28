
use strict;
use warnings;

use Test::More tests => 14;
use Test::Deep;

use_ok 'Parse::BooleanLogic';


my $parser = new Parse::BooleanLogic;

sub parse_cmp($$) {
    my ($string, $struct) = @_;
    cmp_deeply $parser->as_array($string), $struct, $string;
}

parse_cmp
    '',
    [],
;

parse_cmp
    'x = 10',
    [{ operand => 'x = 10' }],
;

parse_cmp
    '(x = 10)',
    [[{ operand => 'x = 10' }]],
;

parse_cmp
    '(x = 10) OR y = "Y"',
    [
        [{ operand => 'x = 10' }],
        'OR',
        { operand => 'y = "Y"' }
    ],
;

parse_cmp
    'just a string',
    [{ operand => 'just a string' }],
;

parse_cmp
    '"quoted string"',
    [{ operand => '"quoted string"' }],
;

parse_cmp
    '"quoted string (with parens)"',
    [{ operand => '"quoted string (with parens)"' }],
;

parse_cmp
    'string "quoted" in the middle',
    [{ operand => 'string "quoted" in the middle' }],
;

parse_cmp
    'string OR string',
    [{ operand => 'string' }, 'OR', { operand => 'string' }],
;

parse_cmp
    '"OR" OR string',
    [{ operand => '"OR"' }, 'OR', { operand => 'string' }],
;

parse_cmp
    "recORd = 3",
    [{ operand => "recORd = 3" }],
;

parse_cmp
    "op ORheading = 3",
    [{ operand => "op ORheading = 3" }],
;

parse_cmp
    "operAND",
    [{ operand => "operAND" }],
;
