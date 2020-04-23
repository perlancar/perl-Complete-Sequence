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

our $COMPLETE_SEQUENCE_TRACE = $ENV{COMPLETE_SEQUENCE_TRACE} // 0;

sub _get_strings_from_item {
    my ($item, $stash) = @_;

    my @strings;
    my $ref = ref $item;
    if (!$ref) {
        push @strings, $item;
    } elsif ($ref eq 'ARRAY') {
        push @strings, @$item;
    } elsif ($ref eq 'CODE') {
        push @strings, _get_strings_from_item($item->($stash), $stash);
    } elsif ($ref eq 'HASH') {
        if (defined $item->{alternative}) {
            push @strings, map { _get_strings_from_item($_, $stash) }
                @{ $item->{alternative} };
        } elsif (defined $item->{sequence} && @{ $item->{sequence} }) {
            my @sets = map { [_get_strings_from_item($_, $stash)] }
                @{ $item->{sequence} };
            #use DD; dd \@sets;

            # sigh, this Set::CrossProduct module is quite fussy. it won't
            # accept a single set
            if (@sets > 1) {
                require Set::CrossProduct;
                my $scp = Set::CrossProduct->new(\@sets);
                while (my $tuple = $scp->get) {
                    push @strings, join("", @$tuple);
                }
            } elsif (@sets == 1) {
                push @strings, @{ $sets[0] };
            }
        } else {
            die "Need alternative or sequence";
        }
    } else {
        die "Invalid item: $item";
    }
    @strings;
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

  Coderef will be called with `$stash` argument which contains various
  information, e.g. the index of the sequence item (`item_index`), the completed
  parts (`completed_item_words`), the current word (`cur_word`), etc.

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

    my $stash = {
        completed_item_words => \@prefixes_from_completed_items,
        cur_word => $word,
        orig_word => $orig_word,
    };

    my $itemidx = -1;
    for my $item (@$sequence) {
        $itemidx++; $stash->{item_index} = $itemidx;
        log_trace("[compseq] Looking at sequence item[$itemidx] : %s", $item) if $COMPLETE_SEQUENCE_TRACE;
        my @array = _get_strings_from_item($item, $stash);
        log_trace("[compseq] Result from sequence item[$itemidx]: %s", \@array) if $COMPLETE_SEQUENCE_TRACE;
        my $res = Complete::Util::complete_array_elem(
            word => $word,
            array => \@array,
        );
        if ($res && @$res == 1) {
            # the word can be completed directly (unambiguously) with this item.
            # move on to get more words from the next item.
            log_trace("[compseq] Word ($word) can be completed unambiguously with this sequence item[$itemidx], moving on to the next sequence item") if $COMPLETE_SEQUENCE_TRACE;
            substr($word, 0, length $res->[0]) = "";
            $stash->{cur_word} = $word;
            push @prefixes_from_completed_items, $res->[0];
            next;
        } elsif ($res && @$res > 1) {
            # the word can be completed with several choices from this item.
            # present the choices as the final answer.
            my $compres = [map { join("", @prefixes_from_completed_items, $_) } @$res];
            log_trace("[compseq] Word ($word) can be completed with several choices from this sequence item[$itemidx], returning final result: %s", $compres) if $COMPLETE_SEQUENCE_TRACE;
            return $compres;
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
                $stash->{cur_word} = $word;
                push @prefixes_from_completed_items, $matching_str;
                log_trace("[compseq] Word ($word) cannot be completed by this sequence item[$itemidx] because part of the word matches previous sequence item(s); completed_parts=%s, word=%s", \@prefixes_from_completed_items, $word) if $COMPLETE_SEQUENCE_TRACE;
                next;
            }

            # nope, this word simply doesn't match
            log_trace("[compseq] Word ($word) cannot be completed by this sequence item[$itemidx], giving up the rest of the sequence items") if $COMPLETE_SEQUENCE_TRACE;
            goto RETURN;
        }
    }

  RETURN:
    my $compres;
    if (@prefixes_from_completed_items) {
        $compres = [join("", @prefixes_from_completed_items)];
    } else {
        $compres = [];
    }
    log_trace("[compseq] Returning final result: %s", $compres) if $COMPLETE_SEQUENCE_TRACE;
    $compres;
}

1;
# ABSTRACT:

=head1 ENVIRONMENT

=head2 COMPLETE_SEQUENCE_TRACE

Bool. If set to true, will display more log statements for debugging.


=head1 SEE ALSO

L<Complete::Path>. Conceptually, L</complete_sequence> is similar to
C<complete_path> from L<Complete::Path>. Except unlike a path, a sequence does
not (necessarily) have path separator.

L<Complete>
