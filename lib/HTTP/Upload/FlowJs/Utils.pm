package HTTP::Upload::FlowJs::Util;

use strict;
use warnings;

use vars qw(@ISA @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(clean_fragment mime_detect);

use feature "fc";
use Unicode::Normalize;

#
# mime detect
#

my $mime_detect_fallback;
sub mime_detect {
    if ( not defined $mime_detect_fallback ) {
        eval {
            require MIME::Detect;
            $mime_detect_fallback = 0;
            1;
        } or do {
            $mime_detect_fallback = 1;
        }
    }

    if ( $mime_detect_fallback ) {
        return undef
    }
    elsif ( defined $mime_detect_fallback ) {
        return MIME::Detect->new(@_);
    }
}


#
# clean_fragment
#

my $clean_fragment_fallback;
sub clean_fragment {
    if ( not defined $clean_fragment_fallback ) {
        eval {
            require Text::CleanFragment;
            $clean_fragment_fallback = 0;
            1;
        } or do {
            $clean_fragment_fallback = 1;
        }
    }

    if ( $clean_fragment_fallback ) {
        return clean_fragment_fallback(@_);
    }
    elsif ( defined $clean_fragment_fallback ) {
        return Text::CleanFragment::clean_fragment(@_);
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
