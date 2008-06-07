=head1 NAME

Parse::BooleanLogic - parser of boolean expressions

=head1 SYNOPSIS
    
    my $parser = new Parse::BooleanLogic;
    my $tree = $parser->as_array( string => 'x = 10' );
    $tree = $parser->as_array( string => 'x = 10 OR (x > 20 AND x < 30)' );

    $parser->parse(
        string   => 'x = 10 OR (x > 20 AND x < 30)',
        callback => {
            open_paren   => sub { ... },
            operator     => sub { ... },
            operand      => sub { ... },
            close_paren  => sub { ... },
            error        => sub { ... },
        },
    );

=head1 DESCRIPTION

This module is quite fast parser for boolean expressions. Original it's been writen for
Request Tracker for parsing SQL like expressions and it's still capable to, but
it can be used to parse other boolean logic sentences with OPERANDs joined using
binary OPERATORs and grouped and nested using parentheses (OPEN_PAREN and CLOSE_PAREN).

=cut



use strict;
use warnings;

package Parse::BooleanLogic;

our $VERSION = '0.03';

use constant OPERAND     => 1;
use constant OPERATOR    => 2;
use constant OPEN_PAREN  => 4;
use constant CLOSE_PAREN => 8;
my @tokens = qw[OPERAND OPERATOR OPEN_PAREN CLOSE_PAREN];

use Regexp::Common qw(delimited);
my $re_operator    = qr[(?i:AND|OR)];
my $re_open_paren  = qr[\(];
my $re_close_paren = qr[\)];

my $re_tokens      = qr{(?:$re_operator|$re_open_paren|$re_close_paren)};
my $re_delim       = qr{$RE{delimited}{-delim=>qq{\'\"}}};
my $re_operand     = qr{(?!\s)(?:$re_delim|(?!$re_tokens|["']).+?(?=$re_tokens|["']|\Z))+};

=head1 METHODS

=head2 new

Very simple constructor, returns a new object. Now takes no options and most
methods can be executed as class methods too, however there are plans to
change it and using this lightweight constructor is recommended.

=cut

sub new {
    my $proto = shift;
    return bless {@_}, ref($proto) || $proto;
}


=head2 Parsing expressions

=head3 as_array $string [ %options ]

Takes a string and parses it into perl structure, where parentheses represented using
array references, operands are hash references with one key/value pair: operand,
when binary operators are simple scalars. So string C<x = 10 OR (x > 20 AND x < 30)>
is parsed into the following structure:

    [
        { operand => 'x = 10' },
        'OR',
        [
            { operand => 'x > 20' },
            'AND',
            { operand => 'x < 30' },
        ]
    ]

Aditional options:

=over 4

=item operand_cb - custom operands handler

=item error_cb - custom errors handler

=back

=cut

{ # static variables

my ($tree, $node, @pnodes);
my %callback;
$callback{'open_paren'} = sub {
    push @pnodes, $node;
    push @{ $pnodes[-1] }, $node = []
};
$callback{'close_paren'}     = sub { $node = pop @pnodes };
$callback{'operator'} = sub { push @$node, $_[0] };
$callback{'operand'} = sub { push @$node, { operand => $_[0] } };

sub as_array {
    my $self = shift;
    my $string = shift;
    my %arg = (@_);

    $node = $tree = [];
    @pnodes = ();

    unless ( $arg{'operand_cb'} || $arg{'error_cb'} ) {
        $self->parse(string => $string, callback => \%callback);
        return $tree;
    }

    my %cb = %callback;
    if ( $arg{'operand_cb'} ) {
        $cb{'operand'} = sub { push @$node, $arg{'operand_cb'}->( $_[0] ) };
    }
    $cb{'error'} = $arg{'error_cb'} if $arg{'error_cb'};
    $self->parse(string => $string, callback => \%cb);
    return $tree;
} }

=head3 parse

Takes named arguments: string and callback. Where the first one is scalar with
expression, the latter is a reference to hash with callbacks: open_paren, operator
operand, close_paren and error. Callback for errors is optional and parser dies if
it's omitted. Each callback is called when parser finds corresponding element in the
string. In all cases the current match is passed as argument into the callback.

Here is simple example based on L</as_array> method:

    # result tree and the current group
    my ($tree, $node);
    $tree = $node = [];

    # stack with nested groups, outer most in the bottom, inner on the top
    my @pnodes = ();

    my %callback;
    # on open_paren put the current group on top of the stack,
    # create new empty group and at the same time put it into
    # the end of previous one
    $callback{'open_paren'} = sub {
        push @pnodes, $node;
        push @{ $pnodes[-1] }, $node = []
    };

    # on close_paren just switch to previous group by taking it
    # from the top of the stack
    $callback{'close_paren'} = sub { $node = pop @pnodes };

    # push binary operators as is and operands as hash references
    $callback{'operator'} = sub { push @$node, $_[0] };
    $callback{'operand'}  = sub { push @$node, { operand => $_[0] } };

    # run parser
    $parser->parse( string => $string, callback => \%callback );

    return $tree;

Using this method you can build other representations of an expression.

=cut

sub parse {
    my $self = shift;
    my %args = (
        string => '',
        callback => {},
        @_
    );
    my ($string, $cb) = @args{qw(string callback)};
    $string = '' unless defined $string;

    my $want = OPERAND | OPEN_PAREN;
    my $last = 0;

    my $depth = 0;

    while ( $string =~ /(
                        $re_operator
                        |$re_open_paren
                        |$re_close_paren
                        |$re_operand
                       )/iogx )
    {
        my $match = $1;
        next if $match =~ /^\s*$/;

        # Highest priority is last
        my $current = 0;
        $current = OPERAND     if ($want & OPERAND)     && $match =~ /^$re_operand$/io;
        $current = OPERATOR    if ($want & OPERATOR)    && $match =~ /^$re_operator$/io;
        $current = OPEN_PAREN  if ($want & OPEN_PAREN)  && $match =~ /^$re_open_paren$/io;
        $current = CLOSE_PAREN if ($want & CLOSE_PAREN) && $match =~ /^$re_close_paren$/io;

        unless ($current && $want & $current) {
            my $tmp = substr($string, 0, pos($string)- length($match));
            $tmp .= '>'. $match .'<--here'. substr($string, pos($string));
            my $msg = "Wrong expression, expecting a ". $self->bitmask_to_string($want) ." in '$tmp'";
            $cb->{'error'}? $cb->{'error'}->($msg): die $msg;
            return;
        }

        # State Machine:
        if ( $current & OPEN_PAREN ) {
            $cb->{'open_paren'}->( $match );
            $depth++;
            $want = OPERAND | OPEN_PAREN;
        }
        elsif ( $current & CLOSE_PAREN ) {
            $cb->{'close_paren'}->( $match );
            $depth--;
            $want = OPERATOR;
            $want |= CLOSE_PAREN if $depth;
        }
        elsif ( $current & OPERATOR ) {
            $cb->{'operator'}->( $match );
            $want = OPERAND | OPEN_PAREN;
        }
        elsif ( $current & OPERAND ) {
            $match =~ s/\s+$//;
            $cb->{'operand'}->( $match );
            $want = OPERATOR;
            $want |= CLOSE_PAREN if $depth;
        }

        $last = $current;
    }

    unless ( !$last || $last & (CLOSE_PAREN | OPERAND) ) {
        my $msg = "Incomplete query, last element ("
            . $self->bitmask_to_string($last)
            . ") is not CLOSE_PAREN or OPERAND in '$string'";
        $cb->{'error'}? $cb->{'error'}->($msg): die $msg;
        return;
    }

    if ( $depth ) {
        my $msg = "Incomplete query, $depth paren(s) isn't closed in '$string'";
        $cb->{'error'}? $cb->{'error'}->($msg): die $msg;
        return;
    }
}

sub bitmask_to_string {
    my $self = shift;
    my $mask = shift;

    my @res;
    for( my $i = 0; $i < @tokens; $i++ ) {
        next unless $mask & (1<<$i);
        push @res, $tokens[$i];
    }

    my $tmp = join ', ', splice @res, 0, -1;
    unshift @res, $tmp if $tmp;
    return join ' or ', @res;
}

=head2 Tree modifications

Several functions taking a tree of boolean expressions as returned by
as_array method and changing it using a callback.

=head3 filter $tree $callback

Returns sub-tree where only operands left for which the callback returned
true value.

=cut

sub filter {
    my ($self, $tree, $cb, $inner) = @_;

    my $skip_next = 0;

    my @res;
    foreach my $entry ( @$tree ) {
        next if $skip_next-- > 0;

        if ( ref $entry eq 'ARRAY' ) {
            my $tmp = $self->filter( $entry, $cb, 1 );
            if ( !$tmp || (ref $tmp eq 'ARRAY' && !@$tmp) ) {
                pop @res;
                $skip_next = 1 unless @res;
            } else {
                push @res, $tmp;
            }
        } elsif ( ref $entry eq 'HASH' ) {
            if ( $cb->( $entry ) ) {
                push @res, $entry;
            } else {
                pop @res;
                $skip_next = 1 unless @res;
            }
        } else {
            push @res, $entry;
        }
    }
    return $res[0] if @res == 1 && ($inner || ref $res[0] eq 'ARRAY');
    return \@res;
}

=head3 solve $tree $callback

Returns sub-tree where only operands left for which the callback returned
true value.

=cut

sub solve {
    my ($self, $tree, $cb) = @_;

    my ($res, $ea, $skip_next) = (0, 'OR', 0);
    foreach my $entry ( @$tree ) {
        next if $skip_next-- > 0;
        unless ( ref $entry ) {
            $ea = $entry;
            $skip_next++ if ($res && $ea eq 'OR') || (!$res && $ea eq 'AND');
            next;
        }

        my $cur;
        if ( ref $entry eq 'ARRAY' ) {
            $cur = $self->solve( $entry, $cb, 1 );
        } else {
            $cur = $cb->( $entry );
        }
        if ( $ea eq 'OR' ) {
            $res ||= $cur;
        } else {
            $res &&= $cur;
        }
    }
    return $res? 1 : 0;
}

1;

=head1 AUTHORS

Ruslan Zakirov E<lt>ruz@cpan.orgE<gt>, Robert Spier E<lt>rspier@pobox.comE<gt>

=head1 COPYRIGHT

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
