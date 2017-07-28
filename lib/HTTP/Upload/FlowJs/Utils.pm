package HTTP::Upload::FlowJs::Utils;

use strict;
use warnings;

use vars qw(@ISA @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(clean_fragment mime_detect);

use feature qw(fc);
use Unicode::Normalize;

BEGIN {
    # clean_fragment
    {
        eval { require Text::CleanFragment };
        my $subname = __PACKAGE__ . '::clean_fragment';
        no strict 'refs';
        if ( $@ ) {
            *{$subname} = \&clean_fragment_fallback;
        }
        else {
            *{$subname} = \&Text::CleanFragment::clean_fragment;
        }
    }


    # mime_detect
    {
        eval { require MIME::Detect };
        my $subname = __PACKAGE__ . '::mime_detect';
        no strict 'refs';
        if ( $@ ) {
            *{$subname} = sub { undef };
        }
        else {
            *{$subname} = sub { MIME::Detect->new(@_) };
        }
    }
}

sub clean_fragment_fallback {
    my @strings = @_;

    for( @strings ) {
        $_ = NFKD($_);
        s/([\x{80}-\x{300}])/fc($1)/eg;

        tr/['"\x{2019}]//d;     # Eliminate apostrophes
        tr/\x{300}-\x{36f}//d;
        s/[^a-zA-Z0-9.-]+/_/g;  # Replace all non-ascii by underscores, including whitespace
        s/-+/-/g;               # Squash dashes
        s/_(?:-_)+/-/g;         # Squash _-_ and _-_-_ to -
        s/^[-_]+//;             # Eliminate leading underscores
        s/[-_]+$//;             # Eliminate trailing underscores
        s/_(\W)/$1/;            # No underscore before - or .
     };
    wantarray ? @strings : $strings[0];
};

1;
