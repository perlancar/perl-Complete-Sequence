package Complete::Sequence;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Complete::Common qw(:all);

use Exporter qw(import);
our @EXPORT_OK = qw(
                       complete_sequence
               );

our %SPEC;

sub _get_strings_from_item {
    my ($item) = @_;

    my @array;
    my $ref = ref $item;
    if (!$ref) {
        push @array, $item;
    } elsif ($ref eq 'ARRAY') {
        push @array, @$item;
    } elsif ($ref eq 'CODE') {
        push @array, _get_strings_from_item( $item->() );
    } elsif ($ref eq 'HASH') {
        if (defined $item->{alternative}) {
            push @array, map { _get_strings_from_item($_) }
                @{ $item->{alternative} };
        } elsif (defined $item->{sequence} && @{ $item->{sequence} }) {
            my @set = map { [_get_strings_from_item($_)] }
                @{ $item->{sequence} };
            #use DD; dd \@set;
            # sigh, this module is quite fussy. it won't accept
            if (@set > 1) {
                require Set::CrossProduct;
                my $scp = Set::CrossProduct->new(\@set);
                while (my $tuple = $scp->get) {
                    push @array, join("", @$tuple);
                }
            } elsif (@set == 1) {
                push @array, @{ $set[0] };
            }
        } else {
            die "Need alternative or sequence";
        }
    } else {
        die "Invalid item: $item";
    }
    @array;
}

$SPEC{complete_sequence} = {
    v => 1.1,
    summary => 'Complete string from a sequence of choices',
    description => <<'_',

Sometime you want to complete a string where its parts (sequence items) are
formed from various pieces. For example, suppose your program "delete-user-data"
accepts an argument that is in the form of:

    USERNAME
    UID "(" "current" ")"
    UID "(" "historical" ")"

    "EVERYONE"

Supposed existing users include `budi`, `ujang`, and `wati` with UID 101, 102,
103.

This can be written as:

    [
        {
            alternative => [
                [qw/budi ujang wati/],
                {sequence => [
                    [qw/101 102 103/],
                    ["(current)", "(historical)"],
                ]},
                "EVERYONE",
            ],
        }
    ]

When word is empty (`''`), the offered completion is:

    budi
    ujang
    wati

    101
    102
    103

    EVERYONE

When word is `101`, the offered completion is:

    101
    101(current)
    101(historical)

When word is `101(h`, the offered completion is:

    101(historical)

_
    args => {
        %arg_word,
        sequence => {
            schema => 'array*',
            req => 1,
            description => <<'_',

A sequence structure is an array of items. An item can be:

* a scalar/string (a single string to choose from)

* an array of strings (multiple strings to choose from)

* a coderef (will be called to extract an item)

* a hash (another sequence or alternative of items)

If you want to specify another sub-sequence of items:

    {sequence => [ ... ]}   # put items in here

If you want to specify an alternative of sub-sequences or sub-alternative:

    {alternative => [ ... ]}    # put items in here

_
        },
    },
    result_naked => 1,
    result => {
        schema => 'array',
    },
};
sub complete_sequence {
    require Complete::Util;

    my %args = @_;

    my $word = $args{word} // "";
    my $sequence = $args{sequence};

    my $orig_word = $word;
    my @prefixes_from_completed_items;

    for my $item (@$sequence) {
        my @array = _get_strings_from_item($item);
        my $res = Complete::Util::complete_array_elem(
            word => $word,
            array => \@array,
        );
        if ($res && @$res == 1) {
            # the word can be completed directly (unambiguously) with this item.
            # move on to get more words from the next item.
            push @prefixes_from_completed_items, $res->[0];
            substr($word, 0, length $res->[0]) = "";
            next;
        } elsif ($res && @$res > 1) {
            # the word can be completed with several choices from this item.
            # present the choices as the final answer.
            return [map { join("", @prefixes_from_completed_items, $_) } @$res];
        } else {
            # the word cannot be completed with this item. it can be that the
            # word already contains this item and the next.
            my $num_matches = 0;
            my $matching_str;
            for my $str (@array) {
                # XXX perhaps we want to be case-insensitive?
                if (index($word, $str) == 0) {
                    $num_matches++;
                    $matching_str = $str;
                }
            }
            if ($num_matches == 1) {
                substr($word, 0, length($matching_str)) = "";
                push @prefixes_from_completed_items, $matching_str;
                next;
            }

            # nope, this word simply doesn't match
            goto RETURN;
        }
    }

  RETURN:
    if (@prefixes_from_completed_items) {
        return [join("", @prefixes_from_completed_items)];
    } else {
        return [];
    }

}

1;
# ABSTRACT:

=head1 SEE ALSO

L<Complete::Path>. Conceptually, L</complete_sequence> is similar to
C<complete_path> from L<Complete::Path>. Except unlike a path, a sequence does
not (necessarily) have path separator.

L<Complete>
