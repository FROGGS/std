# STD.pm
#
# Copyright 2007-2010, Larry Wall
#
# You may copy this software under the terms of the Artistic License,
#     version 2.0 or later.

grammar STD:ver<6.0.0.alpha>:auth<http://perl.org>;

use DEBUG;
use NAME;
use Stash;

our $ALL;

=begin comment

    Contextuals used in STD
    =======================
    # per parse
    my $*ACTIONS;         # class or object which defines reduce actions
    my $*SETTINGNAME;     # name of core setting
    my $*TMP_PREFIX;      # where to put tmp files
    my $*ORIG;            # the original program string
    my @*ORIG;            # same thing as individual chars
    my @*MEMOS;           # per-position info such as ws and line number
    my $*HIGHWATER;      # where we were last looking for things
    my $*HIGHMESS;       # current parse failure message
    my $*HIGHEXPECT;     # things we were looking for at the bleeding edge
    my $*IN_PANIC;       # don't panic recursively

    # symbol table management
    our $ALL;            # all the stashes, keyed by id
    my $*CORE;            # the CORE scope
    my $*SETTING;         # the SETTING scope
    my $*GLOBAL;          # the GLOBAL scope
    my $*PROCESS;         # the PROCESS scope
    my $*UNIT;            # the UNIT scope
    my $*CURPAD;      # current lexical scope
    my $*CURPKG;          # current package scope

    my %*MYSTERY;     # names we assume may be post-declared functions

    # tree attributes, marked as propagating up (u) down (d) or up-and-down (u/d)
    my %*LANG;            # (d) braided languages: MAIN, Q, Regex, etc

    my $*IN_DECL;     # (d) a declarator is looking for a name to declare
    my $*SCOPE = "";      # (d) which scope declarator we're under
    my $*MULTINESS;       # (d) which multi declarator we're under
    my $*PKGDECL ::= "";         # (d) current package declarator
    my $*NEWPKG;      # (u/d) new package being declared
    my $*NEWPAD;      # (u/d) new lexpad being declared
    my $*DECLARAND;   # (u/d) new object associated with declaration

    my $*GOAL ::= "(eof)";  # (d) which special terminator we're most wanting
    my $*IN_REDUCE;   # (d) attempting to parse an [op] construct
    my $*IN_META;     # (d) parsing a metaoperator like [..]
    my $*QUASIMODO;   # (d) don't carp about quasi variables
    my $*LEFTSIGIL;   # (u) sigil of LHS for item vs list assignment
    my $*QSIGIL;      # (d) sigil of current interpolation

    my $*INVOCANT_OK; # (d) parsing a list that allows an invocant
    my $*INVOCANT_IS; # (u) invocant of args match

    my $*BORG;            # (u/d) who to blame if we're missing a block

=end comment

=begin notes

    Some rules are named by syntactic category plus an additional symbol
    specified in adverbial form, either in bare :name form or in :sym<name>
    form.  (It does not matter which form you use for identifier symbols,
    except that to specify a symbol "sym" you must use the :sym<sym> form
    of adverb.)  If you use the <sym> rule within the rule, it will parse the
    symbol at that point.  At the final reduction point of a rule, if $sym
    has been set, that is used as the final symbol name for the rule.  This
    need not match the symbol specified as part the rule name; that is just
    for disambiguating the name.  However, if no $sym is set, the original
    symbol will be used by default.

    Note that some of these rules are written strangely because we're
    still bootstrapping via a preprocessor, gimme5.  For instance,
    blocks that contain nested braces are delimited by double braces
    so that the preprocessor does not need to parse Perl 6 code.

    This grammar relies on transitive longest-token semantics, though
    initially we made a feeble attempt to order rules so a procedural
    interpretation of alternation could usually produce a correct parse.
    (This is becoming less true over time.)

=end notes

method TOP ($STOP = '') {
    my $lang = self.cursor_fresh( ::STD::P6 );

    if $STOP {
        my $*GOAL ::= $STOP;
        $lang.unitstop($STOP).comp_unit;
    }
    else {
        $lang.comp_unit;
    }
}

##############
# Precedence #
##############

# The internal precedence levels are *not* part of the public interface.
# The current values are mere implementation; they may change at any time.
# Users should specify precedence only in relation to existing levels.

constant %term            = (:dba('term')            , :prec<z=>);
constant %methodcall      = (:dba('methodcall')      , :prec<y=>, :assoc<unary>, :uassoc<left>, :fiddly);
constant %autoincrement   = (:dba('autoincrement')   , :prec<x=>, :assoc<unary>, :uassoc<non>);
constant %exponentiation  = (:dba('exponentiation')  , :prec<w=>, :assoc<right>);
constant %symbolic_unary  = (:dba('symbolic unary')  , :prec<v=>, :assoc<unary>, :uassoc<left>);
constant %multiplicative  = (:dba('multiplicative')  , :prec<u=>, :assoc<left>);
constant %additive        = (:dba('additive')        , :prec<t=>, :assoc<left>);
constant %replication     = (:dba('replication')     , :prec<s=>, :assoc<left>);
constant %concatenation   = (:dba('concatenation')   , :prec<r=>, :assoc<list>);
constant %junctive_and    = (:dba('junctive and')    , :prec<q=>, :assoc<list>);
constant %junctive_or     = (:dba('junctive or')     , :prec<p=>, :assoc<list>);
constant %named_unary     = (:dba('named unary')     , :prec<o=>, :assoc<unary>, :uassoc<left>);
constant %structural      = (:dba('structural infix'), :prec<n=>, :assoc<non>, :diffy);
constant %chaining        = (:dba('chaining')        , :prec<m=>, :assoc<chain>, :diffy, :iffy);
constant %tight_and       = (:dba('tight and')       , :prec<l=>, :assoc<list>);
constant %tight_or        = (:dba('tight or')        , :prec<k=>, :assoc<list>);
constant %conditional     = (:dba('conditional')     , :prec<j=>, :assoc<right>, :fiddly);
constant %item_assignment = (:dba('item assignment') , :prec<i=>, :assoc<right>);
constant %list_assignment = (:dba('list assignment') , :prec<i=>, :assoc<right>, :sub<e=>, :fiddly);
constant %loose_unary     = (:dba('loose unary')     , :prec<h=>, :assoc<unary>, :uassoc<left>);
constant %comma           = (:dba('comma')           , :prec<g=>, :assoc<list>, :nextterm<nulltermish>, :fiddly);
constant %list_infix      = (:dba('list infix')      , :prec<f=>, :assoc<list>);
constant %list_prefix     = (:dba('list prefix')     , :prec<e=>, :assoc<unary>, :uassoc<left>);
constant %loose_and       = (:dba('loose and')       , :prec<d=>, :assoc<list>);
constant %loose_or        = (:dba('loose or')        , :prec<c=>, :assoc<list>);
constant %sequencer       = (:dba('sequencer')       , :prec<b=>, :assoc<list>, :nextterm<statement>, :fiddly);
constant %LOOSEST         = (:dba('LOOSEST')         , :prec<a=!>);
constant %terminator      = (:dba('terminator')      , :prec<a=>, :assoc<list>);

# "epsilon" tighter than terminator
#constant $LOOSEST = %LOOSEST<prec>;
constant $LOOSEST = "a=!"; # XXX preceding line is busted
constant $item_assignment_prec = 'i=';
constant $methodcall_prec = 'y=';

##############
# Categories #
##############

# Categories are designed to be easily extensible in derived grammars
# by merely adding more rules in the same category.  The rules within
# a given category start with the category name followed by a differentiating
# adverbial qualifier to serve (along with the category) as the longer name.

# The endsym context, if specified, says what to implicitly check for in each
# rule right after the initial <sym>.  Normally this is used to make sure
# there's appropriate whitespace.  # Note that endsym isn't called if <sym>
# isn't called.

my $*endsym = "null";
my $*endargs = -1;

proto token category { <...> }

token category:category { <sym> }

token category:sigil { <sym> }
proto token sigil { <...> }

token category:twigil { <sym> }
proto token twigil { <...> }

token category:special_variable { <sym> }
proto token special_variable { <...> }

token category:comment { <sym> }
proto token comment { <...> }

token category:version { <sym> }
proto token version { <...> }

token category:module_name { <sym> }
proto token module_name { <...> }

token category:value { <sym> }
proto token value { <...> }

token category:term { <sym> }
proto token term { <...> }

token category:number { <sym> }
proto token number { <...> }

token category:quote { <sym> }
proto token quote () { <...> }

token category:prefix { <sym> }
proto token prefix is unary is defequiv(%symbolic_unary) { <...> }

token category:infix { <sym> }
proto token infix is binary is defequiv(%additive) { <...> }

token category:postfix { <sym> }
proto token postfix is unary is defequiv(%autoincrement) { <...> }

token category:dotty { <sym> }
proto token dotty (:$*endsym = 'unspacey') { <...> }

token category:circumfix { <sym> }
proto token circumfix { <...> }

token category:postcircumfix { <sym> }
proto token postcircumfix is unary { <...> }  # unary as far as EXPR knows...

token category:quote_mod { <sym> }
proto token quote_mod { <...> }

token category:trait_mod { <sym> }
proto token trait_mod (:$*endsym = 'spacey') { <...> }

token category:type_declarator { <sym> }
proto token type_declarator (:$*endsym = 'spacey') { <...> }

token category:scope_declarator { <sym> }
proto token scope_declarator (:$*endsym = 'nofun') { <...> }

token category:package_declarator { <sym> }
proto token package_declarator (:$*endsym = 'spacey') { <...> }

token category:multi_declarator { <sym> }
proto token multi_declarator (:$*endsym = 'spacey') { <...> }

token category:routine_declarator { <sym> }
proto token routine_declarator (:$*endsym = 'nofun') { <...> }

token category:regex_declarator { <sym> }
proto token regex_declarator (:$*endsym = 'spacey') { <...> }

token category:statement_prefix { <sym> }
proto rule  statement_prefix () { <...> }

token category:statement_control { <sym> }
proto rule  statement_control (:$*endsym = 'spacey') { <...> }

token category:statement_mod_cond { <sym> }
proto rule  statement_mod_cond (:$*endsym = 'nofun') { <...> }

token category:statement_mod_loop { <sym> }
proto rule  statement_mod_loop (:$*endsym = 'nofun') { <...> }

token category:infix_prefix_meta_operator { <sym> }
proto token infix_prefix_meta_operator is binary { <...> }

token category:infix_postfix_meta_operator { <sym> }
proto token infix_postfix_meta_operator ($op) is binary { <...> }

token category:infix_circumfix_meta_operator { <sym> }
proto token infix_circumfix_meta_operator is binary { <...> }

token category:postfix_prefix_meta_operator { <sym> }
proto token postfix_prefix_meta_operator is unary { <...> }

token category:prefix_postfix_meta_operator { <sym> }
proto token prefix_postfix_meta_operator is unary { <...> }

token category:prefix_circumfix_meta_operator { <sym> }
proto token prefix_circumfix_meta_operator is unary { <...> }

token category:terminator { <sym> }
proto token terminator { <...> }

token unspacey { <.unsp>? }
token endid { <?before <-[ \- \' \w ]> > }
token spacey { <?before <[ \s \# ]> > }
token nofun { <!before '(' | '.(' | '\\' | '\'' | '-' | "'" | \w > }

# Note, don't reduce on a bare sigil unless you don't want a twigil or
# you otherwise don't care what the longest token is.

token sigil:sym<$>  { <sym> }
token sigil:sym<@>  { <sym> }
token sigil:sym<%>  { <sym> }
token sigil:sym<&>  { <sym> }

token twigil:sym<.> { <sym> }
token twigil:sym<!> { <sym> }
token twigil:sym<^> { <sym> <?before \w> }
token twigil:sym<:> { <sym> <?before \w> }
token twigil:sym<*> { <sym> }
token twigil:sym<+> { <sym> <!!worry: "The + twigil is deprecated, use the * twigil instead"> }
token twigil:sym<?> { <sym> }
token twigil:sym<=> { <sym> }
token twigil:sym<~> { <sym> }

# overridden in subgrammars
token stopper { <!> }

# hopefully we can include these tokens in any outer LTM matcher
regex stdstopper {
    :my @stub = return self if @*MEMOS[self.pos]<endstmt> :exists;
    :dba('standard stopper')
    [
    | <?terminator>
    | <?unitstopper>
    | $                                 # unlikely, check last (normal LTM behavior)
    ]
    { @*MEMOS[$¢.pos]<endstmt> ||= 1; }
}

token longname {
    <name> <colonpair>*
}

token name {
    [
    | <identifier> <morename>*
    | <morename>+
    ]
}

token morename {
    :my $*QSIGIL ::= '';
    '::'
    [
    ||  <?before '(' | <alpha> >
        [
        | <identifier>
        | :dba('indirect name') '(' ~ ')' <EXPR>
        ]
    || <?before '::'> <.panic: "Name component may not be null">
    ]?
}

##############################
# Quote primitives           #
##############################

# XXX should eventually be derived from current Unicode tables.
constant %open2close = (
"\x0028" => "\x0029",
"\x003C" => "\x003E",
"\x005B" => "\x005D",
"\x007B" => "\x007D",
"\x00AB" => "\x00BB",
"\x0F3A" => "\x0F3B",
"\x0F3C" => "\x0F3D",
"\x169B" => "\x169C",
"\x2018" => "\x2019",
"\x201A" => "\x2019",
"\x201B" => "\x2019",
"\x201C" => "\x201D",
"\x201E" => "\x201D",
"\x201F" => "\x201D",
"\x2039" => "\x203A",
"\x2045" => "\x2046",
"\x207D" => "\x207E",
"\x208D" => "\x208E",
"\x2208" => "\x220B",
"\x2209" => "\x220C",
"\x220A" => "\x220D",
"\x2215" => "\x29F5",
"\x223C" => "\x223D",
"\x2243" => "\x22CD",
"\x2252" => "\x2253",
"\x2254" => "\x2255",
"\x2264" => "\x2265",
"\x2266" => "\x2267",
"\x2268" => "\x2269",
"\x226A" => "\x226B",
"\x226E" => "\x226F",
"\x2270" => "\x2271",
"\x2272" => "\x2273",
"\x2274" => "\x2275",
"\x2276" => "\x2277",
"\x2278" => "\x2279",
"\x227A" => "\x227B",
"\x227C" => "\x227D",
"\x227E" => "\x227F",
"\x2280" => "\x2281",
"\x2282" => "\x2283",
"\x2284" => "\x2285",
"\x2286" => "\x2287",
"\x2288" => "\x2289",
"\x228A" => "\x228B",
"\x228F" => "\x2290",
"\x2291" => "\x2292",
"\x2298" => "\x29B8",
"\x22A2" => "\x22A3",
"\x22A6" => "\x2ADE",
"\x22A8" => "\x2AE4",
"\x22A9" => "\x2AE3",
"\x22AB" => "\x2AE5",
"\x22B0" => "\x22B1",
"\x22B2" => "\x22B3",
"\x22B4" => "\x22B5",
"\x22B6" => "\x22B7",
"\x22C9" => "\x22CA",
"\x22CB" => "\x22CC",
"\x22D0" => "\x22D1",
"\x22D6" => "\x22D7",
"\x22D8" => "\x22D9",
"\x22DA" => "\x22DB",
"\x22DC" => "\x22DD",
"\x22DE" => "\x22DF",
"\x22E0" => "\x22E1",
"\x22E2" => "\x22E3",
"\x22E4" => "\x22E5",
"\x22E6" => "\x22E7",
"\x22E8" => "\x22E9",
"\x22EA" => "\x22EB",
"\x22EC" => "\x22ED",
"\x22F0" => "\x22F1",
"\x22F2" => "\x22FA",
"\x22F3" => "\x22FB",
"\x22F4" => "\x22FC",
"\x22F6" => "\x22FD",
"\x22F7" => "\x22FE",
"\x2308" => "\x2309",
"\x230A" => "\x230B",
"\x2329" => "\x232A",
"\x23B4" => "\x23B5",
"\x2768" => "\x2769",
"\x276A" => "\x276B",
"\x276C" => "\x276D",
"\x276E" => "\x276F",
"\x2770" => "\x2771",
"\x2772" => "\x2773",
"\x2774" => "\x2775",
"\x27C3" => "\x27C4",
"\x27C5" => "\x27C6",
"\x27D5" => "\x27D6",
"\x27DD" => "\x27DE",
"\x27E2" => "\x27E3",
"\x27E4" => "\x27E5",
"\x27E6" => "\x27E7",
"\x27E8" => "\x27E9",
"\x27EA" => "\x27EB",
"\x2983" => "\x2984",
"\x2985" => "\x2986",
"\x2987" => "\x2988",
"\x2989" => "\x298A",
"\x298B" => "\x298C",
"\x298D" => "\x298E",
"\x298F" => "\x2990",
"\x2991" => "\x2992",
"\x2993" => "\x2994",
"\x2995" => "\x2996",
"\x2997" => "\x2998",
"\x29C0" => "\x29C1",
"\x29C4" => "\x29C5",
"\x29CF" => "\x29D0",
"\x29D1" => "\x29D2",
"\x29D4" => "\x29D5",
"\x29D8" => "\x29D9",
"\x29DA" => "\x29DB",
"\x29F8" => "\x29F9",
"\x29FC" => "\x29FD",
"\x2A2B" => "\x2A2C",
"\x2A2D" => "\x2A2E",
"\x2A34" => "\x2A35",
"\x2A3C" => "\x2A3D",
"\x2A64" => "\x2A65",
"\x2A79" => "\x2A7A",
"\x2A7D" => "\x2A7E",
"\x2A7F" => "\x2A80",
"\x2A81" => "\x2A82",
"\x2A83" => "\x2A84",
"\x2A8B" => "\x2A8C",
"\x2A91" => "\x2A92",
"\x2A93" => "\x2A94",
"\x2A95" => "\x2A96",
"\x2A97" => "\x2A98",
"\x2A99" => "\x2A9A",
"\x2A9B" => "\x2A9C",
"\x2AA1" => "\x2AA2",
"\x2AA6" => "\x2AA7",
"\x2AA8" => "\x2AA9",
"\x2AAA" => "\x2AAB",
"\x2AAC" => "\x2AAD",
"\x2AAF" => "\x2AB0",
"\x2AB3" => "\x2AB4",
"\x2ABB" => "\x2ABC",
"\x2ABD" => "\x2ABE",
"\x2ABF" => "\x2AC0",
"\x2AC1" => "\x2AC2",
"\x2AC3" => "\x2AC4",
"\x2AC5" => "\x2AC6",
"\x2ACD" => "\x2ACE",
"\x2ACF" => "\x2AD0",
"\x2AD1" => "\x2AD2",
"\x2AD3" => "\x2AD4",
"\x2AD5" => "\x2AD6",
"\x2AEC" => "\x2AED",
"\x2AF7" => "\x2AF8",
"\x2AF9" => "\x2AFA",
"\x2E02" => "\x2E03",
"\x2E04" => "\x2E05",
"\x2E09" => "\x2E0A",
"\x2E0C" => "\x2E0D",
"\x2E1C" => "\x2E1D",
"\x2E20" => "\x2E21",
"\x3008" => "\x3009",
"\x300A" => "\x300B",
"\x300C" => "\x300D",
"\x300E" => "\x300F",
"\x3010" => "\x3011",
"\x3014" => "\x3015",
"\x3016" => "\x3017",
"\x3018" => "\x3019",
"\x301A" => "\x301B",
"\x301D" => "\x301E",
"\xFD3E" => "\xFD3F",
"\xFE17" => "\xFE18",
"\xFE35" => "\xFE36",
"\xFE37" => "\xFE38",
"\xFE39" => "\xFE3A",
"\xFE3B" => "\xFE3C",
"\xFE3D" => "\xFE3E",
"\xFE3F" => "\xFE40",
"\xFE41" => "\xFE42",
"\xFE43" => "\xFE44",
"\xFE47" => "\xFE48",
"\xFE59" => "\xFE5A",
"\xFE5B" => "\xFE5C",
"\xFE5D" => "\xFE5E",
"\xFF08" => "\xFF09",
"\xFF1C" => "\xFF1E",
"\xFF3B" => "\xFF3D",
"\xFF5B" => "\xFF5D",
"\xFF5F" => "\xFF60",
"\xFF62" => "\xFF63",
);

constant %close2open = invert %open2close;

token opener {
  <[
\x0028
\x003C
\x005B
\x007B
\x00AB
\x0F3A
\x0F3C
\x169B
\x2018
\x201A
\x201B
\x201C
\x201E
\x201F
\x2039
\x2045
\x207D
\x208D
\x2208
\x2209
\x220A
\x2215
\x223C
\x2243
\x2252
\x2254
\x2264
\x2266
\x2268
\x226A
\x226E
\x2270
\x2272
\x2274
\x2276
\x2278
\x227A
\x227C
\x227E
\x2280
\x2282
\x2284
\x2286
\x2288
\x228A
\x228F
\x2291
\x2298
\x22A2
\x22A6
\x22A8
\x22A9
\x22AB
\x22B0
\x22B2
\x22B4
\x22B6
\x22C9
\x22CB
\x22D0
\x22D6
\x22D8
\x22DA
\x22DC
\x22DE
\x22E0
\x22E2
\x22E4
\x22E6
\x22E8
\x22EA
\x22EC
\x22F0
\x22F2
\x22F3
\x22F4
\x22F6
\x22F7
\x2308
\x230A
\x2329
\x23B4
\x2768
\x276A
\x276C
\x276E
\x2770
\x2772
\x2774
\x27C3
\x27C5
\x27D5
\x27DD
\x27E2
\x27E4
\x27E6
\x27E8
\x27EA
\x2983
\x2985
\x2987
\x2989
\x298B
\x298D
\x298F
\x2991
\x2993
\x2995
\x2997
\x29C0
\x29C4
\x29CF
\x29D1
\x29D4
\x29D8
\x29DA
\x29F8
\x29FC
\x2A2B
\x2A2D
\x2A34
\x2A3C
\x2A64
\x2A79
\x2A7D
\x2A7F
\x2A81
\x2A83
\x2A8B
\x2A91
\x2A93
\x2A95
\x2A97
\x2A99
\x2A9B
\x2AA1
\x2AA6
\x2AA8
\x2AAA
\x2AAC
\x2AAF
\x2AB3
\x2ABB
\x2ABD
\x2ABF
\x2AC1
\x2AC3
\x2AC5
\x2ACD
\x2ACF
\x2AD1
\x2AD3
\x2AD5
\x2AEC
\x2AF7
\x2AF9
\x2E02
\x2E04
\x2E09
\x2E0C
\x2E1C
\x2E20
\x3008
\x300A
\x300C
\x300E
\x3010
\x3014
\x3016
\x3018
\x301A
\x301D
\xFD3E
\xFE17
\xFE35
\xFE37
\xFE39
\xFE3B
\xFE3D
\xFE3F
\xFE41
\xFE43
\xFE47
\xFE59
\xFE5B
\xFE5D
\xFF08
\xFF1C
\xFF3B
\xFF5B
\xFF5F
\xFF62
  ]>
}

# assumes whitespace is eaten already

method peek_delimiters {
    my $pos = self.pos;
    my $startpos = $pos;
    my $char = substr($*ORIG,$pos++,1);
    if $char ~~ /^\s$/ {
        self.panic("Whitespace character is not allowed as delimiter"); # "can't happen"
    }
    elsif $char ~~ /^\w$/ {
        self.panic("Alphanumeric character is not allowed as delimiter");
    }
    elsif %close2open{$char} {
        self.panic("Use of a closing delimiter for an opener is reserved");
    }
    elsif $char eq ':' {
        self.panic("Colons may not be used to delimit quoting constructs");
    }

    my $rightbrack = %open2close{$char};
    if not defined $rightbrack {
        return $char, $char;
    }
    while substr($*ORIG,$pos,1) eq $char {
        $pos++;
    }
    my $len = $pos - $startpos;
    my $start = $char x $len;
    my $stop = $rightbrack x $len;
    return $start, $stop;
}

role startstop[$start,$stop] {
    token starter { $start }
    token stopper { $stop }
} # end role

role stop[$stop] {
    token starter { <!> }
    token stopper { $stop }
} # end role

role unitstop[$stop] {
    token unitstopper { $stop }
} # end role

token unitstopper { $ }

method balanced ($start,$stop) { self.mixin( ::startstop[$start,$stop] ); }
method unbalanced ($stop) { self.mixin( ::stop[$stop] ); }
method unitstop ($stop) { self.mixin( ::unitstop[$stop] ); }

method truly ($bool,$opt) {
    return self if $bool;
    self.panic("Can't negate $opt adverb");
}

token charname {
    [
    | <radint>
    | <[a..z A..Z]><-[ \] , # ]>*?<[a..z A..Z ) ]> <?before \s*<[ \] , # ]>>
    ] || <.panic: "Unrecognized character name">
}

token charnames { [<.ws><charname><.ws>] ** ',' }

token charspec {
    [
    | :dba('character name') '[' ~ ']' <charnames>
    | \d+
    | <[ ?..Z \\.._ ]>
    | <?> <.panic: "Unrecognized \\c character">
    ]
}

proto token backslash { <...> }
proto token escape { <...> }
token starter { <!> }
token escape:none { <!> }

# and this is what makes nibbler polymorphic...
method nibble ($lang) {
    self.cursor_fresh($lang).nibbler;
}

# note: polymorphic over many quote languages, we hope
token nibbler {
    :my $text = '';
    :my $from = self.pos;
    :my $to = $from;
    :my @nibbles = ();
    :my $multiline = 0;
    :my $nibble;
    { $<_from> = self.pos; }
    [ <!before <stopper> >
        [
        || <starter> <nibbler> <stopper>
                        {{
                            push @nibbles, $¢.makestr(TEXT => $text, _from => $from, _pos => $to ) if $from != $to;

                            my $n = $<nibbler>[*-1]<nibbles>;
                            my @n = @$n;

                            push @nibbles, $<starter>;
                            push @nibbles, @n;
                            push @nibbles, $<stopper>;

                            $text = '';
                            $to = $from = $¢.pos;
                        }}
        || <escape>     {{
                            push @nibbles, $¢.makestr(TEXT => $text, _from => $from, _pos => $to ) if $from != $to;
                            push @nibbles, $<escape>[*-1];
                            $text = '';
                            $to = $from = $¢.pos;
                        }}
        || .
                        {{
                            my $ch = substr($*ORIG, $¢.pos-1, 1);
                            $text ~= $ch;
                            $to = $¢.pos;
                            if $ch ~~ "\n" {
                                $multiline++;
                            }
                        }}
        ]
    ]*
    {{
        push @nibbles, $¢.makestr(TEXT => $text, _from => $from, _pos => $to ) if $from != $to or !@nibbles;
        $<nibbles> = \@nibbles;
        $<_pos> = $¢.pos;
        $<nibbler> :delete;
        $<escape> :delete;
        $<starter> :delete;
        $<stopper> :delete;
        $*LAST_NIBBLE = $¢;
        $*LAST_NIBBLE_MULTILINE = $¢ if $multiline;
    }}
}

token babble ($l) {
    :my $lang = $l;
    :my $start;
    :my $stop;

    <.ws>
    [ <quotepair> <.ws>
        {
            my $kv = $<quotepair>[*-1];
            $lang = $lang.tweak($kv.<k>, $kv.<v>)
                or self.panic("Unrecognized adverb :" ~ $kv.<k> ~ '(' ~ $kv.<v> ~ ')');
        }
    ]*

    {
        ($start,$stop) = $¢.peek_delimiters();
        $lang = $start ne $stop ?? $lang.balanced($start,$stop)
                                !! $lang.unbalanced($stop);
        $<B> = [$lang,$start,$stop];
    }
}

our @herestub_queue;

class Herestub {
    has Str $.delim;
    has $.orignode;
    has $.lang;
} # end class

role herestop {
    token stopper { ^^ {} $<ws>=(\h*?) $*DELIM \h* <.unv>?? $$ \v? }
} # end role

# XXX be sure to temporize @herestub_queue on reentry to new line of heredocs

method heredoc () {
    my $*CTX ::= self.callm if $*DEBUG +& DEBUG::trace_call;
    return if self.peek;
    my $here = self;
    while my $herestub = shift @herestub_queue {
        my $*DELIM = $herestub.delim;
        my $lang = $herestub.lang.mixin( ::herestop );
        my $doc;
        if ($doc) = $here.nibble($lang) {
            $here = $doc.trim_heredoc();
            $herestub.orignode<doc> = $doc;
        }
        else {
            self.panic("Ending delimiter $*DELIM not found");
        }
    }
    return self.cursor($here.pos);  # return to initial type
}

token quibble ($l) {
    :my ($lang, $start, $stop);
    <babble($l)>
    { my $B = $<babble><B>; ($lang,$start,$stop) = @$B; }

    $start <nibble($lang)> [ $stop || <.panic: "Couldn't find terminator $stop"> ]

    {{
        if $lang<_herelang> {
            push @herestub_queue,
                ::Herestub.new(
                    delim => $<nibble><nibbles>[0]<TEXT>,
                    orignode => $¢,
                    lang => $lang<_herelang>,
                );
        }
    }}
}

token quotepair {
    :my $key;
    :my $value;

    ':'
    :dba('colon pair (restricted)')
    [
    | '!' <identifier> [ '(' <.panic: "Argument not allowed on negated pair"> ]?
        { $key = $<identifier>.Str; $value = 0; }
    | <identifier>
        { $key = $<identifier>.Str; }
        [
        || <.unsp>? <?before '('> <circumfix> { $value = $<circumfix>; }
        || { $value = 1; }
        ]
    | $<n>=(\d+) $<id>=(<[a..z]>+) [ '(' <.panic: "2nd argument not allowed on pair"> ]?
        { $key = $<id>.Str; $value = $<n>.Str; }
    ]
    { $<k> = $key; $<v> = $value; }
}

token quote:sym<' '>   { "'" <nibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:q).unbalanced("'"))> "'" }
token quote:sym<" ">   { '"' <nibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:qq).unbalanced('"'))> '"' }

token circumfix:sym<« »>   { '«' <nibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:qq).tweak(:ww).balanced('«','»'))> '»' }
token circumfix:sym«<< >>» { '<<' <nibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:qq).tweak(:ww).balanced('<<','>>'))> '>>' }
token circumfix:sym«< >»   { '<'
                              [ <?before 'STDIN>' > <.obs('<STDIN>', '$' ~ '*IN.lines')> ]?  # XXX fake out gimme5
                              [ <?before '>' > <.obs('<>', 'lines() or ()')> ]?
                              <nibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:q).tweak(:w).balanced('<','>'))> '>' }

##################
# Lexer routines #
##################

token ws {
    :my @stub = return self if @*MEMOS[self.pos]<ws> :exists;
    :my $startpos = self.pos;
    :my $*HIGHEXPECT = {};

    :dba('whitespace')
    [
        | \h+ <![#\s\\]> { @*MEMOS[$¢.pos]<ws> = $startpos; }   # common case
        | <?before \w> <?after \w> :::
            { @*MEMOS[$startpos]<ws>:delete; }
            <.panic: "Whitespace is required between alphanumeric tokens">        # must \s+ between words
    ]
    ||
    [
    | <.unsp>
    | <.vws> <.heredoc>
    | <.unv>
    | $ { $¢.moreinput }
    ]*

    {{
        if ($¢.pos == $startpos) {
            @*MEMOS[$¢.pos]<ws>:delete;
        }
        else {
            @*MEMOS[$¢.pos]<ws> = $startpos;
            @*MEMOS[$¢.pos]<endstmt> = @*MEMOS[$startpos]<endstmt>
                if @*MEMOS[$startpos]<endstmt> :exists;
        }
    }}
}

token unsp {
    \\ <?before [\s|'#'] >
    :dba('unspace')
    [
    | <.vws>
    | <.unv>
    | $ { $¢.moreinput }
    ]*
}

token vws {
    :dba('vertical whitespace')
    \v
    [ '#DEBUG -1' { say "DEBUG"; $STD::DEBUG = $*DEBUG = -1; } ]?
}

# We provide two mechanisms here:
# 1) define $*moreinput, or
# 2) override moreinput method
method moreinput () {
    $*moreinput.() if $*moreinput;
}

token unv {
   :dba('horizontal whitespace')
   [
   | \h+
   | <?before \h* '=' [ \w | '\\'] > ^^ <.pod_comment>
   | \h* <comment>
   ]
}

token comment:sym<#`(...)> {
    '#`' [ <?opener> || <.panic: "Opening bracket is required for #` comment"> ]
    <.quibble($¢.cursor_fresh( %*LANG<Q> ))>
}

token comment:sym<#(...)> {
    '#' <?opener> <.worry: "Embedded comment without backtick is deprecated"> <!>
    <.quibble($¢.cursor_fresh( %*LANG<Q> ))>
}

token comment:sym<#=(...)> {
    '#=' <?opener>
    <quibble($¢.cursor_fresh( %*LANG<Q> ))>
}

token comment:sym<#=> {
   '#=' {} $<attachment> = [\N*]
}

token comment:sym<#> {
   '#' {} \N*
}

token ident {
    <.alpha> \w*
}

token apostrophe {
    <[ ' \- ]>
}

token identifier {
    <.ident> [ <.apostrophe> <.ident> ]*
}

# XXX We need to parse the pod eventually to support $= variables.

token pod_comment {
    ^^ \h* '=' <.unsp>?
    [
    | 'begin' \h+ <identifier> ::
        [
        ||  .*? "\n" \h* '=' <.unsp>? 'end' \h+ $<identifier> » \N*
        ||  <?{ $<identifier>.Str eq 'END'}> .*
        || { my $id = $<identifier>.Str; self.panic("=begin $id without matching =end $id"); }
        ]
    | 'begin' » :: \h* [ $$ || '#' || <.panic: "Unrecognized token after =begin"> ]
        [ .*? "\n" \h* '=' <.unsp>? 'end' » \N* || { self.panic("=begin without matching =end"); } ]
        
    | 'for' » :: \h* [ <identifier> || $$ || '#' || <.panic: "Unrecognized token after =for"> ]
        [.*?  ^^ \h* $$ || .*]
    | :: 
        [ <?before .*? ^^ '=cut' » > <.panic: "Obsolescent pod format, please use =begin/=end instead"> ]?
        [<alpha>||\s||<.panic: "Illegal pod directive">]
        \N*
    ]
}

# suppress fancy end-of-line checking
token embeddedblock {
    # encapsulate braided languages
    :temp %*LANG;
    :my $*SIGNUM;
    :my $*GOAL ::= '}';
    :temp $*CURPAD;

    :dba('embedded block')

    <.newpad>
    <.finishpad>
    '{' :: [ :lang($¢.cursor_fresh(%*LANG<MAIN>)) <statementlist> ]
    [ '}' || <.panic: "Unable to parse statement list; couldn't find right brace"> ]
}

token binints { [<.ws><binint><.ws>] ** ',' }

token binint {
    <[ 0..1 ]>+ [ _ <[ 0..1 ]>+ ]*
}

token octints { [<.ws><octint><.ws>] ** ',' }

token octint {
    <[ 0..7 ]>+ [ _ <[ 0..7 ]>+ ]*
}

token hexints { [<.ws><hexint><.ws>] ** ',' }

token hexint {
    <[ 0..9 a..f A..F ]>+ [ _ <[ 0..9 a..f A..F ]>+ ]*
}

token decints { [<.ws><decint><.ws>] ** ',' }

token decint {
    \d+ [ _ \d+ ]*
}

token integer {
    [
    | 0 [ b <binint>
        | o <octint>
        | x <hexint>
        | d <decint>
        | <decint>
            <!!{ $¢.worry("Leading 0 does not indicate octal in Perl 6") }>
        ]
    | <decint>
    ]
    <!!before ['.' <?before \s | ',' | '=' | <terminator> > <.panic: "Decimal point must be followed by digit">]? >
}

token radint {
    [
    | <integer>
    | <?before ':'\d> <rad_number> <?{
                        defined $<rad_number><intpart>
                        and
                        not defined $<rad_number><fracpart>
                    }>
    ]
}

token escale {
    <[Ee]> <[+\-]>? <decint>
}

# careful to distinguish from both integer and 42.method
token dec_number {
    :dba('decimal number')
    [
    | $<coeff> = [              '.' <frac=.decint> ] <escale>?
    | $<coeff> = [<int=.decint> '.' <frac=.decint> ] <escale>?
    | $<coeff> = [<int=.decint>                    ] <escale>
    ]
    <!!before [ '.' <?before \d> <.panic: "Number contains two decimal points (missing 'v' for version number?)">]? >
}

token rad_number {
    ':' $<radix> = [\d+] <.unsp>?      # XXX optional dot here?
    {}           # don't recurse in lexer
    :dba('number in radix notation')
    [
    || '<'
            $<intpart> = [ <[ 0..9 a..z A..Z ]>+ [ _ <[ 0..9 a..z A..Z ]>+ ]* ]
            $<fracpart> = [ '.' <[ 0..9 a..z A..Z ]>+ [ _ <[ 0..9 a..z A..Z ]>+ ]* ]?
            [ '*' <base=.radint> '**' <exp=.radint> ]?
       '>'
#      { make radcalc($<radix>, $<intpart>, $<fracpart>, $<base>, $<exp>) }
    || <?before '['> <circumfix>
    || <?before '('> <circumfix>
    || <.panic: "Malformed radix number">
    ]
}

token terminator:sym<)>
    { <sym> <O(|%terminator)> }

token terminator:sym<]>
    { ']' <O(|%terminator)> }

token terminator:sym<}>
    { '}' <O(|%terminator)> }

grammar P6 is STD {

    ###################
    # Top-level rules #
    ###################

    # Note: we only check for the stopper.  We don't check for ^ because
    # we might be embedded in something else.
    rule comp_unit {
        :my $*begin_compunit = 1;
        :my $*endargs = -1;
        :my %*LANG;
        :my $*PKGDECL ::= "";
        :my $*IN_DECL = '';
        :my $*DECLARAND;
        :my $*NEWPKG;
        :my $*NEWPAD;
        :my $*QSIGIL ::= '';
        :my $*IN_META = 0;
        :my $*QUASIMODO;
        :my $*SCOPE = "";
        :my $*LEFTSIGIL;
        :my $*PRECLIM;
        :my %*MYSTERY = ();
        :my $*INVOCANT_OK;
        :my $*INVOCANT_IS;
        :my $*CURPAD;
        :my $*MULTINESS = '';
        :my $*SIGNUM = 0;

        :my $*CURPKG;
        {{

            %*LANG<MAIN>    = ::STD::P6 ;
            %*LANG<Q>       = ::STD::Q ;
            %*LANG<Quasi>   = ::STD::Quasi ;
            %*LANG<Regex>   = ::STD::Regex ;
            %*LANG<Trans>   = ::STD::Trans ;
            %*LANG<P5>      = ::STD::P5 ;
            %*LANG<P5Regex> = ::STD::P5::Regex ;

            @*WORRIES = ();
            self.load_setting($*SETTINGNAME);
            my $oid = $*SETTING.id;
            my $id = 'MY:file<' ~ $*FILE<name> ~ '>';
            $*CURPAD = Stash.new(
                'OUTER::' => [$oid],
                '!file' => $*FILE, '!line' => 0,
                '!id' => [$id],
            );
            $ALL.{$id} = $*CURPAD;
            $*UNIT = $*CURPAD;
            $ALL.<UNIT> = $*UNIT;
            self.finishpad;
        }}
        <statementlist>
        [ <?unitstopper> || <.panic: "Confused"> ]
        # "CHECK" time...
        {{
            if @*WORRIES {
                warn "Potential difficulties:\n  " ~ join( "\n  ", @*WORRIES) ~ "\n";
            }
            my $m = $¢.explain_mystery();
            warn $m if $m;
        }}
    }

    # Note: because of the possibility of placeholders we can't determine arity of
    # the block syntactically, so this must be determined via semantic analysis.
    # Also, pblocks used in an if/unless statement do not treat $_ as a placeholder,
    # while most other blocks treat $_ as equivalent to $^x.  Therefore the first
    # possible place to check arity is not here but in the rule that calls this
    # rule.  (Could also be done in a later pass.)

    token pblock () {
        :temp $*CURPAD;
        :dba('parameterized block')
        [<?before <.lambda> | '{' > ||
            {{
                if $*BORG and $*BORG.<block> {
                    if $*BORG.<name> {
                        my $m = "Function '" ~ $*BORG.<name> ~ "' needs parens to avoid gobbling block" ~ $*BORG.<culprit>.locmess;
                        $*BORG.<block>.panic($m ~ "\nMissing block (apparently gobbled by '" ~ $*BORG.<name> ~ "')");
                    }
                    else {
                        my $m = "Expression needs parens to avoid gobbling block" ~ $*BORG.<culprit>.locmess;
                        $*BORG.<block>.panic($m ~ "\nMissing block (apparently gobbled by expression)");
                    }
                }
                elsif %*MYSTERY {
                    $¢.panic("Missing block (apparently gobbled by undeclared routine?)");
                }
                else {
                    $¢.panic("Missing block");
                }
            }}
        ]
        [
        | <lambda>
            <.newpad(1)>
            <signature(1)>
            <blockoid>
            <.getsig>
        | <?before '{'>
            <.newpad(1)>
            <blockoid>
            <.getsig>
        ]
    }

    token lambda { '->' | '<->' }

    # Look for an expression followed by a required lambda.
    token xblock {
        :my $*GOAL ::= '{';
        :my $*BORG = {};
        <EXPR>
        { $*BORG.<culprit> //= $<EXPR>.cursor(self.pos) }
        <.ws>
        <pblock>
    }

    token block () {
        :temp $*CURPAD;
        :dba('scoped block')
        [ <?before '{' > || <.panic: "Missing block"> ]
        <.newpad>
        <blockoid>
        <.checkyada>
    }

    token blockoid {
        # encapsulate braided languages
        :temp %*LANG;
        :my $*SIGNUM;

        <.finishpad>
        [
        | :dba('block') '{' ~ '}' <statementlist>
        | <?terminator> <.panic: 'Missing block'>
        | <?> <.panic: "Malformed block">
        ]

        [
        | <?before \h* $$>  # (usual case without comments)
            { @*MEMOS[$¢.pos]<endstmt> = 2; }
        | \h* <?before <[\\,:]>>
        | <.unv>? $$
            { @*MEMOS[$¢.pos]<endstmt> = 2; }
        | {} <.unsp>? { @*MEMOS[$¢.pos]<endargs> = 1; }
        ]
    }

    token regex_block {
        # encapsulate braided languages
        :temp %*LANG;

        :my $lang = %*LANG<Regex>;
        :my $*GOAL ::= '}';

        [ <quotepair> <.ws>
            {
                my $kv = $<quotepair>[*-1];
                $lang = $lang.tweak($kv.<k>, $kv.<v>)
                    or self.panic("Unrecognized adverb :" ~ $kv.<k> ~ '(' ~ $kv.<v> ~ ')');
            }
        ]*

        '{'
        <nibble( $¢.cursor_fresh($lang).unbalanced('}') )>
        [ '}' || <.panic: "Unable to parse regex; couldn't find right brace"> ]

        [
        | <?before \h* $$>  # (usual case without comments)
            { @*MEMOS[$¢.pos]<endstmt> = 2; }
        | \h* <?before <[\\,:]>>
        | <.unv>? $$
            { @*MEMOS[$¢.pos]<endstmt> = 2; }
        | {} <.unsp>? { @*MEMOS[$¢.pos]<endargs> = 1; }
        ]
    }

    # statement semantics
    rule statementlist {
        :my $*INVOCANT_OK = 0;
        :dba('statement list')

        [
        | $
        | <?before <[\)\]\}]>>
        | [<statement><eat_terminator> ]*
        ]
    }

    # embedded semis, context-dependent semantics
    rule semilist {
        :my $*INVOCANT_OK = 0;
        :dba('semicolon list')
        [
        | <?before <[\)\]\}]>>
        | [<statement><eat_terminator> ]*
        ]
    }


    token label {
        :my $label;
        <identifier> ':' <?before \s> <.ws>

        [ <?{ $¢.is_name($label = $<identifier>.Str) }>
          <.panic("Illegal redeclaration of '$label'")>
        ]?

        # add label as a pseudo type
        {{ my $*IN_DECL = 'label'; $¢.add_my_name($label); }}

    }

    token statement {
        :my $*endargs = -1;
        :my $*QSIGIL ::= 0;
        <!before <[\)\]\}]> >

        # this could either be a statement that follows a declaration
        # or a statement that is within the block of a code declaration
        <!!{ $*LASTSTATE = $¢.pos; $¢ = %*LANG<MAIN>.bless($¢); }>

        [
        | <label> <statement>
        | <statement_control>
        | <EXPR>
            :dba('statement end')
            [
            || <?{ (@*MEMOS[$¢.pos]<endstmt> // 0) == 2 }>   # no mod after end-line curly
            ||
                :dba('statement modifier')
                <.ws>
                [
                | <statement_mod_loop>
                    {{
                        my $sp = $<EXPR><statement_prefix>;
                        if $sp and $sp<sym> eq 'do' {
                           my $s = $<statement_mod_loop>[0]<sym>;
                           $¢.obs("do...$s" ,"repeat...$s");
                        }
                    }}
                | <statement_mod_cond>
                    :dba('statement modifier loop')
                    [
                    || <?{ (@*MEMOS[$¢.pos]<endstmt> // 0) == 2 }>
                    || <.ws> <statement_mod_loop>?
                    ]
                ]?
            ]
        | <?before ';'>
        | {} <.panic: "Bogus statement">
        ]

        # Is there more on same line after a block?
        [ <?{ (@*MEMOS[@*MEMOS[$¢.pos]<ws>//$¢.pos]<endargs>//0) == 1 }>
            \h*
            <!before ';' | ')' | ']' | '}' >
            <!infixstopper>
            <.panic: "Missing semicolon or comma after block">
        ]?
    }

    token eat_terminator {
        [
        || ';' [ <?before $> { $*ORIG ~~ s/\;$/ /; } ]?
        || <?{ @*MEMOS[$¢.pos]<endstmt> }> <.ws>
        || <?terminator>
        || $
        || <?stopper>
        || {{ if @*MEMOS[$¢.pos]<ws> { $¢.pos = @*MEMOS[$¢.pos]<ws>; } }}   # undo any line transition
            <.panic: "Confused">
        ]
    }

    #####################
    # statement control #
    #####################

    token statement_control:need {
        :my $longname;
        <sym>:s
        [
        |<version>
        |<module_name>
            {{
                my $*IN_DECL = 'use';
                my $*SCOPE = 'use';
                $longname = $<module_name>[*-1]<longname>;
                $¢.do_need($longname);
            }}
        ] ** ','
    }

    token statement_control:import {
        :my $longname;
        :my $*IN_DECL = 'use';
        :my $*SCOPE = 'use';
        <sym> <.ws>
        <term>
        [
        || <.spacey> <arglist>
            {{
                $¢.do_import($<term>, $<arglist>);
            }}
        || {{ $¢.do_import($<term>, ''); }}
        ]
        <.ws>
    }

    token statement_control:use {
        :my $longname;
        :my $*IN_DECL = 'use';
        :my $*SCOPE = 'use';
        <sym> <.ws>
        [
        | <version>
        | <module_name>
            {{
                $longname = $<module_name><longname>;
            }}
            [
            || <.spacey> <arglist>
                {{
                    $¢.do_use($longname, $<arglist>);
                }}
            || {{ $¢.do_use($longname, ''); }}
            ]
        ]
        <.ws>
    }


    token statement_control:no {
        <sym> <.ws>
        <module_name>[<.spacey><arglist>]?
        <.ws>
    }


    token statement_control:if {
        <sym> :s
        <xblock>
        [
            [ <!before 'else'\s*'if'> || <.panic: "Please use 'elsif'"> ]
            'elsif'<?spacey> <elsif=.xblock>
        ]*
        [
            'else'<?spacey> <else=.pblock>
        ]?
    }


    token statement_control:unless {
        <sym> :s
        <xblock>
        [ <!before 'else'> || <.panic: "unless does not take \"else\" in Perl 6; please rewrite using \"if\""> ]
    }


    token statement_control:while {
        <sym> :s
        [ <?before '(' ['my'? '$'\w+ '=']? '<' '$'?\w+ '>' ')'>   #'
            <.panic: "This appears to be Perl 5 code"> ]?
        <xblock>
    }


    token statement_control:until {
        <sym> :s
        <xblock>
    }


    token statement_control:repeat {
        <sym> :s
        [
            | $<wu>=['while'|'until']<.spacey>
              <xblock>
            | <pblock>
              $<wu>=['while'|'until'][<.spacey>||<.panic: "Whitespace required after keyword">] <EXPR>
        ]
    }

    token statement_control:loop {
        <sym> <.ws>
        $<eee> = (
            '(' [ :s
                <e1=.EXPR>? ';'
                <e2=.EXPR>? ';'
                <e3=.EXPR>?
            ')'||<.panic: "Malformed loop spec">]
            [ <?before '{' > <.panic: "Whitespace required before block"> ]?
        )? <.ws>
        <block>
    }


    token statement_control:for {
        <sym> :s
        [ <?before 'my'? '$'\w+ '(' >
            <.panic: "This appears to be Perl 5 code"> ]?
        [ <?before '(' <.EXPR>? ';' <.EXPR>? ';' <.EXPR>? ')' >
            <.obs('C-style "for (;;)" loop', '"loop (;;)"')> ]?
        <xblock>
    }

    token statement_control:given {
        <sym> :s
        <xblock>
    }
    token statement_control:when {
        <sym> :s
        <xblock>
    }
    rule statement_control:default {<sym> <block> }

    token statement_prefix:BEGIN   { <sym> <blast> }
    token statement_prefix:CHECK   { <sym> <blast> }
    token statement_prefix:INIT    { <sym> <blast> }
    token statement_prefix:START   { <sym> <blast> }
    token statement_prefix:ENTER   { <sym> <blast> }
    token statement_prefix:FIRST   { <sym> <blast> }

    token statement_prefix:END     { <sym> <blast> }
    token statement_prefix:LEAVE   { <sym> <blast> }
    token statement_prefix:KEEP    { <sym> <blast> }
    token statement_prefix:UNDO    { <sym> <blast> }
    token statement_prefix:NEXT    { <sym> <blast> }
    token statement_prefix:LAST    { <sym> <blast> }
    token statement_prefix:PRE     { <sym> <blast> }
    token statement_prefix:POST    { <sym> <blast> }

    rule statement_control:CATCH   {<sym> <block> }
    rule statement_control:CONTROL {<sym> <block> }
    rule statement_control:TEMP    {<sym> <block> }

    #######################
    # statement modifiers #
    #######################

    rule modifier_expr { <EXPR> }

    rule statement_mod_cond:if     {<sym> <modifier_expr> }
    rule statement_mod_cond:unless {<sym> <modifier_expr> }
    rule statement_mod_cond:when   {<sym> <modifier_expr> }

    rule statement_mod_loop:while {<sym> <modifier_expr> }
    rule statement_mod_loop:until {<sym> <modifier_expr> }

    rule statement_mod_loop:for   {<sym> <modifier_expr> }
    rule statement_mod_loop:given {<sym> <modifier_expr> }

    ################
    # module names #
    ################

    token def_module_name {
        <longname>
        [ :dba('generic role')
            <?before '['>
            <?{ ($*PKGDECL//'') eq 'role' }>
            <.newpad>
            '[' ~ ']' <signature>
            { $*IN_DECL = ''; }
            <.finishpad>
        ]?
    }

    token module_name:normal {
        <longname>
        [ <?before '['> :dba('generic role') '[' ~ ']' <arglist> ]?
    }

    token module_name:deprecated { 'v6-alpha' }

    token vnum {
        \d+ | '*'
    }

    token version:sym<v> {
        'v' <?before \d+> :: <vnum> ** '.' '+'?
    }

    ###############
    # Declarators #
    ###############

    token variable_declarator {
        :my $*IN_DECL = 'variable';
        :my $*DECLARAND;
        <variable>
        { $¢.add_variable($<variable>.Str); $*IN_DECL = ''; }
        [   # Is it a shaped array or hash declaration?
          #  <?{ $<sigil> eq '@' | '%' }>
            <.unsp>?
            $<shape> = [
            | '(' ~ ')' <signature>
            | :dba('shape definition') '[' ~ ']' <semilist>
            | :dba('shape definition') '{' ~ '}' <semilist>
            | <?before '<'> <postcircumfix>
            ]*
        ]?
        <.ws>

        <trait>*
        <.getdecl>
    }

    rule scoped ($*SCOPE) {
        :dba('scoped declarator')
        [
        | <declarator>
        | <regex_declarator>
        | <package_declarator>
        | [<typename> ]+
            {
                my $t = $<typename>;
                @$t > 1 and $¢.panic("Multiple prefix constraints not yet supported");
                $*OFTYPE = $t[0];
            }
            <multi_declarator>
        | <multi_declarator>
        ]
        || <?before <[A..Z]>><longname>{{
                my $t = $<longname>.Str;
                if not $¢.is_known($t) {
                    $¢.panic("In \"$*SCOPE\" declaration, typename $t must be predeclared (or marked as declarative with :: prefix)");
                }
            }}
            <!> # drop through
        || <.panic: "Malformed $*SCOPE">
    }


    token scope_declarator:my        { <sym> <scoped('my')> }
    token scope_declarator:our       { <sym> <scoped('our')> }
    token scope_declarator:anon      { <sym> <scoped('anon')> }
    token scope_declarator:state     { <sym> <scoped('state')> }
    token scope_declarator:has       { <sym> <scoped('has')> }
    token scope_declarator:augment   { <sym> <scoped('augment')> }
    token scope_declarator:supersede { <sym> <scoped('supersede')> }


    token package_declarator:class {
        :my $*PKGDECL ::= 'class';
        <sym> <package_def>
    }

    token package_declarator:grammar {
        :my $*PKGDECL ::= 'grammar';
        <sym> <package_def>
    }

    token package_declarator:module {
        :my $*PKGDECL ::= 'module';
        <sym> <package_def>
    }

    token package_declarator:package {
        :my $*PKGDECL ::= 'package';
        <sym> <package_def>
    }

    token package_declarator:role {
        :my $*PKGDECL ::= 'role';
        <sym> <package_def>
    }

    token package_declarator:knowhow {
        :my $*PKGDECL ::= 'knowhow';
        <sym> <package_def>
    }

    token package_declarator:slang {
        :my $*PKGDECL ::= 'slang';
        <sym> <package_def>
    }

    token package_declarator:require {   # here because of declarational aspects
        <sym> <.ws>
        [
        || <module_name> <EXPR>?
        || <EXPR>
        ]
    }

    token package_declarator:trusts {
        <sym> <.ws>
        <module_name>
    }

    token package_declarator:does {
        <sym>:s
        <typename>
    }

    rule package_def {
        :my $longname;
        :my $*IN_DECL = 'package';
        :my $*DECLARAND;
        :my $*NEWPKG;
        :my $*NEWPAD;
        { $*SCOPE ||= 'our'; }
        [
            [
                <def_module_name>{
                    $longname = $<def_module_name>[0]<longname>;
                    $¢.add_name($longname.Str);
                }
            ]?
            <trait>*
            <.getdecl>
            [
            || <?before '{'>
                [
                :temp $*CURPKG;
                {{
                    # figure out the actual full package name (nested in outer package)
                    if $longname and $*NEWPKG {
                        my $shortname = $longname.<name>.Str;
                        if $*SCOPE eq 'our' {
                            $*CURPKG = $*NEWPKG // $*CURPKG.{$shortname ~ '::'};
                            say "added our " ~ $*CURPKG.id if $*DEBUG +& DEBUG::symtab;
                        }
                        else {
                            $*CURPKG = $*NEWPKG // $*CURPKG.{$shortname ~ '::'};
                            say "added my " ~ $*CURPKG.id if $*DEBUG +& DEBUG::symtab;
                        }
                    }
                    $*begin_compunit = 0;
                }}
                <block>
                ]
            || <?before ';'>
                [
                || <?{ $*begin_compunit }>
                    {{
                        $longname orelse $¢.panic("Compilation unit cannot be anonymous");
                        my $shortname = $longname.<name>.Str;
                        $*CURPKG = $*NEWPKG // $*CURPKG.{$shortname ~ '::'};
                        $*begin_compunit = 0;

                        # throw out null core when compiling the real CORE
                        if $shortname eq 'CORE' and $*CORE.id ~~ /NULL/ {
                            $*UNIT<OUTER::> = [''];
                            $*CORE = $*UNIT;
                            $*SETTING = $*UNIT;
                            $ALL = {
                                CORE => $*UNIT,
                                SETTING => $*UNIT,
                                $*UNIT.id => $*UNIT,
                            };
                        }
                    }}
                || <.panic: "Too late for semicolon form of " ~ $*PKGDECL ~ " definition">
                ]
            || <.panic: "Unable to parse " ~ $*PKGDECL ~ " definition">
            ]
        ] || <.panic: "Malformed $*PKGDECL">
    }

    token declarator {
        [
        | <variable_declarator>
        | '(' ~ ')' <signature> <trait>*
        | <routine_declarator>
        | <regex_declarator>
        | <type_declarator>
        ]
    }

    token multi_declarator:multi {
        :my $*MULTINESS = 'multi';
        <sym> <.ws> [ <declarator> || <routine_def> || <.panic: 'Malformed multi'> ]
    }
    token multi_declarator:proto {
        :my $*MULTINESS = 'proto';
        <sym> <.ws> [ <declarator> || <routine_def> || <.panic: 'Malformed proto'> ]
    }
    token multi_declarator:only {
        :my $*MULTINESS = 'only';
        <sym> <.ws> [ <declarator> || <routine_def> || <.panic: 'Malformed only'> ]
    }
    token multi_declarator:null {
        :my $*MULTINESS = '';
        <declarator>
    }

    token routine_declarator:sub       { <sym> <routine_def> }
    token routine_declarator:method    { <sym> <method_def> }
    token routine_declarator:submethod { <sym> <method_def> }
    token routine_declarator:macro     { <sym> <macro_def> }

    token regex_declarator:regex { <sym>       <regex_def> }
    token regex_declarator:token { <sym>       <regex_def> }
    token regex_declarator:rule  { <sym>       <regex_def> }

    rule multisig {
        :my $signum = 0;
        :dba('signature')
        [
            ':'?'(' ~ ')' <signature(++$signum)>
        ]
        ** '|'
    }

    method checkyada {
        try {
            my $startsym = self.<blockoid><statementlist><statement>[0]<EXPR><sym> // '';
            if $startsym eq '...' or $startsym eq '!!!' or $startsym eq '???' {
                $*DECLARAND<stub> = 1;
            }
        };
        return self;
    }

    rule routine_def () {
        :temp $*CURPAD;
        :my $*IN_DECL = 'routine';
        :my $*DECLARAND;
        [
            [ $<sigil>=['&''*'?] <deflongname>? | <deflongname> ]?
            <.newpad(1)>
            [ <multisig> | <trait> ]*
            <!{
                $*IN_DECL = '';
            }>
            <blockoid>:!s
            <.checkyada>
            <.getsig>
            <.getdecl>
        ] || <.panic: "Malformed routine">
    }

    rule method_def () {
        :temp $*CURPAD;
        :my $*IN_DECL = 'method';
        :my $*DECLARAND;
        <.newpad(1)>
        [
            [
            | <[ ! ^ ]>?<longname> [ <multisig> | <trait> ]*
            | <multisig> <trait>*
            | <sigil> '.'
                :dba('subscript signature')
                [
                | '(' ~ ')' <signature>
                | '[' ~ ']' <signature>
                | '{' ~ '}' <signature>
                | <?before '<'> <postcircumfix>
                ]
                <trait>*
            | <?>
            ]
            { $*IN_DECL = ''; }
            <blockoid>:!s
            <.checkyada>
            <.getsig>
            <.getdecl>
        ] || <.panic: "Malformed method">
    }

    rule regex_def () {
        :temp $*CURPAD;
        :my $*IN_DECL = 'regex';
        :my $*DECLARAND;
        [
            [ '&'<deflongname>? | <deflongname> ]?
            <.newpad(1)>
            [ [ ':'?'(' <signature(1)> ')'] | <trait> ]*
            { $*IN_DECL = ''; }
            <.finishpad>
            <regex_block>:!s
            <.getsig>
            <.getdecl>
        ] || <.panic: "Malformed regex">
    }

    rule macro_def () {
        :temp $*CURPAD;
        :my $*IN_DECL = 'macro';
        :my $*DECLARAND;
        [
            [ '&'<deflongname>? | <deflongname> ]?
            <.newpad(1)>
            [ <multisig> | <trait> ]*
            <!{
                $*IN_DECL = '';
            }>
            { $*IN_DECL = ''; }
            <blockoid>:!s
            <.checkyada>
            <.getsig>
            <.getdecl>
        ] || <.panic: "Malformed macro">
    }

    rule trait {
        :my $*IN_DECL = 0;
        [
        | <trait_mod>
        | <colonpair>
        ]
    }

    token trait_mod:is {
        <sym>:s <longname><circumfix>?  # e.g. context<rw> and Array[Int]
        {{
            if $*DECLARAND {
                my $traitname = $<longname>.Str;
                # XXX eventually will use multiple dispatch
                $*DECLARAND{$traitname} = self.gettrait($traitname, $<circumfix>);
            }
        }}
    }
    token trait_mod:hides {
        <sym>:s <module_name>
    }
    token trait_mod:does {
        :my $*PKGDECL ::= 'role';
        <sym>:s <module_name>
    }
    token trait_mod:will {
        <sym>:s <identifier> <pblock>
    }

    token trait_mod:of {
        ['of'|'returns']:s <typename>
        [ <?{ $*OFTYPE }> <.panic("Extra 'of' type; already declared as type " ~ $*OFTYPE.Str)> ]?
        { $*OFTYPE = $<typename>; }
    }
    token trait_mod:as      { <sym>:s <typename> }
    token trait_mod:handles { <sym>:s <term> }

    #########
    # Nouns #
    #########

    # (for when you want to tell EXPR that infix already parsed the term)
    token nullterm {
        <?>
    }

    token nulltermish {
        :dba('null term')
        [
        | <?stdstopper>
        | <term=.termish>
            {
                $¢.<PRE>  = $<term><PRE>:delete;
                $¢.<POST> = $<term><POST>:delete;
                $¢.<~CAPS> = $<term><~CAPS>;
            }
        | <?>
        ]
    }

    token termish {
        :my $*SCOPE = "";
        :my $*OFTYPE;
        :my $*VAR;
        :dba('prefix or term')
        [
        | <PRE> [ <!{ my $p = $<PRE>; my @p = @$p; @p[*-1]<O><term> and $<term> = pop @$p }> <PRE> ]*
            [ <?{ $<term> }> || <term> ]
        | <term>
        ]

        # also queue up any postfixes
        :dba('postfix')
        [
        || <?{ $*QSIGIL }>
            [
            || <?{ $*QSIGIL eq '$' }> [ <POST>+! <?after <[ \] } > ) ]> > ]?
            ||                          <POST>+! <?after <[ \] } > ) ]> > 
            || { $*VAR = 0; }
            ]
        || <!{ $*QSIGIL }>
            <POST>*
        ]
        {
            self.check_variable($*VAR) if $*VAR;
            $¢.<~CAPS> = $<term><~CAPS>;
        }
    }

    token term:fatarrow           { <fatarrow> }
    token term:variable           { <variable> { $*VAR = $<variable> } }
    token term:package_declarator { <package_declarator> }
    token term:scope_declarator   { <scope_declarator> }
    token term:multi_declarator   { <?before 'multi'|'proto'|'only'> <multi_declarator> }
    token term:routine_declarator { <routine_declarator> }
    token term:regex_declarator   { <regex_declarator> }
    token term:type_declarator    { <type_declarator> }
    token term:circumfix          { <circumfix> }
    token term:dotty              { <dotty> }
    token term:value              { <value> }
    token term:capterm            { <capterm> }
    token term:sigterm            { <sigterm> }
    token term:statement_prefix   { <statement_prefix> }
    token term:colonpair          { [ <colonpair> <.ws> ]+ }

    token fatarrow {
        <key=.identifier> \h* '=>' <.ws> <val=.EXPR(item %item_assignment)>
    }

    token colonpair {
        :my $key;
        :my $value;

        ':'
        :dba('colon pair')
        [
        | '!' <identifier> [ <[ \[ \( \< \{ ]> <.panic: "Argument not allowed on negated pair"> ]?
            { $key = $<identifier>.Str; $value = 0; }
        | $<num> = [\d+] <identifier> [ <[ \[ \( \< \{ ]> <.panic: "2nd argument not allowed on pair"> ]?
        | <identifier>
            { $key = $<identifier>.Str; }
            [
            || <.unsp>? :dba('pair value') <circumfix> { $value = $<circumfix>; }
            || { $value = 1; }
            ]
        | :dba('signature') '(' ~ ')' <fakesignature>
        | <circumfix>
            { $key = ""; $value = $<circumfix>; }
        | $<var> = (<sigil> {} <twigil>? <desigilname>)
            { $key = $<var><desigilname>.Str; $value = $<var>; }
        ]
        { $<k> = $key; $<v> = $value; }
    }

    # Most of these special variable rules are there simply to catch old p5 brainos

    token special_variable:sym<$¢> { <sym> }

    token special_variable:sym<$!> { <sym> <!before \w> }

    token special_variable:sym<$!{ }> {
        ( '$!{' :: (.*?) '}' )
        <.obs($0.Str ~ " variable", 'smart match against $!')>
    }

    token special_variable:sym<$/> {
        <sym>
        # XXX assuming nobody ever wants to assign $/ directly anymore...
        [ <?before \h* '=' <![=]> >
            <.obs('$/ variable as input record separator',
                 "the filehandle's :irs attribute")>
        ]?
    }

    token special_variable:sym<$~> {
        <sym> :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$~ variable', 'Form module')>
    }

    token special_variable:sym<$`> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$` variable', 'explicit pattern before <(')>
    }

    token special_variable:sym<$@> {
        <sym> ::
        <.obs('$@ variable as eval error', '$!')>
    }

    token special_variable:sym<$#> {
        <sym> ::
        [
        || (\w+) <.obs("\$#" ~ $0.Str ~ " variable", '@' ~ $0.Str ~ '.end')>
        || <.obs('$# variable', '.fmt')>
        ]
    }
    token special_variable:sym<$$> {
        <sym> <!alpha> :: <?before \s | ',' | <terminator> >
        <.obs('$$ variable', '$*PID')>
    }
    token special_variable:sym<$%> {
        <sym> ::
        <.obs('$% variable', 'Form module')>
    }

    # Note: this works because placeholders are restricted to lowercase
    token special_variable:sym<$^X> {
        <sigil> '^' $<letter> = [<[A..Z]>] \W
        <.obscaret($<sigil>.Str ~ '^' ~ $<letter>.Str, $<sigil>.Str, $<letter>.Str)>
    }

    token special_variable:sym<$^> {
        <sym> :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$^ variable', 'Form module')>
    }

    token special_variable:sym<$&> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$& variable', '$/ or $()')>
    }

    token special_variable:sym<$*> {
        <sym> :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$* variable', '^^ and $$')>
    }

    token special_variable:sym<$)> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$) variable', '$*EGID')>
    }

    token special_variable:sym<$-> {
        <sym> :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$- variable', 'Form module')>
    }

    token special_variable:sym<$=> {
        <sym> :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$= variable', 'Form module')>
    }

    token special_variable:sym<@+> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('@+ variable', '.to method')>
    }

    token special_variable:sym<%+> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('%+ variable', '.to method')>
    }

    token special_variable:sym<$+[ ]> {
        '$+['
        <.obs('@+ variable', '.to method')>
    }

    token special_variable:sym<@+[ ]> {
        '@+['
        <.obs('@+ variable', '.to method')>
    }

    token special_variable:sym<@+{ }> {
        '@+{'
        <.obs('%+ variable', '.to method')>
    }

    token special_variable:sym<@-> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('@- variable', '.from method')>
    }

    token special_variable:sym<%-> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('%- variable', '.from method')>
    }

    token special_variable:sym<$-[ ]> {
        '$-['
        <.obs('@- variable', '.from method')>
    }

    token special_variable:sym<@-[ ]> {
        '@-['
        <.obs('@- variable', '.from method')>
    }

    token special_variable:sym<%-{ }> {
        '@-{'
        <.obs('%- variable', '.from method')>
    }

    token special_variable:sym<$+> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$+ variable', 'Form module')>
    }

    token special_variable:sym<${^ }> {
        <sigil> '{^' :: $<text>=[.*?] '}'
        <.obscaret($<sigil>.Str ~ '{^' ~ $<text>.Str ~ '}', $<sigil>.Str, $<text>.Str)>
    }

    # XXX should eventually rely on multi instead of nested cases here...
    method obscaret (Str $var, Str $sigil, Str $name) {
        my $repl;
        given $sigil {
            when '$' {
                given $name {
                    when 'MATCH'         { $repl = '$/' }
                    when 'PREMATCH'      { $repl = 'an explicit pattern before <(' }
                    when 'POSTMATCH'     { $repl = 'an explicit pattern after )>' }
                    when 'ENCODING'      { $repl = '$?ENCODING' }
                    when 'UNICODE'       { $repl = '$?UNICODE' }  # XXX ???
                    when 'TAINT'         { $repl = '$*TAINT' }
                    when 'OPEN'          { $repl = 'filehandle introspection' }
                    when 'N'             { $repl = '$-1' } # XXX ???
                    when 'L'             { $repl = 'Form module' }
                    when 'A'             { $repl = 'Form module' }
                    when 'E'             { $repl = '$!.extended_os_error' }
                    when 'C'             { $repl = 'COMPILING namespace' }
                    when 'D'             { $repl = '$*DEBUGGING' }
                    when 'F'             { $repl = '$*SYSTEM_FD_MAX' }
                    when 'H'             { $repl = '$?FOO variables' }
                    when 'I'             { $repl = '$*INPLACE' } # XXX ???
                    when 'O'             { $repl = '$?OS or $*OS' }
                    when 'P'             { $repl = 'whatever debugger Perl 6 comes with' }
                    when 'R'             { $repl = 'an explicit result variable' }
                    when 'S'             { $repl = 'the context function' } # XXX ???
                    when 'T'             { $repl = '$*BASETIME' }
                    when 'V'             { $repl = '$*PERL_VERSION' }
                    when 'W'             { $repl = '$*WARNING' }
                    when 'X'             { $repl = '$*EXECUTABLE_NAME' }
                    when *               { $repl = "a global form such as $sigil*$name" }
                }
            }
            when '%' {
                given $name {
                    when 'H'             { $repl = '$?FOO variables' }
                    when *               { $repl = "a global form such as $sigil*$name" }
                }
            }
            when * { $repl = "a global form such as $sigil*$name" }
        };
        return self.obs("$var variable", $repl);
    }

    token special_variable:sym<::{ }> {
        '::' <?before '{'>
    }

    regex special_variable:sym<${ }> {
        <sigil> '{' {} $<text>=[.*?] '}'
        {{
            my $sigil = $<sigil>.Str;
            my $text = $<text>.Str;
            my $bad = $sigil ~ '{' ~ $text ~ '}';
            $text = $text - 1 if $text ~~ /^\d+$/;
            if $text !~~ /^(\w|\:)+$/ {
                $¢.obs($bad, $sigil ~ '(' ~ $text ~ ')');
            }
            elsif $*QSIGIL {
                $¢.obs($bad, '{' ~ $sigil ~ $text ~ '}');
            }
            else {
                $¢.obs($bad, $sigil ~ $text);
            }
        }}
    }

    token special_variable:sym<$[> {
        <sym> :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$[ variable', 'user-defined array indices')>
    }

    token special_variable:sym<$]> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$] variable', '$*PERL_VERSION')>
    }

    token special_variable:sym<$\\> {
        <sym> :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$\\ variable', "the filehandle's :ors attribute")>
    }

    token special_variable:sym<$|> {
        <sym> :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$| variable', ':autoflush on open')>
    }

    token special_variable:sym<$:> {
        <sym> <?before <[\x20\t\n\],=)}]> >
        <.obs('$: variable', 'Form module')>
    }

    token special_variable:sym<$;> {
        <sym> :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$; variable', 'real multidimensional hashes')>
    }

    token special_variable:sym<$'> { #'
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$' ~ "'" ~ 'variable', "explicit pattern after )\x3E")>
    }

    token special_variable:sym<$"> {
        <sym> <!{ $*QSIGIL }>
        :: <?before \s | ',' | '=' | <terminator> >
        <.obs('$" variable', '.join() method')>
    }

    token special_variable:sym<$,> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$, variable', ".join() method")>
    }

    token special_variable:sym['$<'] {
        <sym> :: <!before \s* \w+ \s* '>' >
        <.obs('$< variable', '$*UID')>
    }

    token special_variable:sym«\$>» {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$> variable', '$*EUID')>
    }

    token special_variable:sym<$.> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$. variable', "the filehandle's .line method")>
    }

    token special_variable:sym<$?> {
        <sym> :: <?before \s | ',' | <terminator> >
        <.obs('$? variable as child error', '$!')>
    }

    # desigilname should only follow a sigil/twigil

    token desigilname {
        [
        | <?before '$' > <variable> { $*VAR = $<variable> }
        | <longname>
        ]
    }

    token variable {
        :my $*IN_META = 0;
        :my $sigil = '';
        :my $twigil = '';
        :my $name;
        <?before <sigil> {
            $sigil = $<sigil>.Str;
            $*LEFTSIGIL ||= $sigil;
        }> {}
        [
        || <sigil> <twigil>? <?before '::' [ '{' | '<' | '(' ]> <longname> # XXX
        || '&'
            [
            | <twigil>? <sublongname> { $name = $<sublongname>.Str }
            | :dba('infix noun') '[' ~ ']' <infixish(1)>
            ]
        || '$::' <name>? # XXX
        || '$:' <name> # XXX
        || [
            | <sigil> <twigil>? <desigilname> { $name = $<desigilname>.Str }
            | <special_variable>
            | <sigil> $<index>=[\d+]
            # Note: $() can also parse as contextualizer in an expression; should have same effect
            | <sigil> <?before '<' | '('> <postcircumfix>
            | <sigil> <?{ $*IN_DECL }>
            | <?> {{
                if $*QSIGIL {
                    return ();
                }
                else {
                    $¢.panic("Anonymous variable requires declarator");
                }
              }}
            ]
        ]

        { my $t = $<twigil>; $twigil = $t.[0].Str if @$t; }
        [ <?{ $twigil eq '.' }>
            [<.unsp> | '\\' | <?> ] <?before '('> <postcircumfix>
        ]?
    }



    token deflongname {
        :dba('new name to be defined')
        <name>
        [
        | <colonpair>+ { $¢.add_macro($<name>) if $*IN_DECL; }
        | { $¢.add_routine($<name>.Str) if $*IN_DECL; }
        ]
    }

    token subshortname {
        [
        | <category>
            [ <colonpair>+ { $¢.add_macro($<category>) if $*IN_DECL; } ]?
        | <desigilname>
        ]
    }

    token sublongname {
        <subshortname> <sigterm>?
    }

    token value:quote   { <quote> }
    token value:number  { <number> }
    token value:version { <version> }

    # Note: call this only to use existing type, not to declare type
    token typename {
        [
        | '::?'<identifier>                 # parse ::?CLASS as special case
        | <longname>
          <?{{
            my $longname = $<longname>.Str;
            if substr($longname, 0, 2) eq '::' {
                $¢.add_my_name(substr($longname, 2));
            }
            else {
                $¢.is_name($longname)
            }
          }}>
        ]
        # parametric type?
        <.unsp>? [ <?before '['> <param=.postcircumfix> ]?
        <.unsp>? [ <?before '{'> <whence=.postcircumfix> ]?
        [<.ws> 'of' <.ws> <typename> ]?
    }

    token numish {
        [
        | 'NaN' »
        | <[+\-]>?
            [
            | <integer>
            | <dec_number>
            | <rad_number>
            | 'Inf' »
            ]
        ]
    }

    token number:rational { <nu=.integer>'/'<de=.integer> }
    token number:complex { <re=.numish><?before <[+\-]>\d><im=.numish>'\\'?'i' | <im=.numish>'\\'?'i' }
    token number:numish { <numish> }

    ##########
    # Quotes #
    ##########

    token sibble ($l, $lang2) {
        :my ($lang, $start, $stop);
        <babble($l)>
        { my $B = $<babble><B>; ($lang,$start,$stop) = @$B; }

        $start <left=.nibble($lang)> [ $stop || <.panic: "Couldn't find terminator $stop"> ]
        [ <?{ $start ne $stop }>
            <.ws>
            [ <infixish> || <panic: "Missing assignment operator"> ]
            [ <?{ $<infixish>.Str eq '=' || $<infixish>.<infix_postfix_meta_operator> }> || <.panic: "Malformed assignment operator"> ]
            <.ws>
            <right=EXPR(item %item_assignment)>
        || 
            { $lang = $lang2.unbalanced($stop); }
            <right=.nibble($lang)> $stop
        ]
    }

    token tribble ($l, $lang2 = $l) {
        :my ($lang, $start, $stop);
        <babble($l)>
        { my $B = $<babble><B>; ($lang,$start,$stop) = @$B; }

        $start <left=.nibble($lang)> [ $stop || <.panic: "Couldn't find terminator $stop"> ]
        [ <?{ $start ne $stop }>
            <.ws> <quibble($lang2)>
        || 
            { $lang = $lang2.unbalanced($stop); }
            <right=.nibble($lang)> $stop
        ]
    }

    token quasiquibble ($l) {
        :temp %*LANG;
        :my ($lang, $start, $stop);
        :my $*QUASIMODO = 0; # :COMPILING sets true
        <babble($l)>
        {
            my $B = $<babble><B>;
            ($lang,$start,$stop) = @$B;
            %*LANG<MAIN> = $lang;
        }

        [
        || <?{ $start eq '{' }> [ :lang($lang) <block> ]
        || [ :lang($lang) <starter> <statementlist> [ <stopper> || <.panic: "Couldn't find terminator $stop"> ] ]
        ]
    }

    token quote:sym<//>   {
        '/'\s*'/' <.panic: "Null regex not allowed">
    }

    token quote:sym</ />   {
        '/' <nibble( $¢.cursor_fresh( %*LANG<Regex> ).unbalanced("/") )> [ '/' || <.panic: "Unable to parse regex; couldn't find final '/'"> ]
        <.old_rx_mods>?
    }

    # handle composite forms like qww
    token quote:qq {
        :my $qm;
        'qq'
        [
        | <quote_mod> » <!before '('> { $qm = $<quote_mod>.Str } <.ws> <quibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:qq).tweak($qm => 1))>
        | » <!before '('> <.ws> <quibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:qq))>
        ]
    }
    token quote:q {
        :my $qm;
        'q'
        [
        | <quote_mod> » <!before '('> { $qm = $<quote_mod>.Str } <quibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:q).tweak($qm => 1))>
        | » <!before '('> <.ws> <quibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:q))>
        ]
    }

    token quote:Q {
        :my $qm;
        'Q'
        [
        | <quote_mod> » <!before '('> { $qm = $<quote_mod>.Str } <quibble($¢.cursor_fresh( %*LANG<Q> ).tweak($qm => 1))>
        | » <!before '('> <.ws> <quibble($¢.cursor_fresh( %*LANG<Q> ))>
        ]
    }

    token quote_mod:w  { <sym> }
    token quote_mod:ww { <sym> }
    token quote_mod:p  { <sym> }
    token quote_mod:x  { <sym> }
    token quote_mod:to { <sym> }
    token quote_mod:s  { <sym> }
    token quote_mod:a  { <sym> }
    token quote_mod:h  { <sym> }
    token quote_mod:f  { <sym> }
    token quote_mod:c  { <sym> }
    token quote_mod:b  { <sym> }

    token quote:rx {
        <sym> » <!before '('>
        <quibble( $¢.cursor_fresh( %*LANG<Regex> ) )>
        <!old_rx_mods>
    }

    token quote:m  {
        <sym> » <!before '('>
        <quibble( $¢.cursor_fresh( %*LANG<Regex> ) )>
        <!old_rx_mods>
    }

    token quote:mm {
        <sym> » <!before '('>
        <quibble( $¢.cursor_fresh( %*LANG<Regex> ).tweak(:s))>
        <!old_rx_mods>
    }

    token quote:s {
        <sym> » <!before '('>
        <pat=.sibble( $¢.cursor_fresh( %*LANG<Regex> ), $¢.cursor_fresh( %*LANG<Q> ).tweak(:qq))>
        <!old_rx_mods>
    }

    token quote:ss {
        <sym> » <!before '('>
        <pat=.sibble( $¢.cursor_fresh( %*LANG<Regex> ).tweak(:s), $¢.cursor_fresh( %*LANG<Q> ).tweak(:qq))>
        <!old_rx_mods>
    }
    token quote:tr {
        <sym> » <!before '('> <pat=.tribble( $¢.cursor_fresh( %*LANG<Q> ).tweak(:q))>
        <!old_tr_mods>
    }

    token old_rx_mods {
        <!after \s>
        (< i g s m x c e >+) 
        {{
            given $0.Str {
                $_ ~~ /i/ and $¢.worryobs('/i',':i');
                $_ ~~ /g/ and $¢.worryobs('/g',':g');
                $_ ~~ /s/ and $¢.worryobs('/s','^^ and $$ anchors');
                $_ ~~ /m/ and $¢.worryobs('/m','. or \N');
                $_ ~~ /x/ and $¢.worryobs('/x','normal default whitespace');
                $_ ~~ /c/ and $¢.worryobs('/c',':c or :p');
                $_ ~~ /e/ and $¢.worryobs('/e','interpolated {...} or s{} = ... form');
                $¢.obs('suffix regex modifiers','prefix adverbs');
            }
        }}
    }

    token old_tr_mods {
        (< c d s ] >+) 
        {{
            given $0.Str {
                $_ ~~ /c/ and $¢.worryobs('/c',':c');
                $_ ~~ /d/ and $¢.worryobs('/g',':d');
                $_ ~~ /s/ and $¢.worryobs('/s',':s');
                $¢.obs('suffix transliteration modifiers','prefix adverbs');
            }
        }}
    }

    token quote:quasi {
        <sym> » <!before '('> <quasiquibble($¢.cursor_fresh( %*LANG<Quasi> ))>
    }

    ###########################
    # Captures and Signatures #
    ###########################

    token capterm {
        '\\'
        [
        | '(' <capture>? ')'
        | <?before \S> <termish>
        | {} <.panic: "You can't backslash that">
        ]
    }

    rule capture {
        :my $*INVOCANT_OK = 1;
        <EXPR>
    }

    token sigterm {
        :dba('signature')
        ':(' ~ ')' <fakesignature>
    }

    rule param_sep { [','|':'|';'|';;'] }

    token fakesignature() {
        :temp $*CURPAD;
        <.newpad>
        <signature>
    }

    token signature ($padsig = 0) {
        :my $*IN_DECL = 'sig';
        :my $*zone = 'posreq';
        :my $startpos = self.pos;
        :my $*MULTINESS = 'only';
        :my $*SIGNUM = $padsig;
        <.ws>
        [
        | <?before '-->' | ')' | ']' | '{' | ':'\s >
        | [ <parameter> || <.panic: "Malformed parameter"> ]
        ] ** <param_sep>
        <.ws>
        { $*IN_DECL = ''; }
        [ '-->' <.ws> <typename> <.ws> ]?
        {{
            $*LEFTSIGIL = '@';
            if $padsig {
                $*CURPAD.<$?SIGNATURE> ~= '|' if $padsig > 1;
                $*CURPAD.<$?SIGNATURE> ~= '(' ~ substr($*ORIG, $startpos, $¢.pos - $startpos) ~ ')';
                $*CURPAD.<!NEEDSIG>:delete;
            }
        }}
    }

    token type_declarator:subset {
        :my $*IN_DECL = 'subset';
        :my $*DECLARAND;
        <sym> :s
        [
            [ <longname> { $¢.add_name($<longname>[0].Str); } ]?
            <trait>*
            [where <EXPR(item %chaining)> ]?    # (EXPR can parse multiple where clauses)
        ] || <.panic: "Malformed subset">
    }

    token type_declarator:enum {
        :my $*IN_DECL = 'enum';
        :my $*DECLARAND;
        <sym> <.ws>
        [ <longname> { $¢.add_name($<longname>[0].Str); } <.ws> ]?
        <trait>* <?before <[ < ( « ]> > <term> <.ws>
            {$¢.add_enum($<longname>, $<term>.Str); }
    }

    token type_declarator:constant {
        :my $*IN_DECL = 'constant';
        :my $*DECLARAND;
        <sym> <.ws>

        [
        | <identifier> { $¢.add_name($<identifier>.Str); }
        | <variable> { $¢.add_variable($<variable>.Str); }
        | <?>
        ]
        { $*IN_DECL = ''; }
        <.ws>

        <trait>*

        [
        || <?before '='>
        || <?before <-[\n=]>*'='> <.panic: "Malformed constant"> # probable initializer later
        || <.panic: "Missing initializer on constant declaration">
        ]

        <.getdecl>
    }


    token type_constraint {
        :my $*IN_DECL = '';
        [
        | <value>
        | <typename>
        | where <.ws> <EXPR(item %chaining)>
        ]
        <.ws>
    }

    rule post_constraint {
        :my $*IN_DECL = '';
        :dba('constraint')
        [
        | '[' ~ ']' <signature>
        | '(' ~ ')' <signature>
        | where <EXPR(item %chaining)>
        ]
    }

    token named_param {
        :my $*GOAL ::= ')';
        ':'
        [
        | <name=.identifier> '(' <.ws>
            [ <named_param> | <param_var> <.ws> ]
            [ ')' || <.panic: "Unable to parse named parameter; couldn't find right parenthesis"> ]
        | <param_var>
        ]
    }

    token param_var {
        :dba('formal parameter')
        [
        | '[' ~ ']' <signature>
        | '(' ~ ')' <signature>
        | <sigil> <twigil>?
            [
                # Is it a longname declaration?
            || <?{ $<sigil>.Str eq '&' }> <?ident> {}
                <name=.sublongname>

            ||  # Is it a shaped array or hash declaration?
                <?{ $<sigil>.Str eq '@' || $<sigil>.Str eq '%' }>
                <name=.identifier>?
                <?before <[ \< \( \[ \{ ]> >
                <postcircumfix>

                # ordinary parameter name
            || <name=.identifier>
            || $<name> = [<[/!]>]

                # bare sigil?
            ]?
            {{
                my $vname = $<sigil>.Str;
                my $t = $<twigil>;
                my $twigil = '';
                $twigil = $t.[0].Str if @$t;
                $vname ~= $twigil;
                my $n = try { $<name>[0].Str } // '';
                $vname ~= $n;
                given $twigil {
                    when '' {
                        self.add_my_name($vname) if $n ne '';
                    }
                    when '.' {
                    }
                    when '!' {
                    }
                    when '*' {
                    }
                    default {
                        self.worry("Illegal to use $twigil twigil in signature");
                    }
                }
            }}
        ]
    }

    token parameter {
        :my $kind;
        :my $quant = '';
        :my $q;
        :my $*DECLARAND;

        [
        | <type_constraint>+
            {{
                my $t = $<type_constraint>;
                my @t = grep { substr($_.Str,0,2) ne '::' }, @$t;
                @t > 1 and $¢.panic("Multiple prefix constraints not yet supported")
            }}
            [
            | '**' <param_var>   { $quant = '**'; $kind = '*'; }
            | '*' <param_var>   { $quant = '*'; $kind = '*'; }
            | '|' <param_var>   { $quant = '|'; $kind = '*'; }
            | '\\' <param_var>  { $quant = '\\'; $kind = '!'; }
            |   [
                | <param_var>   { $quant = ''; $kind = '!'; }
                | <named_param> { $quant = ''; $kind = '*'; }
                ]
                [
                | '?'           { $quant = '?'; $kind = '?' }
                | '!'           { $quant = '!'; $kind //= '!' }
                | <?>
                ]
            | <?> { $quant = ''; $kind = '!' }
            ]

        | '**' <param_var>   { $quant = '**'; $kind = '*'; }
        | '*' <param_var>   { $quant = '*'; $kind = '*'; }
        | '|' <param_var>   { $quant = '|'; $kind = '*'; }
        | '\\' <param_var>  { $quant = '\\'; $kind = '!'; }
        |   [
            | <param_var>   { $quant = ''; $kind = '!'; }
            | <named_param> { $quant = ''; $kind = '*'; }
            ]
            [
            | '?'           { $quant = '?'; $kind = '?' }
            | '!'           { $quant = '!'; $kind //= '!' }
            | <?>
            ]
        | {} <longname> <.panic("Invalid typename " ~ $<longname>.Str)>
        ]

        <trait>*

        <post_constraint>*

        <.getdecl>

        [
            <default_value> {{
                given $quant {
                  when '!' { $¢.panic("Can't put a default on a required parameter") }
                  when '*' { $¢.panic("Can't put a default on a slurpy parameter") }
                  when '**' { $¢.panic("Can't put a default on a slice parameter") }
                  when '|' { $¢.panic("Can't put a default on an slurpy capture parameter") }
                  when '\\' { $¢.panic("Can't put a default on a capture parameter") }
                }
                $kind = '?' if $kind eq '!';
            }}
            [<?before ':' > <.panic: "Can't put a default on the invocant parameter">]?
            [<!before <[,;)\]\{\-]> > <.panic: "Default expression must come last">]?
        ]?
        [<?before ':'> <?{ $kind ne '!' }> <.panic: "Invocant is too exotic">]?

        {
            $<quant> = $quant;
            $<kind> = $kind;
        }

        # enforce zone constraints
        {{
            given $kind {
                when '!' {
                    given $*zone {
                        when 'posopt' {
    $¢.panic("Can't put required parameter after optional parameters");
                        }
                        when 'var' {
    $¢.panic("Can't put required parameter after variadic parameters");
                        }
                    }
                }
                when '?' {
                    given $*zone {
                        when 'posreq' { $*zone = 'posopt' }
                        when 'var' {
    $¢.panic("Can't put optional positional parameter after variadic parameters");
                        }
                    }
                }
                when '*' {
                    $*zone = 'var';
                }
            }
        }}
    }

    rule default_value {
        :my $*IN_DECL = '';
        '=' <EXPR(item %item_assignment)>
    }

    token statement_prefix:sink    { <sym> <blast> }
    token statement_prefix:try     { <sym> <blast> }
    token statement_prefix:quietly { <sym> <blast> }
    token statement_prefix:gather  { <sym> <blast> }
    token statement_prefix:contend { <sym> <blast> }
    token statement_prefix:async   { <sym> <blast> }
    token statement_prefix:maybe   { <sym> <blast> }
    token statement_prefix:lazy    { <sym> <blast> }
    token statement_prefix:do      { <sym> <blast> }

    token statement_prefix:lift    {
        :my $*QUASIMODO = 1;
        <sym> <blast>
    }

    # accepts blocks and statements
    token blast {
        <?before \s> <.ws>
        [
        | <block>
        | <statement>  # creates a dynamic scope but not lexical scope
        ]
    }

    #########
    # Terms #
    #########

    # start playing with the setting stubber
    token term:YOU_ARE_HERE {
        <sym> <.you_are_here>
        <O(|%term)>
    }

    token term:new {
        'new' \h+ <longname> \h* <!before ':'> <.obs("C++ constructor syntax", "method call syntax")>
    }

    token term:sym<::?IDENT> {
        $<sym> = [ '::?' <identifier> ] »
        <O(|%term)>
    }

    token term:sym<Object> {
        <sym> » {}
        <.obs('Object', 'Mu as the "most universal" object type')>
    }

    token term:sym<undef> {
        <sym> » {}
        [ <?before \h*'$/' >
            <.obs('$/ variable as input record separator',
                 "the filehandle's .slurp method")>
        ]?
        [ <?before [ '(' || \h*<sigil><twigil>?\w ] >
            <.obs('undef as a verb', 'undefine function or assignment of Nil')>
        ]?
        <.obs('undef as a value', "something more specific:\n\tMu (the \"most undefined\" type object),\n\tan undefined type object such as Int,\n\tNil as an empty list,\n\t*.notdef as a matcher or method,\n\tAny:U as a type constraint\n\tor fail() as a failure return\n\t   ")>
    }

    token term:sym<proceed>
        { <sym> » <O(|%term)> }

    token term:sym<self>
        { <sym> » <O(|%term)> }

    token term:sym<defer>
        { <sym> » <O(|%term)> }

    token term:rand {
        <sym> »
        [ <?before '('? \h* [\d|'$']> <.obs('rand(N)', 'N.rand or (1..N).pick')> ]?
        [ <?before '()'> <.obs('rand()', 'rand')> ]?
        <O(|%term)>
    }

    token term:sym<*>
        { <sym> <O(|%term)> }

    token term:sym<**>
        { <sym> <O(|%term)> }

    token infix:lambda {
        <?before '{' | '->' > <!{ $*IN_META }> {{
            my $line = $¢.lineof($¢.pos);
            for 'if', 'unless', 'while', 'until', 'for', 'loop', 'given', 'when', 'sub' {
                my $m = %*MYSTERY{$_};
                next unless $m;
                if $line - ($m.<line>//-123) < 5 {
                    if $m.<ctx> eq '(' {
                        $¢.panic($_ ~ '() interpreted as function call at line ' ~ $m.<line> ~
                        "; please use whitespace " ~
                        ($_ eq 'loop' ?? 'around' !! 'instead of') ~
                        " parens\nUnexpected block in infix position (two terms in a row)");
                    }
                    else {
                        $¢.panic("'$_' interpreted as listop at line " ~ $m.<line> ~
                        "; please use 'do' to introduce statement_control:<$_>.\nUnexpected block in infix position (two terms in a row)");
                    }
                }
            }
            return () if $*IN_REDUCE;
            $¢.panic("Unexpected block in infix position (two terms in a row, or previous statement missing semicolon?)");
        }}
        <O(|%term)>
    }

    token circumfix:sigil
        { :dba('contextualizer') <sigil> '(' ~ ')' <semilist> { $*LEFTSIGIL ||= $<sigil>.Str } <O(|%term)> }

    token circumfix:sym<( )>
        { :dba('parenthesized expression') '(' ~ ')' <semilist> <O(|%term)> }

    token circumfix:sym<[ ]>
        { :dba('array composer') '[' ~ ']' <semilist> <O(|%term)> { @*MEMOS[$¢.pos]<acomp> = 1; } }

    #############
    # Operators #
    #############

    token PRE {
        :dba('prefix or meta-prefix')
        [
        | <prefix>
            { $<O> = $<prefix><O>; $<sym> = $<prefix><sym> }
        | <prefix_circumfix_meta_operator>
            { $<O> = $<prefix_circumfix_meta_operator><O>; $<sym> = $<prefix_circumfix_meta_operator>.Str }
        ]
        # XXX assuming no precedence change
        
        <prefix_postfix_meta_operator>*
        <.ws>
    }

    token infixish ($in_meta = $*IN_META) {
        :my $infix;
        :my $*IN_META = $in_meta;
        <!stdstopper>
        <!infixstopper>
        :dba('infix or meta-infix')
        [
        | <colonpair> {
                $<fake> = 1;
                $<sym> = ':';
                %<O><prec> = %item_assignment<prec>;  # actual test is non-inclusive!
                %<O><assoc> = 'unary';
                %<O><dba> = 'adverb';
            }
        |   [
            | :dba('bracketed infix') '[' ~ ']' <infix=.infixish(1)> { $<O> = $<infix><O>; $<sym> = $<infix><sym>; }
            | <infix=infix_circumfix_meta_operator> { $<O> = $<infix><O>; $<sym> = $<infix><sym>; }
            | <infix=infix_prefix_meta_operator>    { $<O> = $<infix><O>; $<sym> = $<infix><sym>; }
            | <infix>                               { $<O> = $<infix><O>; $<sym> = $<infix><sym>; }
            | {} <?dotty> <.panic: "Method call found where infix expected (omit whitespace?)">
            | {} <?postfix> <.panic: "Postfix found where infix expected (omit whitespace?)">
            ]
            [ <?before '='> <?{ $infix = $<infix>; }> <infix_postfix_meta_operator($infix)>
                   { $<O> = $<infix_postfix_meta_operator>[0]<O>; $<sym> = $<infix_postfix_meta_operator>[0]<sym>; }
            ]?

        ]
    }

    # NOTE: Do not add dotty ops beginning with anything other than dot!
    #   Dotty ops have to parse as .foo terms as well, and almost anything
    #   other than dot will conflict with some other prefix.

    # doing fancy as one rule simplifies LTM
    token dotty:sym<.*> {
        ('.' [ <[+*?=]> | '^' '!'? ]) :: <.unspacey> <dottyop>
        { $<sym> = $0.Str; }
        <O(%methodcall)>
    }

    token dotty:sym<.> {
        <sym> <dottyop>
        <O(%methodcall)>
    }

    token privop {
        '!' <methodop>
        <O(%methodcall)>
    }

    token dottyopish {
        <term=.dottyop>
    }

    token dottyop {
        :dba('dotty method or postfix')
        [
        | <methodop>
        | <colonpair>
        | <!alpha> <postop> { $<O> = $<postop><O>; $<sym> = $<postop><sym>; }  # only non-alpha postfixes have dotty form
        ]
    }

    # Note, this rule mustn't do anything irreversible because it's used
    # as a lookahead by the quote interpolator.

    token POST {
        <!stdstopper>

        # last whitespace didn't end here
        <!{ @*MEMOS[$¢.pos]<ws> }>

        [ <.unsp> | '\\' ]?

        [ ['.' <.unsp>?]? <postfix_prefix_meta_operator> <.unsp>? ]*

        :dba('postfix')
        [
        | <dotty>  { $<O> = $<dotty><O>;  $<sym> = $<dotty><sym>;  $<~CAPS> = $<dotty><~CAPS>; }
        | <privop> { $<O> = $<privop><O>; $<sym> = $<privop><sym>; $<~CAPS> = $<privop><~CAPS>; }
        | <postop> { $<O> = $<postop><O>; $<sym> = $<postop><sym>; $<~CAPS> = $<postop><~CAPS>; }
        ]
        { $*LEFTSIGIL = '@'; }
    }

    method can_meta ($op, $meta) {
        !$op<O><fiddly> ||
            self.panic("Can't " ~ $meta ~ " " ~ $op<sym> ~ " because " ~ $op<O><dba> ~ " operators are too fiddly");
        self;
    }

    regex prefix_circumfix_meta_operator:reduce {
        :my $*IN_REDUCE = 1;
        :my $op;
        <?before '['\S+']'>
        $<s> = (
            '['
            [
            || <op=.infixish(1)> <?before ']'>
            || \\<op=.infixish(1)> <?before ']'>
            || <!>
            ]
            ']' ['«'|<?>]
        )
        { $op = $<s><op>; }

        <.can_meta($op, "reduce")>

        [
        || <!{ $op<O><diffy> }>
        || <?{ $op<O><assoc> eq 'chain' }>
        || <.panic("Can't reduce " ~ $op<sym> ~ " because " ~ $op<O><dba> ~ " operators are diffy and not chaining")>
        ]

        <O($op.Opairs, |%list_prefix, assoc => 'unary', uassoc => 'left')>
        { $<sym> = $<s>.Str; }

        [ <?before '('> || <?before \s+ [ <?stdstopper> { $<O><term> = 1 } ]? > || { $<O><term> = 1 } ]
    }

    token prefix_postfix_meta_operator:sym< « >    { <sym> | '<<' }

    token postfix_prefix_meta_operator:sym< » >    {
        [ <sym> | '>>' ]
        # require >>.( on interpolated hypercall so infix:«$s»($a,$b) {...} dwims
        [<!{ $*QSIGIL }> || <!before '('> ]
    }

    token infix_prefix_meta_operator:sym<!> {
        <sym> <!before '!'> {} [ <infixish(1)> || <.panic: "Negation metaoperator not followed by valid infix"> ]

        [
        || <?{ $<infixish>.Str eq '=' }>
           <O(|%chaining)>
           
        || <.can_meta($<infixish>, "negate")>    
           <?{ $<infixish><O><iffy> }>
           <?{ $<O> = $<infixish><O>; }>
            
        || <.panic("Can't negate " ~ $<infixish>.Str ~ " because " ~ $<infixish><O><dba> ~ " operators are not iffy enough")>
        ]
    }

    token infix_prefix_meta_operator:sym<R> {
        <sym> {} <infixish(1)>
        <.can_meta($<infixish>, "reverse")>
        <?{ $<O> = $<infixish><O>; }>
    }

    token infix_prefix_meta_operator:sym<S> {
        <sym> {} <infixish(1)>
        <.can_meta($<infixish>, "sequence")>
        <?{ $<O> = $<infixish><O>; }>
    }

    token infix_prefix_meta_operator:sym<X> {
        <sym> {}
        [ <infixish(1)>
            [X <.panic: "Old form of XopX found">]?
            <.can_meta($<infixish>[0], "cross")>
            <?{ $<O> = $<infixish>[0]<O>; $<O><prec>:delete; $<sym> ~= $<infixish>[0].Str }>
        ]?
        <O(|%list_infix, self.Opairs)>
    }

    token infix_circumfix_meta_operator:sym<« »> {
        [
        | '«'
        | '»'
        ]
        {} <infixish(1)> [ '«' | '»' || <.panic: "Missing « or »"> ]
        <.can_meta($<infixish>, "hyper")>
        <?{ $<O> := $<infixish><O>; }>
    }

    token infix_circumfix_meta_operator:sym«<< >>» {
        [
        | '<<'
        | '>>'
        ]
        {} <infixish(1)> [ '<<' | '>>' || <.panic("Missing << or >>")> ]
        <.can_meta($<infixish>, "hyper")>
        <?{ $<O> := $<infixish><O>; }>
    }

    token infix_postfix_meta_operator:sym<=> ($op) {
        '='
        <.can_meta($op, "make assignment out of")>
        [ <!{ $op<O><diffy> }> || <.panic("Can't make assignment out of " ~ $op<sym> ~ " because " ~ $op<O><dba> ~ " operators are diffy")> ]
        { $<sym> = $op<sym> ~ '='; }
        <O(|%item_assignment, $op.Opairs, dba => 'assignment', iffy => 0)>
    }

    token postcircumfix:sym<( )>
        { :dba('argument list') '(' ~ ')' <semiarglist> <O(|%methodcall)> }

    token postcircumfix:sym<[ ]>
        { :dba('subscript') '[' ~ ']' <semilist> { $<semilist>.Str ~~ /^\s*\-[1]\s*$/ and $¢.obs("[-1] subscript to access final element","[*-1]") } <O(|%methodcall)> }

    token postcircumfix:sym<{ }>
        { :dba('subscript') '{' ~ '}' <semilist> <O(|%methodcall)> }

    token postcircumfix:sym«< >» {
        :my $pos;
        '<'
        { $pos = $¢.pos }
        [
        || <nibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:q).tweak(:w).balanced('<','>'))> '>'
        || <?before \h* [ \d | <sigil> | ':' ] >
           { $¢.cursor_force($pos).panic("Whitespace required before < operator") }
        || { $¢.cursor_force($pos).panic("Unable to parse quote-words subscript; couldn't find right angle quote") }
        ]
        <O(|%methodcall)>
    }

    token postcircumfix:sym«<< >>»
        { '<<' <nibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:qq).tweak(:ww).balanced('<<','>>'))> [ '>>' || <.panic: "Unable to parse quote-words subscript; couldn't find right double-angle quote"> ] <O(|%methodcall)> }

    token postcircumfix:sym<« »>
        { '«' <nibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:qq).tweak(:ww).balanced('«','»'))> [ '»' || <.panic: "Unable to parse quote-words subscript; couldn't find right double-angle quote"> ] <O(|%methodcall)> }

    token postop {
        | <postfix>         { $<O> := $<postfix><O>; $<sym> := $<postfix><sym>; }
        | <postcircumfix>   { $<O> := $<postcircumfix><O>; $<sym> := $<postcircumfix><sym>; }
    }

    token methodop {
        [
        | <longname>
        | <?before '$' | '@' | '&' > <variable> { $*VAR = $<variable> }
        | <?before <[ ' " ]> >
            [ <!{$*QSIGIL}> || <!before '"' <-["]>*? \s > ] # dwim on "$foo."
            <quote>
            [ <?before '(' | '.(' | '\\'> || <.panic: "Quoted method name requires parenthesized arguments"> ]
            { my $t = $<quote><nibble>.Str; $t ~~ /\W/ or $t ~~ /^(WHO|WHAT|WHERE|WHEN|WHY|HOW)$/ or $¢.worry("Useless use of quotes") }
        ] <.unsp>? 

        :dba('method arguments')
        [
        | ':' <?before \s> <!{ $*QSIGIL }> <arglist>
        | <?[\\(]> <args>
        ]?
    }

    token semiarglist {
        <arglist> ** ';'
        <.ws>
    }

    token arglist {
        :my $inv_ok = $*INVOCANT_OK;
        :my StrPos $*endargs = 0;
        :my $*GOAL ::= 'endargs';
        :my $*QSIGIL ::= '';
        <.ws>
        :dba('argument list')
        [
        | <?stdstopper>
        | <EXPR(item %list_prefix)> {{
                my $delims = $<EXPR><delims>;
                for @$delims {
                    if ($_.<sym> // '') eq ':' {
                        if $inv_ok {
                            $*INVOCANT_IS = $<EXPR><list>[0];
                        }
                    }
                }
            }}
        ]
    }

    token term:lambda {
        <?before <.lambda> >
        <pblock>
        {{
            if $*BORG {
                $*BORG.<block> = $<pblock>;
            }
        }}
        <O(|%term)>
    }

    token circumfix:sym<{ }> {
        <?before '{' >
        <pblock>
        {{
            if $*BORG {
                $*BORG.<block> = $<pblock>;
            }
        }}
        <O(|%term)>
    }

    ## methodcall

    token postfix:sym<i>
        { <sym> » <O(|%methodcall)> }

    token infix:sym<.> ()
        { '.' <[\]\)\},:\s\$"']> <.obs('. to concatenate strings', '~')> }

    token postfix:sym['->'] ()
        { '->' <.obs('-> as postfix', 'either . to call a method, or whitespace to delimit a pointy block')> }

    ## autoincrement
    token postfix:sym<++>
        { <sym> <O(|%autoincrement)> }

    token postfix:sym«--» ()
        { <sym> <O(|%autoincrement)> }

    token prefix:sym<++>
        { <sym> <O(|%autoincrement)> }

    token prefix:sym«--» ()
        { <sym> <O(|%autoincrement)> }

    ## exponentiation
    token infix:sym<**>
        { <sym> <O(|%exponentiation)> }

    ## symbolic unary
    token prefix:sym<!>
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<+>
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<->
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<~~>
        { <sym> <.badinfix> <O(|%symbolic_unary)> }

    token prefix:sym<~>
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<??>
        { <sym> <.badinfix> <O(|%symbolic_unary)> }

    token prefix:sym<?>
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<~^>
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<+^>
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<?^>
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<^^>
        { <sym> <.badinfix> <O(|%symbolic_unary)> }

    token prefix:sym<^>
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<||>
        { <sym> <O(|%symbolic_unary)> }

    token prefix:sym<|>
        { <sym> <O(|%symbolic_unary)> }


    ## multiplicative
    token infix:sym<*>
        { <sym> <O(|%multiplicative)> }

    token infix:sym</>
        { <sym> <O(|%multiplicative)> }

    token infix:sym<div>
        { <sym> <O(|%multiplicative)> }

    token infix:sym<%>
        { <sym> <O(|%multiplicative, iffy => 1)> }   # Allow !% operator

    token infix:sym<mod>
        { <sym> <O(|%multiplicative)> }

    token infix:sym<+&>
        { <sym> <O(|%multiplicative)> }

    token infix:sym« +< »
        { <sym> <!before '<'> <O(|%multiplicative)> }

    token infix:sym« << »
        { <sym> \s <.obs('<< to do left shift', '+< or ~<')> <O(|%multiplicative)> }

    token infix:sym« >> »
        { <sym> \s <.obs('>> to do right shift', '+> or ~>')> <O(|%multiplicative)> }

    token infix:sym« +> »
        { <sym> <!before '>'> <O(|%multiplicative)> }

    token infix:sym<~&>
        { <sym> <O(|%multiplicative)> }

    token infix:sym<?&>
        { <sym> <O(|%multiplicative)> }

    token infix:sym« ~< »
        { <sym> <!before '<'> <O(|%multiplicative)> }

    token infix:sym« ~> »
        { <sym> <!before '>'> <O(|%multiplicative)> }


    ## additive
    token infix:sym<+>
        { <sym> <!before '+'> <O(|%additive)> }

    token infix:sym<->
        { <sym> <!before '-'> <O(|%additive)> }

    token infix:sym<+|>
        { <sym> <O(|%additive)> }

    token infix:sym<+^>
        { <sym> <O(|%additive)> }

    token infix:sym<~|>
        { <sym> <O(|%additive)> }

    token infix:sym<~^>
        { <sym> <O(|%additive)> }

    token infix:sym<?|>
        { <sym> <O(|%additive)> }

    token infix:sym<?^>
        { <sym> <O(|%additive)> }

    ## replication
    # Note: no word boundary check after x, relies on longest token for x2 xx2 etc
    token infix:sym<x>
        { <sym> <O(|%replication)> }

    token infix:sym<xx>
        { <sym> <O(|%replication)> }

    ## concatenation
    token infix:sym<~>
        { <sym> <O(|%concatenation)> }


    ## junctive and (all)
    token infix:sym<&>
        { <sym> <O(|%junctive_and)> }


    ## junctive or (any)
    token infix:sym<|>
        { <sym> <O(|%junctive_or)> }

    token infix:sym<^>
        { <sym> <O(|%junctive_or)> }


    ## named unary examples
    # (need \s* to win LTM battle with listops)
    token prefix:sleep
        { <sym> » <?before \s*> <O(|%named_unary)> }

    token prefix:abs
        { <sym> » <?before \s*> <O(|%named_unary)> }

    token prefix:let
        { <sym> » <?before \s*> <O(|%named_unary)> }

    token prefix:temp
        { <sym> » <?before \s*> <O(|%named_unary)> }


    ## structural infix
    token infix:sym« <=> »
        { <sym> <O(|%structural, returns => 'Order')> }

    token infix:cmp
        { <sym> <O(|%structural, returns => 'Order')> }

    token infix:leg
        { <sym> <O(|%structural, returns => 'Order')> }

    token infix:but
        { <sym> <O(|%structural)> }

    token infix:does
        { <sym> <O(|%structural)> }

    token infix:sym<..>
        { <sym> [<!{ $*IN_META }> <?before ')' | ']'> <.panic: "Please use ..* for indefinite range">]? <O(|%structural)> }

    token infix:sym<^..>
        { <sym> <O(|%structural)> }

    token infix:sym<..^>
        { <sym> <O(|%structural)> }

    token infix:sym<^..^>
        { <sym> <O(|%structural)> }


    ## chaining binary
    token infix:sym<==>
        { <sym> <!before '=' > <O(|%chaining)> }

    token infix:sym<!=>
        { <sym> <?before \s> <O(|%chaining)> }

    token infix:sym« < »
        { <sym> <O(|%chaining)> }

    token infix:sym« <= »
        { <sym> <O(|%chaining)> }

    token infix:sym« > »
        { <sym> <O(|%chaining)> }

    token infix:sym« >= »
        { <sym> <O(|%chaining)> }

    token infix:sym<~~>
        { <sym> <O(|%chaining)> }

    # XXX should move to inside meta !
    token infix:sym<!~>
        { <sym> \s <.obs('!~ to do negated pattern matching', '!~~')> <O(|%chaining)> }

    token infix:sym<=~>
        { <sym> <.obs('=~ to do pattern matching', '~~')> <O(|%chaining)> }

    token infix:sym<eq>
        { <sym> <O(|%chaining)> }

    token infix:sym<ne>
        { <sym> <O(|%chaining)> }

    token infix:sym<lt>
        { <sym> <O(|%chaining)> }

    token infix:sym<le>
        { <sym> <O(|%chaining)> }

    token infix:sym<gt>
        { <sym> <O(|%chaining)> }

    token infix:sym<ge>
        { <sym> <O(|%chaining)> }

    token infix:sym<=:=>
        { <sym> <O(|%chaining)> }

    token infix:sym<===>
        { <sym> <O(|%chaining)> }

    token infix:sym<eqv>
        { <sym> <O(|%chaining)> }

    token infix:sym<before>
        { <sym> <O(|%chaining)> }

    token infix:sym<after>
        { <sym> <O(|%chaining)> }


    ## tight and
    token infix:sym<&&>
        { <sym> <O(|%tight_and)> }


    ## tight or
    token infix:sym<||>
        { <sym> <O(|%tight_or)> }

    token infix:sym<^^>
        { <sym> <O(|%tight_or)> }

    token infix:sym<//>
        { <sym> <O(|%tight_or)> }

    token infix:sym<min>
        { <sym> <O(|%tight_or)> }

    token infix:sym<max>
        { <sym> <O(|%tight_or)> }


    ## conditional
    token infix:sym<?? !!> {
        :my $*GOAL ::= '!!';
        '??'
        <.ws>
        <EXPR(item %item_assignment)>
        [ '!!' ||
            [
            || <?before '='> <.panic: "Assignment not allowed within ??!!">
            || <?before '::'> <.panic: "Please use !! rather than ::">
            || <?before <infixish>>    # Note: a tight infix would have parsed right
                <.panic: "Precedence too loose within ??!!; use ??()!! instead ">
            || <.panic: "Found ?? but no !!; possible precedence problem">
            ]
        ]
        <O(|%conditional, _reducecheck => 'raise_middle')>
    }

    method raise_middle {
        self.<middle> = self.<infix><EXPR>;
        self;
    }

    token infix:sym<?>
        { <sym> {} <!before '?'> <?before <-[;]>*?':'> <.obs('?: for the conditional operator', '??!!')> <O(|%conditional)> }

    token infix:sym<ff>
        { <sym> <O(|%conditional)> }

    token infix:sym<^ff>
        { <sym> <O(|%conditional)> }

    token infix:sym<ff^>
        { <sym> <O(|%conditional)> }

    token infix:sym<^ff^>
        { <sym> <O(|%conditional)> }

    token infix:sym<fff>
        { <sym> <O(|%conditional)> }

    token infix:sym<^fff>
        { <sym> <O(|%conditional)> }

    token infix:sym<fff^>
        { <sym> <O(|%conditional)> }

    token infix:sym<^fff^>
        { <sym> <O(|%conditional)> }

    ## assignment
    # There is no "--> type" because assignment may be coerced to either
    # item assignment or list assignment at "make" time.

    token infix:sym<=> ()
    {
        <sym>
        [
        || <?{ $*LEFTSIGIL eq '$' }>
            <O(|%item_assignment)>
        ||  <O(|%list_assignment)>
        ]
    }

    token infix:sym<:=>
        { <sym> <O(|%item_assignment)> }

    token infix:sym<::=>
        { <sym> <O(|%item_assignment)> }

    token infix:sym<.=> {
        <sym>
        <O(|%item_assignment,
            nextterm => 'dottyopish',
            _reducecheck => 'check_doteq'
        )>
    }

    method check_doteq {
        # [ <?before \w+';' | 'new'|'sort'|'subst'|'trans'|'reverse'|'uniq'|'map'|'samecase'|'substr'|'flip'|'fmt' > || ]
        return self if self.<left><scope_declarator>;
        my $ok = 0;

        try {
            my $methop = self.<right><methodop>;
            my $name = $methop.<longname>.Str;
            if $name eq 'new' or $name eq 'sort' or $name eq 'subst' or $name eq 'trans' or $name eq 'reverse' or $name eq 'uniq' or $name eq 'map' or $name eq 'samecase' or $name eq 'substr' or $name eq 'flip' or $name eq 'fmt' {
                $ok = 1;
            }
            elsif not $methop.<args>[0] {
                $ok = 1;
            }
        };

        self.cursor_force(self.<infix><_pos>).worryobs('.= as append operator', '~=') unless $ok;
        self;
    }

    token infix:sym« => »
        { <sym> <O(|%item_assignment, fiddly => 0)> }

    # Note, other assignment ops generated by infix_postfix_meta_operator rule

    ## loose unary
    token prefix:sym<so>
        { <sym> » <O(|%loose_unary)> }

    token prefix:sym<not>
        { <sym> » <O(|%loose_unary)> }

    ## list item separator
    token infix:sym<,>
        { <sym> <O(|%comma, fiddly => 0)> }

    token infix:sym<:>
        { <sym> <?before \s | <terminator> >
            { $¢.panic("Illegal use of colon as invocant marker") unless $*INVOCANT_OK-- or $*PRECLIM ge $item_assignment_prec; }
        <O(|%comma)> }

    token infix:sym<Z>
        { <sym> <O(|%list_infix)> }

    token infix:sym<minmax>
        { <sym> <O(|%list_infix)> }

    token infix:sym<...>
        { <sym> <O(|%list_infix)> }

    token term:sym<...>
        { <sym> <args>? <O(|%list_prefix)> }

    token term:sym<???>
        { <sym> <args>? <O(|%list_prefix)> }

    token term:sym<!!!>
        { <sym> <args>? <O(|%list_prefix)> }

    my %deftrap = (
        :say, :print, :abs, :alarm, :chomp, :chop, :chr, :chroot, :cos,
        :defined, :eval, :exp, :glob, :lc, :lcfirst, :log, :lstat, :mkdir,
        :ord, :readlink, :readpipe, :require, :reverse, :rmdir, :sin,
        :split, :sqrt, :stat, :uc, :ucfirst, :unlink,
    );

    # force identifier(), identifier.(), etc. to be a function call always
    token term:identifier
    {
        :my $name;
        :my $pos;
        <identifier> <?before [<unsp>|'(']? > <![:]>
        { $name = $<identifier>.Str; $pos = $¢.pos; }
        <args( $¢.is_name($name) )>
        { self.add_mystery($name,$pos,substr($*ORIG,$pos,1)) unless $<args><invocant>; }
        {{
            if $*BORG and $*BORG.<block> {
                if not $*BORG.<name> {
                    $*BORG.<culprit> = $<identifier>.cursor($pos);
                    $*BORG.<name> = $name;
                }
            }
            if %deftrap{$name} {
                my $al = $<args><arglist>[0];
                my $ok = 0;
                $ok = 1 if $al and $al.from != $al.to;
                $ok = 1 if $<args><semiarglist>;
                if not $ok {
                    $<identifier>.worryobs("bare '$name'", ".$name if you want to $name \$_, or use an explicit argument");
                }
            }
        }}
        <O(|%term)>
    }

    token args ($istype = 0) {
        :my $listopish = 0;
        :my $*GOAL ::= '';
        :my $*INVOCANT_OK = 1;
        :my $*INVOCANT_IS;
        [
    #    | :dba('argument list') '.(' ~ ')' <semiarglist>
        | :dba('argument list') '(' ~ ')' <semiarglist>
        | :dba('argument list') <.unsp> '(' ~ ')' <semiarglist>
        |  { $listopish = 1 } [<?before \s> <!{ $istype }> <.ws> <!infixstopper> <arglist>]?
        ]
        { $<invocant> = $*INVOCANT_IS; }

        :dba('extra arglist after (...):')
        [
        || <?{ $listopish }>
        || ':' <?before \s> <moreargs=.arglist>    # either switch to listopiness
        || {{ $<O> = {}; }}   # or allow adverbs (XXX needs hoisting?)
        ]
    }

    # names containing :: may or may not be function calls
    # bare identifier without parens also handled here if no other rule parses it
    token term:name
    {
        :my $name;
        :my $pos;
        <longname>
        {
            $name = $<longname>.Str;
            $pos = $¢.pos;
        }
        [
        ||  <?{
                $¢.is_name($name) or substr($name,0,2) eq '::'
            }>
            # parametric type?
            <.unsp>? [ <?before '['> <postcircumfix> ]?
            :dba('type parameter')
            [
                '::'
                <?before [ '«' | '<' | '{' | '<<' ] > <postcircumfix>
            ]?

        # unrecognized names are assumed to be post-declared listops.
        || <args> { self.add_mystery($name,$pos,'termish') unless $<args><invocant>; }
            {{
                if $*BORG and $*BORG.<block> {
                    if not $*BORG.<name> {
                        $*BORG.<culprit> = $<longname>.cursor($pos);
                        $*BORG.<name> //= $name;
                    }
                }
            }}
        ]
        <O(%term)>
    }

    ## loose and
    token infix:sym<and>
        { <sym> <O(|%loose_and)> }

    token infix:sym<andthen>
        { <sym> <O(|%loose_and)> }

    ## loose or
    token infix:sym<or>
        { <sym> <O(|%loose_or)> }

    token infix:sym<orelse>
        { <sym> <O(|%loose_or)> }

    token infix:sym<xor>
        { <sym> <O(|%loose_or)> }

    ## sequencer
    token infix:sym« <== »
        { <sym> <O(|%sequencer)> }

    token infix:sym« ==> »
        { <sym> <O(|%sequencer)> }

    token infix:sym« <<== »
        { <sym> <O(|%sequencer)> }

    token infix:sym« ==>> »
        { <sym> <O(|%sequencer)> }

    ## expression terminator
    # Note: must always be called as <?terminator> or <?before ...<terminator>...>

    token terminator:sym<;>
        { ';' <O(|%terminator)> }

    token terminator:sym<if>
        { 'if' » <.nofun> <O(|%terminator)> }

    token terminator:sym<unless>
        { 'unless' » <.nofun> <O(|%terminator)> }

    token terminator:sym<while>
        { 'while' » <.nofun> <O(|%terminator)> }

    token terminator:sym<until>
        { 'until' » <.nofun> <O(|%terminator)> }

    token terminator:sym<for>
        { 'for' » <.nofun> <O(|%terminator)> }

    token terminator:sym<given>
        { 'given' » <.nofun> <O(|%terminator)> }

    token terminator:sym<when>
        { 'when' » <.nofun> <O(|%terminator)> }

    token terminator:sym« --> »
        { '-->' <O(|%terminator)> }

    token terminator:sym<!!>
        { '!!' <?{ $*GOAL eq '!!' }> <O(|%terminator)> }

    regex infixstopper {
        :dba('infix stopper')
        [
        | <?before <stopper> >
        | <?before '!!' > [ <?{ $*GOAL eq '!!' }> || <.panic: "Ternary !! seems to be missing its ??"> ]
        | <?before '{' | <lambda> > <?{ ($*GOAL eq '{' or $*GOAL eq 'endargs') and @*MEMOS[$¢.pos]<ws> }>
        | <?{ $*GOAL eq 'endargs' and @*MEMOS[$¢.pos]<endargs> }>
        ]
    }

} # end grammar

grammar Q is STD {

    role b1 {
        token escape:sym<\\> { <sym> <item=.backslash> }
        token backslash:qq { <?before 'q'> { $<quote> = $¢.cursor_fresh(%*LANG<MAIN>).quote(); } }
        token backslash:sym<\\> { <text=.sym> }
        token backslash:stopper { <text=.stopper> }
        token backslash:a { <sym> }
        token backslash:b { <sym> }
        token backslash:c { <sym> <charspec> }
        token backslash:e { <sym> }
        token backslash:f { <sym> }
        token backslash:n { <sym> }
        token backslash:o { :dba('octal character') <sym> [ <octint> | '[' ~ ']' <octints> ] }
        token backslash:r { <sym> }
        token backslash:t { <sym> }
        token backslash:x { :dba('hex character') <sym> [ <hexint> | '[' ~ ']' <hexints> ] }
        token backslash:sym<0> { <sym> }
    } # end role

    role b0 {
        token escape:sym<\\> { <!> }
    } # end role

    role c1 {
        token escape:sym<{ }> { <?before '{'> [ :lang(%*LANG<MAIN>) <embeddedblock> ] }
    } # end role

    role c0 {
        token escape:sym<{ }> { <!> }
    } # end role

    role s1 {
        token escape:sym<$> {
            :my $*QSIGIL ::= '$';
            <?before '$'>
            [ :lang(%*LANG<MAIN>) <EXPR(item %methodcall)> ] || <.panic: "Non-variable \$ must be backslashed">
        }
    } # end role

    role s0 {
        token escape:sym<$> { <!> }
    } # end role

    role a1 {
        token escape:sym<@> {
            :my $*QSIGIL ::= '@';
            <?before '@'>
            [ :lang(%*LANG<MAIN>) <EXPR(item %methodcall)> | <!> ] # trap ABORTBRANCH from variable's ::
        }
    } # end role

    role a0 {
        token escape:sym<@> { <!> }
    } # end role

    role h1 {
        token escape:sym<%> {
            :my $*QSIGIL ::= '%';
            <?before '%'>
            [ :lang(%*LANG<MAIN>) <EXPR(item %methodcall)> | <!> ]
        }
    } # end role

    role h0 {
        token escape:sym<%> { <!> }
    } # end role

    role f1 {
        token escape:sym<&> {
            :my $*QSIGIL ::= '&';
            <?before '&'>
            [ :lang(%*LANG<MAIN>) <EXPR(item %methodcall)> | <!> ]
        }
    } # end role

    role f0 {
        token escape:sym<&> { <!> }
    } # end role

    role p1 {
        method postprocess ($s) { $s.parsepath }
    } # end role

    role p0 {
        method postprocess ($s) { $s }
    } # end role

    role w1 {
        method postprocess ($s) { $s.words }
    } # end role

    role w0 {
        method postprocess ($s) { $s }
    } # end role

    role ww1 {
        method postprocess ($s) { $s.words }
    } # end role

    role ww0 {
        method postprocess ($s) { $s }
    } # end role

    role x1 {
        method postprocess ($s) { $s.run }
    } # end role

    role x0 {
        method postprocess ($s) { $s }
    } # end role

    role q {
        token stopper { \' }

        token escape:sym<\\> { <sym> <item=.backslash> }

        token backslash:qq { <?before 'q'> { $<quote> = $¢.cursor_fresh(%*LANG<MAIN>).quote(); } }
        token backslash:sym<\\> { <text=.sym> }
        token backslash:stopper { <text=.stopper> }

        # in single quotes, keep backslash on random character by default
        token backslash:misc { {} (.) { $<text> = "\\" ~ $0.Str; } }

        # begin tweaks (DO NOT ERASE)
        multi method tweak (:single(:$q)!) { self.panic("Too late for :q") }
        multi method tweak (:double(:$qq)!) { self.panic("Too late for :qq") }
        # end tweaks (DO NOT ERASE)

    } # end role

    role qq does b1 does c1 does s1 does a1 does h1 does f1 {
        token stopper { \" }
        # in double quotes, omit backslash on random \W backslash by default
        token backslash:misc { {} [ (\W) { $<text> = $0.Str; } | $<x>=(\w) <.panic("Unrecognized backslash sequence: '\\" ~ $<x>.Str ~ "'")> ] }

        # begin tweaks (DO NOT ERASE)
        multi method tweak (:single(:$q)!) { self.panic("Too late for :q") }
        multi method tweak (:double(:$qq)!) { self.panic("Too late for :qq") }
        # end tweaks (DO NOT ERASE)

    } # end role

    role p5 {
        # begin tweaks (DO NOT ERASE)
        multi method tweak (:$g!) { self }
        multi method tweak (:$i!) { self }
        multi method tweak (:$m!) { self }
        multi method tweak (:$s!) { self }
        multi method tweak (:$x!) { self }
        multi method tweak (:$p!) { self }
        multi method tweak (:$c!) { self }
        # end tweaks (DO NOT ERASE)
    } # end role

    # begin tweaks (DO NOT ERASE)

    multi method tweak (:single(:$q)!) { self.truly($q,':q'); self.mixin( ::q ); }

    multi method tweak (:double(:$qq)!) { self.truly($qq, ':qq'); self.mixin( ::qq ); }

    multi method tweak (:backslash(:$b)!)   { self.mixin($b ?? ::b1 !! ::b0) }
    multi method tweak (:scalar(:$s)!)      { self.mixin($s ?? ::s1 !! ::s0) }
    multi method tweak (:array(:$a)!)       { self.mixin($a ?? ::a1 !! ::a0) }
    multi method tweak (:hash(:$h)!)        { self.mixin($h ?? ::h1 !! ::h0) }
    multi method tweak (:function(:$f)!)    { self.mixin($f ?? ::f1 !! ::f0) }
    multi method tweak (:closure(:$c)!)     { self.mixin($c ?? ::c1 !! ::c0) }

    multi method tweak (:path(:$p)!)        { self.mixin($p ?? ::p1 !! ::p0) }
    multi method tweak (:exec(:$x)!)        { self.mixin($x ?? ::x1 !! ::x0) }
    multi method tweak (:words(:$w)!)       { self.mixin($w ?? ::w1 !! ::w0) }
    multi method tweak (:quotewords(:$ww)!) { self.mixin($ww ?? ::ww1 !! ::ww0) }

    multi method tweak (:heredoc(:$to)!) { self.truly($to, ':to'); self.cursor_herelang; }

    multi method tweak (:$regex!) {
        return %*LANG<Regex>;
    }

    multi method tweak (:$trans!) {
        return %*LANG<Trans>;
    }

    multi method tweak (*%x) {
        my @k = keys(%x);
        self.panic("Unrecognized quote modifier: " ~ join('',@k));
    }
    # end tweaks (DO NOT ERASE)


} # end grammar

grammar Quasi is STD::P6 {
    token term:unquote {
        :my $*QUASIMODO = 0;
        <starter><starter><starter> <.ws>
        [ <EXPR> <stopper><stopper><stopper> || <.panic: "Confused"> ]
    }

    # begin tweaks (DO NOT ERASE)
    multi method tweak (:$ast!) { self; } # XXX some transformer operating on the normal AST?
    multi method tweak (:$lang!) { self.cursor_fresh( $lang ); }
    multi method tweak (:$unquote!) { self; } # XXX needs to override unquote
    multi method tweak (:$COMPILING!) { $*QUASIMODO = 1; self; } # XXX needs to lazify the lexical lookups somehow

    multi method tweak (*%x) {
        my @k = keys(%x);
        self.panic("Unrecognized quasiquote modifier: " ~ join('',@k));
    }
    # end tweaks (DO NOT ERASE)

} # end grammar

##############################
# Operator Precedence Parser #
##############################

method EXPR ($preclvl) {
    my $*CTX ::= self.callm if $*DEBUG +& DEBUG::trace_call;
    if self.peek {
        return self._AUTOLEXpeek('EXPR');
    }
    my $preclim = $preclvl ?? $preclvl.<prec> // $LOOSEST !! $LOOSEST;
    my $*LEFTSIGIL = '';
    my $*PRECLIM = $preclim;
    my @termstack;
    my @opstack;
    my $termish = 'termish';

    push @opstack, { 'O' => item %terminator, 'sym' => '' };         # (just a sentinel value)

    my $here = self;
    my $S = $here.pos;
    self.deb("In EXPR, at $S") if $*DEBUG +& DEBUG::EXPR;

    my &reduce := -> {
        self.deb("entering reduce, termstack == ", +@termstack, " opstack == ", +@opstack) if $*DEBUG +& DEBUG::EXPR;
        my $op = pop @opstack;
        my $sym = $op<sym>;
        given $op<O><assoc> // 'unary' {
            when 'chain' {
                self.deb("reducing chain") if $*DEBUG +& DEBUG::EXPR;
                my @chain;
                push @chain, pop(@termstack);
                push @chain, $op;
                while @opstack {
                    last if $op<O><prec> ne @opstack[*-1]<O><prec>;
                    push @chain, pop(@termstack);
                    push @chain, pop(@opstack);
                }
                push @chain, pop(@termstack);
                my $endpos = @chain[0]<_pos>;
                @chain = reverse @chain if @chain > 1;
                my $startpos = @chain[0]<_from>;
                my $nop = $op.cursor_fresh();
                $nop<chain> = [@chain];
                $nop<_arity> = 'CHAIN';
                $nop<_from> = $startpos;
                $nop<_pos> = $endpos;
                my @caps;
                my $i = 0;
                for @chain {
                    push(@caps, $i++ % 2 ?? 'op' !! 'term' );
                    push(@caps, $_);
                }
                $nop<~CAPS> = \@caps;
                push @termstack, $nop._REDUCE($startpos, 'CHAIN');
                @termstack[*-1].<PRE>:delete;
                @termstack[*-1].<POST> :delete;
            }
            when 'list' {
                self.deb("reducing list") if $*DEBUG +& DEBUG::EXPR;
                my @list;
                my @delims = $op;
                push @list, pop(@termstack);
                while @opstack {
                    self.deb($sym ~ " vs " ~ @opstack[*-1]<sym>) if $*DEBUG +& DEBUG::EXPR;
                    last if $sym ne @opstack[*-1]<sym>;
                    if @termstack and defined @termstack[0] {
                        push @list, pop(@termstack);
                    }
                    else {
                        self.worry("Missing term in " ~ $sym ~ " list");
                    }
                    push @delims, pop(@opstack);
                }
                if @termstack and defined @termstack[0] {
                    push @list, pop(@termstack);
                }
                else {
                    self.worry("Missing final term in '" ~ $sym ~ "' list");
                }
                my $endpos = @list[0]<_pos>;
                @list = reverse @list if @list > 1;
                my $startpos = @list[0]<_from>;
                @delims = reverse @delims if @delims > 1;
                my $nop = $op.cursor_fresh();
                $nop<sym> = $sym;
                $nop<O> = $op<O>;
                $nop<list> = [@list];
                $nop<delims> = [@delims];
                $nop<_arity> = 'LIST';
                $nop<_from> = $startpos;
                $nop<_pos> = $endpos;
                if @list {
                    my @caps;
                    push @caps, 'elem', @list[0] if @list[0];
                    for 0..@delims-1 {
                        my $d = @delims[$_];
                        my $l = @list[$_+1];
                        push @caps, 'delim', $d;
                        push @caps, 'elem', $l if $l;  # nullterm?
                    }
                    $nop<~CAPS> = \@caps;
                }
                push @termstack, $nop._REDUCE($startpos, 'LIST');
                @termstack[*-1].<PRE>:delete;
                @termstack[*-1].<POST>:delete;
            }
            when 'unary' {
                self.deb("reducing") if $*DEBUG +& DEBUG::EXPR;
                self.deb("Termstack size: ", +@termstack) if $*DEBUG +& DEBUG::EXPR;

                self.deb($op.dump) if $*DEBUG +& DEBUG::EXPR;
                my $nop = $op.cursor_fresh();
                my $arg = pop @termstack;
                $op<arg> = $arg;
                my $a = $op<~CAPS>;
                $op<_arity> = 'UNARY';
                if $arg<_from> < $op<_from> { # postfix
                    $op<_from> = $arg<_from>;   # extend from to include arg
#                    warn "OOPS ", $arg.Str, "\n" if @acaps > 1;
                    unshift @$a, 'arg', $arg;
                    push @termstack, $op._REDUCE($op<_from>, 'POSTFIX');
                    @termstack[*-1].<PRE>:delete;
                    @termstack[*-1].<POST>:delete;
                }
                elsif $arg<_pos> > $op<_pos> {   # prefix
                    $op<_pos> = $arg<_pos>;     # extend pos to include arg
#                    warn "OOPS ", $arg.Str, "\n" if @acaps > 1;
                    push @$a, 'arg', $arg;
                    push @termstack, $op._REDUCE($op<_from>, 'PREFIX');
                    @termstack[*-1].<PRE>:delete;
                    @termstack[*-1].<POST>:delete;
                }
            }
            default {
                self.deb("reducing") if $*DEBUG +& DEBUG::EXPR;
                self.deb("Termstack size: ", +@termstack) if $*DEBUG +& DEBUG::EXPR;

                my $right = pop @termstack;
                my $left = pop @termstack;
                $op<right> = $right;
                $op<left> = $left;
                $op<_from> = $left<_from>;
                $op<_pos> = $right<_pos>;
                $op<_arity> = 'BINARY';

                my $a = $op<~CAPS>;
                unshift @$a, 'left', $left;
                push @$a, 'right', $right;

                self.deb($op.dump) if $*DEBUG +& DEBUG::EXPR;
                my $ck;
                if $ck = $op<O><_reducecheck> {
                    $op = $op.$ck;
                }
                push @termstack, $op._REDUCE($op<_from>, 'INFIX');
                @termstack[*-1].<PRE>:delete;
                @termstack[*-1].<POST>:delete;
            }
        }
    };

  TERM:
    loop {
        self.deb("In loop, at ", $here.pos) if $*DEBUG +& DEBUG::EXPR;
        my $oldpos = $here.pos;
        $here = $here.cursor_fresh();
        $*LEFTSIGIL = @opstack[*-1]<O><prec> gt $item_assignment_prec ?? '@' !! '';
        my @t = $here.$termish;

        if not @t or not $here = @t[0] or ($here.pos == $oldpos and $termish eq 'termish') {
            $here.panic("Missing term") if @opstack > 1;
            return ();
            # $here.panic("Failed to parse a required term");
        }
        $termish = 'termish';
        my $PRE = $here.<PRE>:delete // [];
        my $POST = $here.<POST>:delete // [];
        my @PRE = @$PRE;
        my @POST = reverse @$POST;

        # interleave prefix and postfix, pretend they're infixish
        my $M = $here;

        # note that we push loose stuff onto opstack before tight stuff
        while @PRE and @POST {
            my $postO = @POST[0]<O>;
            my $preO = @PRE[0]<O>;
            if $postO<prec> lt $preO<prec> {
                push @opstack, shift @POST;
            }
            elsif $postO<prec> gt $preO<prec> {
                push @opstack, shift @PRE;
            }
            elsif $postO<uassoc> eq 'left' {
                push @opstack, shift @POST;
            }
            elsif $postO<uassoc> eq 'right' {
                push @opstack, shift @PRE;
            }
            else {
                $here.panic('"' ~ @PRE[0]<sym> ~ '" and "' ~ @POST[0]<sym> ~ '" are not associative');
            }
        }
        push @opstack, @PRE,@POST;

        push @termstack, $here.<term>;
        @termstack[*-1].<POST>:delete;
        self.deb("after push: " ~ (0+@termstack)) if $*DEBUG +& DEBUG::EXPR;

        last TERM if $preclim eq $methodcall_prec; # in interpolation, probably

        loop {     # while we see adverbs
            $oldpos = $here.pos;
            last TERM if (@*MEMOS[$oldpos]<endstmt> // 0) == 2;
            $here = $here.cursor_fresh.ws;
            my @infix = $here.cursor_fresh.infixish();
            last TERM unless @infix;
            my $infix = @infix[0];
            last TERM unless $infix.pos > $oldpos;
            
            if not $infix<sym> {
                die $infix.dump if $*DEBUG +& DEBUG::EXPR;
            }

            my $inO = $infix<O>;
            my Str $inprec = $inO<prec>;
            if not defined $inprec {
                self.deb("No prec given in infix!") if $*DEBUG +& DEBUG::EXPR;
                die $infix.dump if $*DEBUG +& DEBUG::EXPR;
                $inprec = %terminator<prec>;
            }

            if $inprec le $preclim {
                if $preclim ne $LOOSEST {
                    my $dba = $preclvl.<dba>;
                    my $h = $*HIGHEXPECT;
                    %$h = ();
                    $h.{"an infix operator with precedence tighter than $dba"} = 1;
                }
                last TERM;
            }

            $here = $infix.cursor_fresh.ws();

            # substitute precedence for listops
            $inO<prec> = $inO<sub> if $inO<sub>;

            # Does new infix (or terminator) force any reductions?
            while @opstack[*-1]<O><prec> gt $inprec {
                &reduce();
            }

            # Not much point in reducing the sentinels...
            last if $inprec lt $LOOSEST;

        if $infix<fake> {
            push @opstack, $infix;
            &reduce();
            next;  # not really an infix, so keep trying
        }

            # Equal precedence, so use associativity to decide.
            if @opstack[*-1]<O><prec> eq $inprec {
                given $inO<assoc> {
                    when 'non'   { $here.panic('"' ~ $infix.Str ~ '" is not associative') }
                    when 'left'  { &reduce() }   # reduce immediately
                    when 'right' { }            # just shift
                    when 'chain' { }            # just shift
                    when 'unary' { }            # just shift
                    when 'list'  {              # if op differs reduce else shift
                       # &reduce() if $infix<sym> !eqv @opstack[*-1]<sym>;
                    }
                    default { $here.panic('Unknown associativity "' ~ $_ ~ '" for "' ~ $infix<sym> ~ '"') }
                }
            }

            $termish = $inO<nextterm> if $inO<nextterm>;
            push @opstack, $infix;              # The Shift
            last;
        }
    }
    &reduce() while +@opstack > 1;
    if @termstack {
        +@termstack == 1 or $here.panic("Internal operator parser error, termstack == " ~ (+@termstack));
        @termstack[0]<_from> = self.pos;
        @termstack[0]<_pos> = $here.pos;
    }
    self._MATCHIFYr($S, "EXPR", @termstack);
}

##########
## Regex #
##########

grammar Regex is STD {

    # begin tweaks (DO NOT ERASE)
    multi method tweak (:Perl5(:$P5)!) { self.require_P5; self.cursor_fresh( %*LANG<Q> ).mixin( ::q ).mixin( ::p5 ) }
    multi method tweak (:overlap(:$ov)!) { self }
    multi method tweak (:exhaustive(:$ex)!) { self }
    multi method tweak (:continue(:$c)!) { self }
    multi method tweak (:pos(:$p)!) { self }
    multi method tweak (:sigspace(:$s)!) { self }
    multi method tweak (:ratchet(:$r)!) { self }
    multi method tweak (:global(:$g)!) { self }
    multi method tweak (:ignorecase(:$i)!) { self }
    multi method tweak (:ignoreaccent(:$a)!) { self }
    multi method tweak (:samecase(:$ii)!) { self }
    multi method tweak (:sameaccent(:$aa)!) { self }
    multi method tweak (:$nth!) { self }
    multi method tweak (:st(:$nd)!) { self }
    multi method tweak (:rd(:$th)!) { self }
    multi method tweak (:$x!) { self }
    multi method tweak (:$bytes!) { self }
    multi method tweak (:$codes!) { self }
    multi method tweak (:$graphs!) { self }
    multi method tweak (:$chars!) { self }
    multi method tweak (:$rw!) { self }
    multi method tweak (:$keepall!) { self }
    multi method tweak (:$panic!) { self }
    # end tweaks (DO NOT ERASE)

    token category:metachar { <sym> }
    proto token metachar { <...> }

    token category:backslash { <sym> }
    proto token backslash { <...> }

    token category:assertion { <sym> }
    proto token assertion { <...> }

    token category:quantifier { <sym> }
    proto token quantifier { <...> }

    token category:mod_internal { <sym> }
    proto token mod_internal { <...> }

    proto token regex_infix { <...> }

    token ws {
        <?{ $*sigspace }>
        || [ <?before \s | '#'> <.nextsame> ]?   # still get all the pod goodness, hopefully
    }

    token normspace {
        <?before \s | '#'> [ :lang($¢.cursor_fresh(%*LANG<MAIN>)) <.ws> ]
    }

    token unsp { '\\' <?before \s | '#'> <.panic: "No unspace allowed in regex (for literal please quote with single quotes)"> }  # no unspace in regexen

    rule nibbler {
        :temp $*sigspace;
        :temp $*ratchet;
        :temp $*ignorecase;
        :temp $*ignoreaccent;
        [ \s* < || | && & > ]?
        <EXPR>
        [ <?before <stopper> || $*GOAL > || <.panic: "Unrecognized regex metacharacter (must be quoted to match literally)"> ]
    }

    token termish {
        <.ws>
        [
        || <term=.quant_atom_list>
        || <?before <stopper> | <[&|~]>  >  <.panic: "Null pattern not allowed">
        || <?before <[ \] \) \> ]> > <.panic: "Unmatched closing bracket">
        || <.panic: "Unrecognized regex metacharacter (must be quoted to match literally)">
        ]
    }
    token quant_atom_list {
        <quantified_atom>+
    }
    token infixish {
        <!infixstopper>
        <!stdstopper>
        <regex_infix>
        {
            $<O> = $<regex_infix><O>;
            $<sym> = $<regex_infix><sym>;
        }
    }
    regex infixstopper {
        :dba('infix stopper')
        <?before <stopper> >
    }

    token regex_infix:sym<||> { <sym> <O(|%tight_or)>  }
    token regex_infix:sym<&&> { <sym> <O(|%tight_and)>  }
    token regex_infix:sym<|> { <sym> <O(|%junctive_or)>  }
    token regex_infix:sym<&> { <sym> <O(|%junctive_and)>  }
    token regex_infix:sym<~> { <sym> <O(|%additive)>  }

    token quantified_atom {
        <!stopper>
        <!regex_infix>
        <atom>
        <.ws>
        [ <quantifier> <.ws> ]?
#            <?{ $<atom>.max_width }>
#                || <.panic: "Can't quantify zero-width atom">
    }

    token atom {
        :dba('regex atom')
        [
        | \w
        | <metachar> ::
        ]
    }

    # sequence stoppers
    token metachar:sym« > » { '>'  :: <fail> }
    token metachar:sym<&&>  { '&&' :: <fail> }
    token metachar:sym<&>   { '&'  :: <fail> }
    token metachar:sym<||>  { '||' :: <fail> }
    token metachar:sym<|>   { '|'  :: <fail> }
    token metachar:sym<]>   { ']'  :: <fail> }
    token metachar:sym<)>   { ')'  :: <fail> }
    token metachar:sym<;>   {
        ';' {}
        [
        || <?before \N*? <stopper> > <.panic: "Semicolon must be quoted">
        || <?before .> <.panic: "Regex missing terminator (or semicolon must be quoted?)">
        || <.panic: "Regex missing terminator">   # the final fake ;
        ]
    }

    token metachar:quant { <quantifier> <.panic: "quantifier quantifies nothing"> }

    # "normal" metachars

    token metachar:sigwhite {
        <normspace>
    }
    token metachar:unsp   { <unsp> }

    token metachar:sym<{ }> {
        <?before '{'>
        <embeddedblock>
        {{ $/<sym> := <{ }> }}
    }

    token metachar:mod {
        <mod_internal>
        { $/<sym> := $<mod_internal><sym> }
    }

    token metachar:sym<:> {
        <sym>
    }

    token metachar:sym<::> {
        <sym>
    }

    token metachar:sym<:::> {
        <sym>
    }

    token metachar:sym<[ ]> {
        '[' {} [:lang(self.unbalanced(']')) <nibbler>]
        [ ']' || <.panic: "Unable to parse regex; couldn't find right bracket"> ]
        { $/<sym> := <[ ]> }
    }

    token metachar:sym<( )> {
        '(' {} [:lang(self.unbalanced(')')) <nibbler>]
        [ ')' || <.panic: "Unable to parse regex; couldn't find right parenthesis"> ]
        { $/<sym> := <( )> }
    }

    token metachar:sym« <( » { '<(' }
    token metachar:sym« )> » { ')>' }

    token metachar:sym« << » { '<<' }
    token metachar:sym« >> » { '>>' }
    token metachar:sym< « > { '«' }
    token metachar:sym< » > { '»' }

    token metachar:qw {
        <?before '<' \s >  # (note required whitespace)
        <circumfix>
    }

    token metachar:sym«< >» {
        '<' ~ '>' <assertion>
    }

    token metachar:sym<\\> { <sym> <backslash> }
    token metachar:sym<.>  { <sym> }
    token metachar:sym<^^> { <sym> }
    token metachar:sym<^>  { <sym> }
    token metachar:sym<$$> {
        <sym>
        [ (\w+) <.obs("\$\$" ~ $0.Str ~ " to deref var inside a regex", "\$(\$" ~ $0.Str ~ ")")> ]?
    }
    token metachar:sym<$>  {
        '$'
        <?before
        | \s
        | '|'
        | '&'
        | ')'
        | ']'
        | '>'
        | $
        | <.stopper>
        >
    }

    token metachar:sym<' '> { <?before "'"> [:lang($¢.cursor_fresh(%*LANG<MAIN>)) <quote>] }
    token metachar:sym<" "> { <?before '"'> [:lang($¢.cursor_fresh(%*LANG<MAIN>)) <quote>] }

    token metachar:var {
        <!before '$$'>
        <?before <sigil>>
        [:lang($¢.cursor_fresh(%*LANG<MAIN>)) <variable> <.ws> <.check_variable($<variable>)> ]
        $<binding> = ( <.ws> '=' <.ws> <quantified_atom> )?
        { $<sym> = $<variable>.Str; }
    }

    token backslash:unspace { <?before \s> <.SUPER::ws> }

    token backslash:sym<0> { '0' <!before <[0..7]> > }

    token backslash:A { <sym> <.obs('\\A as beginning-of-string matcher', '^')> }
    token backslash:a { <sym> <.panic: "\\a is allowed only in strings, not regexes"> }
    token backslash:B { <sym> <.obs('\\B as word non-boundary', '<!wb>')> }
    token backslash:b { <sym> <.obs('\\b as word boundary', '<?wb> (or either of « or »)')> }
    token backslash:c { :i <sym> <charspec> }
    token backslash:d { :i <sym> }
    token backslash:e { :i <sym> }
    token backslash:f { :i <sym> }
    token backslash:h { :i <sym> }
    token backslash:n { :i <sym> }
    token backslash:o { :i :dba('octal character') <sym> [ <octint> | '[' ~ ']' <octints> ] }
    token backslash:Q { <sym> <.obs('\\Q as quotemeta', 'quotes or literal variable match')> }
    token backslash:r { :i <sym> }
    token backslash:s { :i <sym> }
    token backslash:t { :i <sym> }
    token backslash:v { :i <sym> }
    token backslash:w { :i <sym> }
    token backslash:x { :i :dba('hex character') <sym> [ <hexint> | '[' ~ ']' <hexints> ] }
    token backslash:z { <sym> <.obs('\\z as end-of-string matcher', '$')> }
    token backslash:Z { <sym> <.obs('\\Z as end-of-string matcher', '\\n?$')> }
    token backslash:misc { $<litchar>=(\W) }
    token backslash:oops { <.panic: "Unrecognized regex backslash sequence"> }

    token assertion:sym<...> { <sym> }
    token assertion:sym<???> { <sym> }
    token assertion:sym<!!!> { <sym> }

    token assertion:sym<?> { <sym> [ <?before '>'> | <assertion> ] }
    token assertion:sym<!> { <sym> [ <?before '>'> | <assertion> ] }
    token assertion:sym<*> { <sym> [ <?before '>'> | <.ws> <nibbler> ] }

    token assertion:sym<{ }> { <embeddedblock> }

    token assertion:variable {
        <?before <sigil>>  # note: semantics must be determined per-sigil
        [:lang($¢.cursor_fresh(%*LANG<MAIN>).unbalanced('>')) <variable=.EXPR(item %LOOSEST)>]
    }

    token assertion:method {
        '.' [
            | <?before <alpha> > <assertion>
            | [ :lang($¢.cursor_fresh(%*LANG<MAIN>).unbalanced('>')) <dottyop> ]
            ]
    }

    token assertion:name { [ :lang($¢.cursor_fresh(%*LANG<MAIN>).unbalanced('>')) <longname> ]
                                    [
                                    | <?before '>' >
                                    | <.ws> <nibbler>
                                    | '=' <assertion>
                                    | ':' <.ws>
                                        [ :lang($¢.cursor_fresh(%*LANG<MAIN>).unbalanced('>')) <arglist> ]
                                    | '(' {}
                                        [ :lang($¢.cursor_fresh(%*LANG<MAIN>)) <arglist> ]
                                        [ ')' || <.panic: "Assertion call missing right parenthesis"> ]
                                    ]?
    }

    token assertion:sym<[> { <?before '['> <cclass_elem>+ }
    token assertion:sym<+> { <?before '+'> <cclass_elem>+ }
    token assertion:sym<-> { <?before '-'> <cclass_elem>+ }
    token assertion:sym<.> { <sym> }
    token assertion:sym<,> { <sym> }
    token assertion:sym<~~> { <sym> [ <?before '>'> | \d+ | <desigilname> ] }

    token assertion:bogus { <.panic: "Unrecognized regex assertion"> }

    token sign { '+' | '-' | <?> }
    token cclass_elem {
        :dba('character class element')
        <sign>
        <.normspace>?
        [
        | <name>
        | <before '['> <quibble($¢.cursor_fresh( %*LANG<Q> ).tweak(:q))> # XXX parse as q[] for now
        ]
        <.normspace>?
    }

    token mod_arg { :dba('modifier argument') '(' ~ ')' [:lang($¢.cursor_fresh(%*LANG<MAIN>)) <semilist> ] }

    token mod_internal:sym<:my>    { ':' <?before ['my'|'state'|'our'|'anon'|'constant'|'temp'|'let'] \s > [:lang($¢.cursor_fresh(%*LANG<MAIN>)) <statement> <eat_terminator> ] }

    # XXX needs some generalization

    token mod_internal:sym<:i>    { $<sym>=[':i'|':ignorecase'] » { $*ignorecase = 1 } }
    token mod_internal:sym<:!i>   { $<sym>=[':!i'|':!ignorecase'] » { $*ignorecase = 0 } }
    token mod_internal:sym<:i( )> { $<sym>=[':i'|':ignorecase'] <mod_arg> { $*ignorecase = eval $<mod_arg>.Str } }
    token mod_internal:sym<:0i>   { ':' (\d+) ['i'|'ignorecase'] { $*ignorecase = $0 } }

    token mod_internal:sym<:a>    { $<sym>=[':a'|':ignoreaccent'] » { $*ignoreaccent = 1 } }
    token mod_internal:sym<:!a>   { $<sym>=[':!a'|':!ignoreaccent'] » { $*ignoreaccent = 0 } }
    token mod_internal:sym<:a( )> { $<sym>=[':a'|':ignoreaccent'] <mod_arg> { $*ignoreaccent = eval $<mod_arg>.Str } }
    token mod_internal:sym<:0a>   { ':' (\d+) ['a'|'ignoreaccent'] { $*ignoreaccent = $0 } }

    token mod_internal:sym<:s>    { ':s' 'igspace'? » { $*sigspace = 1 } }
    token mod_internal:sym<:!s>   { ':!s' 'igspace'? » { $*sigspace = 0 } }
    token mod_internal:sym<:s( )> { ':s' 'igspace'? <mod_arg> { $*sigspace = eval $<mod_arg>.Str } }
    token mod_internal:sym<:0s>   { ':' (\d+) 's' 'igspace'? » { $*sigspace = $0 } }

    token mod_internal:sym<:r>    { ':r' 'atchet'? » { $*ratchet = 1 } }
    token mod_internal:sym<:!r>   { ':!r' 'atchet'? » { $*ratchet = 0 } }
    token mod_internal:sym<:r( )> { ':r' 'atchet'? » <mod_arg> { $*ratchet = eval $<mod_arg>.Str } }
    token mod_internal:sym<:0r>   { ':' (\d+) 'r' 'atchet'? » { $*ratchet = $0 } }
 
    token mod_internal:sym<:Perl5>    { [':Perl5' | ':P5'] <.require_P5> [ :lang( $¢.cursor_fresh( %*LANG<P5Regex> ).unbalanced($*GOAL) ) <nibbler> ] }

    token mod_internal:adv {
        <?before ':' <.identifier> > [ :lang($¢.cursor_fresh(%*LANG<MAIN>)) <quotepair> ] { $/<sym> := «: $<quotepair><key>» }
    }

    token mod_internal:oops { ':'\w+ <.panic: "Unrecognized regex modifier"> }

    token quantifier:sym<*>  { <sym> <quantmod> }
    token quantifier:sym<+>  { <sym> <quantmod> }
    token quantifier:sym<?>  { <sym> <quantmod> }
    token quantifier:sym<**> { <sym> :: <normspace>? <quantmod> <normspace>?
        [
        | \d+ \s+ '..' <.panic: "Spaces not allowed in bare range">
        | \d+ [ '..' [ \d+ | '*' | <.panic: "Malformed range"> ] ]?
        | <embeddedblock>
        | <quantified_atom>
        ]
    }

    token quantifier:sym<~~> {
        [
        | '!' <sym>
        | <sym>
        ]
        <normspace> <quantified_atom> }

    token quantmod { ':'? [ '?' | '!' | '+' ]? }

} # end grammar

method require_P5 {
    require STD_P5;
    self;
}

method require_P6 {
    require STD_P6;
    self;
}

#################
# Symbol tables #
#################

method newpad ($needsig = 0) {
    my $oid = $*CURPAD.id;
    $ALL.{$oid} === $*CURPAD or die "internal error: current pad id is invalid";
    my $line = self.lineof(self.pos);
    my $id;
    if $*NEWPAD {
        $*NEWPAD.<OUTER::> = $*CURPAD.idref;
        $*CURPAD = $*NEWPAD;
        $*NEWPAD = 0;
        $id = $*CURPAD.id;
    }
    else {
        $id = 'MY:file<' ~ $*FILE<name> ~ '>:line(' ~ $line ~ '):pos(' ~ self.pos ~ ')';
        $*CURPAD = Stash.new(
            'OUTER::' => [$oid],
            '!file' => $*FILE, '!line' => $line,
            '!id' => [$id],
        );
    }
    $*CURPAD.<!NEEDSIG> = 1 if $needsig;
    $ALL.{$id} = $*CURPAD;
    self;
}

method finishpad {
    my $line = self.lineof(self.pos);
    $*CURPAD<$_> //= NAME.new( name => '$_', file => $*FILE, line => $line );
    $*CURPAD<$/> //= NAME.new( name => '$/', file => $*FILE, line => $line );
    $*CURPAD<$!> //= NAME.new( name => '$!', file => $*FILE, line => $line );
    $*SIGNUM = 0;
    self;
}

method getsig {
    my $pv = $*CURPAD.{'%?PLACEHOLDERS'};
    my $sig;
    if $*CURPAD.<!NEEDSIG>:delete {
        if $pv {
            my $h_ = $pv.<%_>:delete;
            my $a_ = $pv.<@_>:delete;
            $sig = join ', ', sort { substr($^a,1) leg substr($^b,1) }, keys %$pv;
            $sig ~= ', *@_' if $a_;
            $sig ~= ', *%_' if $h_;
        }
        else {
            $sig = '$_ is ref = OUTER::<$_>';
        }
        $*CURPAD.<$?SIGNATURE> = $sig;
    }
    else {
        $sig = $*CURPAD.<$?SIGNATURE>;
    }
    self.<sig> = self.makestr(TEXT => $sig);
    self.<pad> = $*CURPAD.idref;
    self;
}

method getdecl {
    self.<decl> = $*DECLARAND;
    self;
}

method is_name ($n, $curpad = $*CURPAD) {
    my $name = $n;
    say "is_name $name" if $*DEBUG +& DEBUG::symtab;

    my $curpkg = $*CURPKG;
    return True if $name ~~ /\:\:\(/;
    my @components = self.canonicalize_name($name);
    if @components > 1 {
        return True if @components[0] eq 'COMPILING::';
        return True if @components[0] eq 'CALLER::';
        return True if @components[0] eq 'CONTEXT::';
        if $curpkg = self.find_top_pkg(@components[0]) {
            say "Found lexical package ", @components[0] if $*DEBUG +& DEBUG::symtab;
            shift @components;
        }
        else {
            say "Looking for GLOBAL::<$name>" if $*DEBUG +& DEBUG::symtab;
            $curpkg = $*GLOBAL;
        }
        while @components > 1 {
            my $pkg = shift @components;
            $curpkg = $curpkg.{$pkg};
            return False unless $curpkg;
            say "Found $pkg okay" if $*DEBUG +& DEBUG::symtab;
        }
    }
    $name = shift(@components)//'';
    say "Looking for $name" if $*DEBUG +& DEBUG::symtab;
    return True if $name eq '';
    my $pad = $curpad;
    while $pad {
        say "Looking in ", $pad.id if $*DEBUG +& DEBUG::symtab;
        if $pad.{$name} {
            say "Found $name in ", $pad.id if $*DEBUG +& DEBUG::symtab;
            return True;
        }
        my $oid = $pad.<OUTER::>[0] || last;
        $pad = $ALL.{$oid};
    }
    return True if $curpkg.{$name};
    return True if $*GLOBAL.{$name};
    say "$name not found" if $*DEBUG +& DEBUG::symtab;
    return False;
}

method find_stash ($n, $curpad = $*CURPAD) {
    my $name = $n;
    say "find_stash $name" if $*DEBUG +& DEBUG::symtab;

    return () if $name ~~ /\:\:\(/;
    my @components = self.canonicalize_name($name);
    if @components > 1 {
        return () if @components[0] eq 'COMPILING::';
        return () if @components[0] eq 'CALLER::';
        return () if @components[0] eq 'CONTEXT::';
        if $curpad = self.find_top_pkg(@components[0]) {
            say "Found lexical package ", @components[0] if $*DEBUG +& DEBUG::symtab;
            shift @components;
        }
        else {
            say "Looking for GLOBAL::<$name>" if $*DEBUG +& DEBUG::symtab;
            $curpad = $*GLOBAL;
        }
        while @components > 1 {
            my $pad = shift @components;
            $curpad = $curpad.{$pad};
            return () unless $curpad;
            say "Found $pad okay" if $*DEBUG +& DEBUG::symtab;
        }
    }
    $name = shift(@components)//'';
    return $curpad if $name eq '';

    my $pad = $curpad;
    while $pad {
        return $_ if $_ = $pad.{$name};
        my $oid = $pad.<OUTER::>[0] || last;
        $pad = $ALL.{$oid};
    }
    return $_ if $_ = $curpad.{$name};
    return $_ if $_ = $*GLOBAL.{$name};
    return ();
}

method find_top_pkg ($name) {
    say "find_top_pkg $name" if $*DEBUG +& DEBUG::symtab;
    if $name eq 'OUR::' {
        return $*CURPKG;
    }
    elsif $name eq 'MY::' {
        return $*CURPAD;
    }
    elsif $name eq 'CORE::' {
        return $*CORE;
    }
    elsif $name eq 'SETTING::' {
        return $*SETTING;
    }
    elsif $name eq 'UNIT::' {
        return $*UNIT;
    }
    # everything is somewhere in lexical scope (we hope)
    my $pad = $*CURPAD;
    while $pad {
        return $pad.{$name} if $pad.{$name};
        my $oid = $pad.<OUTER::>[0] || last;
        $pad = $ALL.{$oid};
    }
    return 0;
}

method add_name ($name) {
    my $scope = $*SCOPE || 'my';
    return self if $scope eq 'anon';
    say "Adding $scope $name" if $*DEBUG +& DEBUG::symtab;
    if $scope eq 'augment' or $scope eq 'supersede' {
        self.is_name($name) or self.worry("Can't $scope something that doesn't exist");
    }
    else {
        if $scope eq 'our' {
            self.add_our_name($name);
        }
        else {
            self.add_my_name($name);
        }
    }
    self;
}

method add_my_name ($n, $d = Nil, $p = Nil) {   # XXX gimme doesn't hand optionals right
    my $name = $n;
    say "add_my_name $name in ", $*CURPAD.id if $*DEBUG +& DEBUG::symtab;
    return self if $name ~~ /\:\:\(/;
    my $curstash = $*CURPAD;
    my @components = self.canonicalize_name($name);
    my $sid = $curstash.id // '???';
    while @components > 1 {
        my $pkg = shift @components;
        $sid ~= "::$pkg";
        my $newstash = $curstash.{$pkg} //= Stash.new(
            'PARENT::' => $curstash.idref,
            '!stub' => 1,
            '!id' => [$sid] );
        say "Adding new package $pkg in ", $curstash.id if $*DEBUG +& DEBUG::symtab;
        $curstash = $newstash;
    }
    $name = my $vname = shift @components;
    return self unless defined $name and $name ne '';
    return self if $name eq '$' or $name eq '@' or $name eq '%';
    if $name ~~ /\:/ {
        $name ~~ s/\:.*//;
    }

    # This may just be a lexical alias to "our" and such,
    # so reuse $*DECLARAND pointer if it's there.
    my $declaring = $d // NAME.new(
        xpad => $curstash.idref,
        name => $name,
        file => $*FILE, line => self.line,
        mult => ($*MULTINESS||'only'),
    );
    my $old = $curstash.{$name};
    if $old and $old<line> and not $old<stub> {
        say "$name exists, curstash = ", $curstash.id if $*DEBUG +& DEBUG::symtab;
        my $omult = $old<mult> // '';
        if $declaring === $old {}  # already did this, probably enum
        elsif $*SCOPE eq 'use' {}
        elsif $*MULTINESS eq 'multi' and $omult ne 'only' {}
        elsif $omult eq 'proto' {}
        elsif $*PKGDECL eq 'role' {}
        elsif $*SIGNUM and $old<signum> and $*SIGNUM != $old<signum> {
            $old<signum> = $*SIGNUM;
        }
        else {
            my $ofile = $old.file // 0;
            my $oline = $old.line // '???';
            my $loc = '';
            if $ofile {
                if $ofile !=== $*FILE {
                    my $oname = $ofile<name>;
                    $loc = " (from $oname line $oline)";
                }
                else {
                    $loc = " (from line $oline)";
                }
            }
            if $old.opad {
                self.panic("Lexical symbol '$name'$loc is already bound to an outer scope implicitly\n  and must therefore be rewritten explicitly as '" ~ $old.name ~ "' before you can\n  unambiguously declare a new '$name' in the same scope");
            }
            elsif $name ~~ /^\w/ {
                self.panic("Illegal redeclaration of symbol '$name'$loc");
            }
            elsif $name ~~ s/^\&// {
                self.panic("Illegal redeclaration of routine '$name'$loc");
            }
            else {  # XXX eventually check for conformant arrays here
                self.worry("Useless redeclaration of variable $name$loc");
            }
        }
    }
    else {
        $*DECLARAND = $curstash.{$name} = $declaring;
        $curstash.{$vname} = $declaring unless $vname eq $name;
        $*DECLARAND<inpad> = $curstash.idref;
        $*DECLARAND<signum> = $*SIGNUM if $*SIGNUM;
        $*DECLARAND<const> ||= 1 if $*IN_DECL eq 'constant';
        if !$*DECLARAND<const> and $name ~~ /^\w+$/ {
            $curstash.{"&$name"} //= $curstash.{$name};
            $sid ~= "::$name";
            $*NEWPAD = $curstash.{$name ~ '::'} //= ($p // Stash.new(
                'PARENT::' => $curstash.idref,
                '!file' => $*FILE, '!line' => self.line,
                '!id' => [$sid] ));
        }
    }
    self;
}

method add_our_name ($n) {
    my $name = $n;
    say "add_our_name $name in " ~ $*CURPKG.id if $*DEBUG +& DEBUG::symtab;
    return self if $name ~~ /\:\:\(/;
    my $curstash = $*CURPKG;
    say "curstash $curstash global $*GLOBAL ", join ' ', %$*GLOBAL if $*DEBUG +& DEBUG::symtab;
    $name ~~ s/\:ver\<.*?\>//;
    $name ~~ s/\:auth\<.*?\>//;
    my @components = self.canonicalize_name($name);
    if @components > 1 {
        my $c = self.find_top_pkg(@components[0]);
        if $c {
            shift @components;
            $curstash = $c;
        }
    }
    my $sid = $curstash.id // '???';
    while @components > 1 {
        my $pkg = shift @components;
        $sid ~= "::$pkg";
        my $newstash = $curstash.{$pkg} //= Stash.new(
            'PARENT::' => $curstash.idref,
            '!stub' => 1,
            '!id' => [$sid] );
        $curstash = $newstash;
        say "Adding new package $pkg in $curstash " if $*DEBUG +& DEBUG::symtab;
    }
    $name = my $vname = shift @components;
    return self unless defined $name and $name ne '';
    if $name ~~ /\:/ {
        $name ~~ s/\:.*//;
    }

    my $declaring = $*DECLARAND // NAME.new(
        xpad => $curstash.idref,
        name => $name,
        file => $*FILE, line => self.line,
        mult => ($*MULTINESS||'only'),
    );
    my $old = $curstash.{$name};
    if $old and $old<line> and not $old<stub> {
        my $omult = $old<mult> // '';
        if $declaring === $old {} # already did it somehow
        elsif $*SCOPE eq 'use' {}
        elsif $*MULTINESS eq 'multi' and $omult ne 'only' {}
        elsif $omult eq 'proto' {}
        elsif $*PKGDECL eq 'role' {}
        else {
            my $ofile = $old.file // 0;
            my $oline = $old.line // '???';
            my $loc = '';
            if $ofile {
                if $ofile !=== $*FILE {
                    my $oname = $ofile<name>;
                    $loc = " (from $oname line $oline)";
                }
                else {
                    $loc = " (from line $oline)";
                }
            }
            $sid = self.clean_id($sid, $name);
            if $name ~~ /^\w/ {
                self.panic("Illegal redeclaration of symbol '$sid'$loc");
            }
            elsif $name ~~ /^\&/ {
                self.panic("Illegal redeclaration of routine '$sid'$loc");
            }
            else {  # XXX eventually check for conformant arrays here
                # (redeclaration of identical package vars is not useless)
            }
        }
    }
    else {
        $*DECLARAND = $curstash.{$name} = $declaring;
        $curstash.{$vname} = $declaring unless $vname eq $name;
        $*DECLARAND<inpkg> = $curstash.idref;
        if $name ~~ /^\w+$/ and $*IN_DECL ne 'constant' {
            $curstash.{"&$name"} //= $declaring;
            $sid ~= "::$name";
            $*NEWPKG = $curstash.{$name ~ '::'} //= Stash.new(
                'PARENT::' => $curstash.idref,
                '!file' => $*FILE, '!line' => self.line,
                '!id' => [$sid] );
        }
    }
    self.add_my_name($n, $declaring, $curstash.{$name ~ '::'}) if $curstash === $*CURPKG;   # the lexical alias
    self;
}

method add_mystery ($name,$pos,$ctx) {
    return self if $*IN_PANIC;
    if not self.is_known($name) {
        say "add_mystery $name $*CURPAD" if $*DEBUG +& DEBUG::symtab;
        %*MYSTERY{$name}.<pad> = $*CURPAD;
        %*MYSTERY{$name}.<ctx> = $ctx;
        %*MYSTERY{$name}.<line> ~= ',' if %*MYSTERY{$name}.<line>;
        %*MYSTERY{$name}.<line> ~= self.lineof($pos);
    }
    else {
        say "$name is known" if $*DEBUG +& DEBUG::symtab;
    }
    self;
}

method explain_mystery() {
    my %post_types;
    my %unk_types;
    my %unk_routines;
    my $m = '';
    for keys(%*MYSTERY) {
        my $p = %*MYSTERY{$_}.<pad>;
        if self.is_name($_, $p) {
            # types may not be post-declared
            %post_types{$_} = %*MYSTERY{$_};
            next;
        }

        next if self.is_known($_, $p) or self.is_known('&' ~ $_, $p);

        # just a guess, but good enough to improve error reporting
        if $_ lt 'a' {
            %unk_types{$_} = %*MYSTERY{$_};
        }
        else {
            %unk_routines{$_} = %*MYSTERY{$_};
        }
    }
    if %post_types {
        my @tmp = sort keys(%post_types);
        $m ~= "Illegally post-declared type" ~ ('s' x (@tmp != 1)) ~ ":\n";
        for @tmp {
            $m ~= "\t'$_' used at line " ~ %post_types{$_}.<line> ~ "\n";
        }
    }
    if %unk_types {
        my @tmp = sort keys(%unk_types);
        $m ~= "Undeclared name" ~ ('s' x (@tmp != 1)) ~ ":\n";
        for @tmp {
            $m ~= "\t'$_' used at line " ~ %unk_types{$_}.<line> ~ "\n";
        }
    }
    if %unk_routines {
        my @tmp = sort keys(%unk_routines);
        $m ~= "Undeclared routine" ~ ('s' x (@tmp != 1)) ~ ":\n";
        for @tmp {
            $m ~= "\t'$_' used at line " ~ %unk_routines{$_}.<line> ~ "\n";
        }
    }
    $m;
}

method load_setting ($setting) {
    $ALL = self.load_pad($setting);

    $*CORE = $ALL<CORE>;
    $*CORE.<!id> //= ['CORE'];

    $*SETTING = $ALL<SETTING>;
    $*CURPAD = $*SETTING;

    $*GLOBAL = $*CORE.<GLOBAL::> = Stash.new(
        '!file' => $*FILE, '!line' => 1,
        '!id' => ['GLOBAL'],
    );
    $*CURPKG = $*GLOBAL;
}

method is_known ($n, $curpad = $*CURPAD) {
    my $name = $n;
    say "is_known $name" if $*DEBUG +& DEBUG::symtab;
    return True if $*QUASIMODO;
    return True if $*CURPKG.{$name};
    my $curpkg = $*CURPKG;
    my @components = self.canonicalize_name($name);
    if @components > 1 {
        return True if @components[0] eq 'COMPILING::';
        return True if @components[0] eq 'CALLER::';
        return True if @components[0] eq 'CONTEXT::';
        if $curpkg = self.find_top_pkg(@components[0]) {
            say "Found lexical package ", @components[0] if $*DEBUG +& DEBUG::symtab;
            shift @components;
        }
        else {
            say "Looking for GLOBAL::<$name>" if $*DEBUG +& DEBUG::symtab;
            $curpkg = $*GLOBAL;
        }
        while @components > 1 {
            my $pkg = shift @components;
            say "Looking for $pkg in $curpkg ", join ' ', keys(%$curpkg) if $*DEBUG +& DEBUG::symtab;
            $curpkg = $curpkg.{$pkg};
            return False unless $curpkg;
            say "Found $pkg okay, now in $curpkg " if $*DEBUG +& DEBUG::symtab;
        }
    }

    $name = shift(@components)//'';
    say "Final component is $name" if $*DEBUG +& DEBUG::symtab;
    return True if $name eq '';
    if $curpkg.{$name} {
        say "Found" if $*DEBUG +& DEBUG::symtab;
        return True;
    }

    my $pad = $curpad;
    my $outer = 0;
    while $pad {
        say "Looking in ", $pad.id if $*DEBUG +& DEBUG::symtab;
        if $pad.{$name} {
            say "Found $name in ", $pad.id if $*DEBUG +& DEBUG::symtab;
            if $outer { # fake up an alias to outer symbol to catch reclaration
                my $n = $pad.{$name};
                $curpad.{$name} = NAME.new(
                    xpad => $pad.idref,
                    opad => $pad.idref,
                    name => ("OUTER::" x $outer) ~ "<$name>",
                    file => $*FILE, line => self.line,
                    mult => 'only',
                );
            }
            return True;
        }
        my $oid = $pad.<OUTER::>[0] || last;
        say $oid // "No OUTER" if $*DEBUG +& DEBUG::symtab;
        $pad = $ALL.{$oid};
        $outer++;
    }
    say "Not Found" if $*DEBUG +& DEBUG::symtab;

    return False;
}


method add_routine ($name) {
    my $vname = '&' ~ $name;
    self.add_name($vname);
    self;
}

method add_variable ($name) {
    my $scope = $*SCOPE || 'our';
    return self if $scope eq 'anon';
    if $scope eq 'our' {
        self.add_our_name($name);
    }
    else {
        self.add_my_name($name);
    }
    self;
}

method add_placeholder($name) {
    my $*IN_DECL = 'variable';
    if $*SIGNUM {
        self.panic("Placeholder variable $name not allowed in signature");
    }
    elsif my $siggy = $*CURPAD.<$?SIGNATURE> {
        self.panic("Placeholder variable $name cannot override existing signature $siggy");
    }
    if not $*CURPAD.<!NEEDSIG> {
        self.panic("Placeholder variable $name cannot be used in this kind of block");
    }
    self.add_my_name($name);
    $name ~~ s/\^//;
    $name = ':' ~ $name if $name ~~ s/\://;
    $*CURPAD.{'%?PLACEHOLDERS'}{$name}++;
    self;
}

method check_variable ($variable) {
    my $name = $variable.Str;
    say "check_variable $name" if $*DEBUG +& DEBUG::symtab;
    my ($sigil, $twigil, $first) = $name ~~ /(\W)(\W*)(.?)/;
    given $twigil {
        when '' {
            my $ok = 0;
            $ok = 1 if $name ~~ /::/;
            $ok ||= $*IN_DECL;
            $ok ||= $sigil eq '&';
            $ok ||= $first lt 'A';
            $ok ||= self.is_known($name);
            if not $ok {
                if $name eq '@_' or $name eq '%_' {
                    $variable.add_placeholder($name);
                }
                else {
                    $variable.worry("Variable $name is not predeclared");
                }
            }
        }
        when '^' {
            my $*MULTINESS = 'multi';
            $variable.add_placeholder($name);
        }
        when ':' {
            my $*MULTINESS = 'multi';
            $variable.add_placeholder($name);
        }
        when '~' {
            return %*LANG.{substr($name,2)};
        }
        when '?' {
            if $name ~~ /\:\:/ {
                my ($first) = self.canonicalize_name($name);
                $variable.worry("Unrecognized variable: $name") unless $first ~~ /^(CALLER|CONTEXT|OUTER|MY|SETTING|CORE)$/;
            }
            else {
                # search upward through languages to STD
                my $v = $variable.lookup_compiler_var($name);
                $variable.<value> = $v if $v;
            }
        }
    }
    self;
}

method lookup_compiler_var($name) {

    # see if they did "constant $?FOO = something" earlier
    my $lex = $*CURPAD.{$name};
    if defined $lex {
        if $lex.<thunk>:exists {
            return $lex.<thunk>.();
        }
        else {
            return $lex.<value>;
        }
    }

    given $name {
        when '$?FILE'     { return $*FILE<name>; }
        when '$?LINE'     { return self.lineof(self.pos); }
        when '$?POSITION' { return self.pos; }

        when '$?LANG'     { return item %*LANG; }

        when '$?LEXPAD'   { return $*CURPAD; }

        when '$?PACKAGE'  { return $*CURPKG; }
        when '$?MODULE'   { return $*CURPKG; } #  XXX should scan
        when '$?CLASS'    { return $*CURPKG; } #  XXX should scan
        when '$?ROLE'     { return $*CURPKG; } #  XXX should scan
        when '$?GRAMMAR'  { return $*CURPKG; } #  XXX should scan

        when '$?PACKAGENAME' { return $*CURPKG.id }

        when '$?OS'       { return 'unimpl'; }
        when '$?DISTRO'   { return 'unimpl'; }
        when '$?VM'       { return 'unimpl'; }
        when '$?XVM'      { return 'unimpl'; }
        when '$?PERL'     { return 'unimpl'; }

        when '$?USAGE'    { return 'unimpl'; }

        when '&?ROUTINE'  { return 'unimpl'; }
        when '&?BLOCK'    { return 'unimpl'; }

        when '%?CONFIG'    { return 'unimpl'; }
        when '%?DEEPMAGIC' { return 'unimpl'; }

        # (derived grammars should default to nextsame, terminating here)
        default { self.worry("Unrecognized variable: $name"); return 0; }
    }
}

####################
# Service Routines #
####################

method panic (Str $s) {
    my $m;
    my $here = self;

    # Have we backed off recently?
    my $highvalid = self.pos <= $*HIGHWATER;

    $here = self.cursor($*HIGHWATER) if $highvalid;

    my $first = $here.lineof($*LAST_NIBBLE.<_from>);
    my $last = $here.lineof($*LAST_NIBBLE.<_pos>);
    if $first != $last {
        if $here.lineof($here.pos) == $last {
            $m ~= "\n(Possible runaway string from line $first)";
        }
        else {
            $first = $here.lineof($*LAST_NIBBLE_MULTILINE.<_from>);
            $last = $here.lineof($*LAST_NIBBLE_MULTILINE.<_pos>);
            # the bigger the string (in lines), the further back we suspect it
            if $here.lineof($here.pos) - $last < $last - $first  {
                $m ~= "\n(Possible runaway string from line $first to line $last)";
            }
        }
    }

    $m ~= "\n" ~ $s;

    if $highvalid {
        $m ~= $*HIGHMESS if $*HIGHMESS;
        $*HIGHMESS = $m;
    }
    else {
        # not in backoff, so at "bleeding edge", as it were... therefore probably
        # the exception will be caught and re-panicked later, so remember message
        $*HIGHMESS ~= "\n" ~ $s;
    }

    $m ~= $here.locmess;

    if $highvalid and %$*HIGHEXPECT {
        my @keys = sort keys %$*HIGHEXPECT;
        if @keys > 1 {
            $m ~= "\n    expecting any of:\n\t" ~ join("\n\t", sort keys %$*HIGHEXPECT);
        }
        else {
            $m ~= "\n    expecting @keys" unless @keys[0] eq 'whitespace';
        }
    }
    if $m ~~ /infix|nofun/ and not $m ~~ /regex/ {
        die "Recursive panic" if $*IN_PANIC;
        $*IN_PANIC++;
        my @t = try { $here.termish };
        $*IN_PANIC--;
        if @t {
            if @*MEMOS[$here.pos - 1]<acomp> {
                $m ~~ s|Confused|Two terms in a row (preceding is not a valid reduce operator)|;
            }
            else {
                $m ~~ s|Confused|Two terms in a row|;
            }
        }
    }

    if @*WORRIES {
        $m ~= "\nOther potential difficulties:\n  " ~ join( "\n  ", @*WORRIES);
    }
    $m ~= "\n";
    $m ~= self.explain_mystery();

    die $Cursor::RED ~ '===' ~ $Cursor::CLEAR ~ 'SORRY!' ~ $Cursor::RED ~ '===' ~ $Cursor::CLEAR ~ $m;
}

method worry (Str $s) {
    push @*WORRIES, $s ~ self.locmess;
    self;
}

method locmess () {
    my $pos = self.pos;
    my $line = self.lineof($pos);
    if $pos >= @*MEMOS - 2 {
        $pos = @*MEMOS - 3;
        $line = ($line - 1) ~ " (EOF)";
    }
    my $pre = substr($*ORIG, 0, $pos);
    $pre = substr($pre, -40, 40);
    1 while $pre ~~ s!.*\n!!;
    $pre = '<BOL>' if $pre eq '';
    my $post = substr($*ORIG, $pos, 40);
    1 while $post ~~ s!(\n.*)!!;
    $post = '<EOL>' if $post eq '';
    " at " ~ $*FILE<name> ~ " line $line:\n------> " ~ $Cursor::GREEN ~ $pre ~ $Cursor::YELLOW ~ $*PERL6HERE ~ $Cursor::RED ~ 
        "$post$Cursor::CLEAR";
}

method line {
    self.lineof(self.pos);
}

method lineof ($p) {
    return 1 unless defined $p;
    my $line = @*MEMOS[$p]<L>;
    return $line if $line;
    $line = 0;
    my $pos = 0;
    my @text = split(/^/,$*ORIG);   # XXX p5ism, should be ^^
    for @text {
        $line++;
        @*MEMOS[$pos++]<L> = $line
            for 1 .. chars($_);
    }
    @*MEMOS[$pos++]<L> = $line;
    return @*MEMOS[$p]<L> // 0;
}

method SETGOAL { }
method FAILGOAL (Str $stop, Str $name) {
    self.panic("Unable to parse $name; couldn't find final '$stop'");
}

# "when" arg assumes more things will become obsolete after Perl 6 comes out...
method obs (Str $old, Str $new, Str $when = ' in Perl 6') {
    %$*HIGHEXPECT = ();
    self.panic("Unsupported use of $old;$when please use $new");
}

method worryobs (Str $old, Str $new, Str $when = ' in Perl 6') {
    self.worry("Unsupported use of $old;$when please use $new");
    self;
}

method badinfix (Str $bad = $*sym) {
    self.panic("Preceding context expects a term, but found infix $bad instead");
}

# Since most keys are valid prefix operators or terms, this rule is difficult
# to reach ('say »+«' works), but it's okay as a last-ditch default anyway.
token term:sym<miscbad> {
    :my $bad;
    {} <!{ $*QSIGIL }> <?before $bad = <.infixish>> <.badinfix($bad.Str)>
}

## vim: expandtab sw=4 ft=perl6
