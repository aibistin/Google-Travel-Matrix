#===============================================================================
#
#         FILE: Matrix.pm
#
#  DESCRIPTION: Module to access the Google Travel Matrix
# https://developers.google.com/maps/documentation/distancematrix/
#
# Each Query Is limited by the number of elements.
#   Elements = Origins * Destinations
#
#  Limitations:
#    100 Elements per request;
#    1 Request Per 10 seconds.
#    2400 Requests per 24 hour period.
#
#
#  Business Limitations:
#    625 Elements per request;
#    1000 elements per 10 seconds;
#    100,000 elements per 24 hour period;
#
#===============================================================================
# Use of the Distance Matrix API must relate to the display of information on a
# Google Map; for example,  to determine origin-destination pairs that fall
# within a specific driving time from one another,  before requesting and
# displaying those destinations on a map. Use of the service in an application
# that doesn't display a Google map is prohibited.
#===============================================================================
#
#{
#    "destination_addresses" : [
#        "San Francisco,  Californie,  États-Unis",
#        "Victoria,  BC,  Canada" ],
#    "origin_addresses" : [
#        "Vancouver,  BC,  Canada",
#        "Seattle,  État de Washington,  États-Unis"
#        ],
#      "rows" : [
#        {
#            "elements" : [
#                {
#                    "distance" : { "text" : "1 678 km", "value" : 1678186 },
#                    "duration" : { "text" : "3 jours 20 heures", "value" : 330805 },
#                    "status" : "OK"
#                },
#                {
#                    "distance" : { "text" : "135 km", "value" : 134638 },
#                    "duration" : { "text" : "6 heures 37 minutes", "value" : 23826 },
#                    "status" : "OK"
#                }
#            ]
#        },
#        {
#            "elements" : [
#                {
#                    "distance" : { "text" : "1 428 km", "value" : 1428353 },
#                    "duration" : { "text" : "3 jours 6 heures", "value" : 280158 },
#                    "status" : "OK"
#                },
#                {
#                    "distance" : { "text" : "146 km", "value" : 146328 },
#                    "duration" : { "text" : "3 heures 12 minutes", "value" : 11512 },
#                    "status" : "OK"
#                }
#            ]
#        }
#      ],
#      "status" : "OK"
#}
#
#
#===============================================================================
package Google::Travel::Matrix;
# ABSTRACT: To access the Google Travel Matrix API .
our $VERSION = '0.1';
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Params::Validate;
use MooseX::UndefTolerant::Attribute;
use namespace::autoclean;
use Try::Tiny;

use LWP::UserAgent;
use JSON::Any;
use JSON;

use XML::Simple;
use URI;
use utf8::all;

use Log::Any qw/$log/;
use Data::Dump qw/dump/;

#-------------------------------------------------------------------------------
#  Globals
#-------------------------------------------------------------------------------
use Readonly;
Readonly my $TRUE               => 1;
Readonly my $FALSE              => 0;
Readonly my $YES                => 1;
Readonly my $NO                 => 0;
Readonly my $FAIL               => undef;
Readonly my @valid_travel_modes => qw( driving walking bicycling );

#------ API Globals
Readonly my $JSON => 'json';
Readonly my $XML  => 'xml';
Readonly my $GOOGLE_TRAVEL_MATRIX_URL =>
    "http://maps.googleapis.com/maps/api/distancematrix/";

#------ Google Matrix Response status codes
Readonly my $VALID_REQ               => 'OK';
Readonly my $INVALID_REQ             => 'INVALID_REQUEST';
Readonly my $MAX_ELEMENTS_EXCEEDED   => 'MAX_ELEMENTS_EXCEEDED';
Readonly my $MAX_DIMENSIONS_EXCEEDED => 'MAX_DIMENSIONS_EXCEEDED';
Readonly my $MAX_QUERY_LIMIT         => 'MAX_QUERY_LIMIT';
Readonly my $REQ_DENIED              => 'REQUEST_DENIED';
Readonly my $UNKNOWN_ERROR           => 'UNKNOWN_ERROR';

#------ Google Matrix Element status codes
Readonly my $OK           => 'OK';
Readonly my $NOT_FOUND    => 'NOT_FOUND';
Readonly my $ZERO_RESULTS => 'ZERO_RESULTS';

#------ Conversions and validation globals
#       Some I added just for fun
Readonly my %convert_to_valid_travel_mode => (
    d         => 'driving',
    c         => 'driving',
    car       => 'driving',
    drive     => 'driving',
    driving   => 'driving',
    motorbike => 'driving',
    scooter   => 'driving',
    truck     => 'driving',
    w         => 'walking',
    foot      => 'walking',
    run       => 'walking',
    walk      => 'walking',
    walking   => 'walking',
    b         => 'bicycling',
    bicycling => 'bicycling',
    cycling   => 'bicycling',
    cycle     => 'bicycling',
);

#------- Google only permits one(out of a possible 2) avoidances
#        With a little sarcasm added for good measure:
Readonly my @valid_travel_avoids        => qw( tolls highways );
Readonly my %convert_to_valid_avoidance => (
    t         => 'tolls',
    tolls     => 'tolls',
    toll      => 'tolls',
    extorsion => 'tolls',
    h         => 'highways',
    highway   => 'highways',
    highways  => 'highways',
);

Readonly my %convert_to_valid_units => (
    i          => 'imperial',
    imperial   => 'imperial',
    miles      => 'imperial',
    cavemanish => 'imperial',
    m          => 'metric',
    meter      => 'metric',
    metric     => 'metric',
    meters     => 'metric',
    metres     => 'metric',
);

Readonly my %convert_to_js_bool => (
    1     => 'true',
    true  => 'true',
    yes   => 'true',
    y     => 'true',
    0     => 'false',
    false => 'false',
    no    => 'false',
);

Readonly my @language_codes => qw/
    ar  eu  bg  bn  ca  cs  da  de  el  en
    es  eu  fa  fi  fil  fr  gl gu  hi  hr
    hu  id  it  iw  ja  kn  ko lt  lv   ml
    mr  nl  nn  no  or  pl  pt pt-BR  pt-PT
    rm  ro  ru  sk  sl  sr  sv  tl  ta  te
    th  tr  uk  vi  zh-CN  zh-TW  /;

Readonly my %language_code_hash => map { $_ => $TRUE } @language_codes;

#-------------------------------------------------------------------------------
# Private Methods
#-------------------------------------------------------------------------------
my ($is_valid_travel_mode,                $is_valid_travel_avoidance,
    $is_valid_language_code,              $convert_href_to_addr_str,
    $convert_aref_to_string_of_addresses, $str_full_trim
);

#-------------------------------------------------------------------------------
#  Goal:
#  Get: Distance and Time Beweeen each point in the Matrix
#  Convert it to DOT travel time.
#
# How.
#
# Provide a Start (Origin) and an End (Destination )
# or Multiple Starts and Ends
# Each End becomes the start of the next Element
#    Origin
#      1 => Destination 1,
#      Origin 2 ( Destination 1 ) => Destination 2,
#      Origin 3 ( Destination 2 ) => Destination 3,
#      ... . Origin n(
#        n == 1
#        ? ( Origin 1 )
#        : ( Destination n + 1 ) => Destination n
#
#          Pass the addresses as an ArrayRef
#          . The addresses will be processed in order
#          . Must be at least two addresses
#          . Each Address Element Must at least have a City,
#        State, Country
#
#          Call The Google API
#
#          Parse the REsults using some kind of JASON Parser
#
#------------------------------------------------------------------------------
# OUTPUT
#
# Request
#   http://maps.googleapis.com/maps/api/distancematrix/output?parameters
#       or preferably
#   https://maps.googleapis.com/maps/api/distancematrix/output?parameters
#
#    output params can be either jason or xml (the former is recommended)
#JASON request
#   http://maps.googleapis.com/maps/api/distancematrix/json?origins=Vancouver+BC|Seattle&destinations=San+Francisco|Victoria+BC&mode=bicycling&language=fr-FR&sensor=false

#-------------------------------------------------------------------------------
#  My Types
#-------------------------------------------------------------------------------

#subtype 'GoogleParams' => as 'HashRef' => where => {\&_validate_google_params($_)}
# => message { 'Invalid Google parameters!'};

#----- Google Paramaters
subtype 'GoogBool', as 'Str',
    where { $_ =~ /^(true|false)$/ },
    message { 'Must be either true or false. Not ' . $_ };

coerce 'GoogBool',
    from 'Str', via { $convert_to_js_bool{ lc $_ } },
    from 'Int', via { $_ >= 1 ? 'true' : 'false' };

#------ Google Output Format (json or xml). Not a Google Param
enum 'GoogOutput', [qw(json  xml)];

coerce 'GoogOutput', from 'Str', via { lc $_ };

#------ Acceptable Google travel modes , driving,walking, bicycling
subtype 'GoogTravelMode', as 'Str', where { $is_valid_travel_mode->($_) },
    message {
    "$_ is not a valid Google travel mode. Pick either driving, walking, or bicycling.";
    };
coerce 'GoogTravelMode', from 'Str',
    via { $convert_to_valid_travel_mode{ lc $_ } };

# Supported Languages Spreadsheet can be found here
# https://spreadsheets.google.com/pub?key=p9pdwsai2hDMsLkXsoM05KQ&gid=1
subtype 'GoogTravelLang', as 'Str',
    where { $is_valid_language_code->($_) },
    message {"$_ is not a valid Google language code"};

#------ What type of routes to avoid
subtype 'GoogTravelAvoid', as 'Str',
    where { $is_valid_travel_avoidance->($_) or ( $_ eq q// ) },
    message {"$_ is not a valid Google travel avoidance."};
coerce 'GoogTravelAvoid', from 'Str',
    via { $convert_to_valid_avoidance{ lc $_ } };

#------        Address's
#------        These are the only required attributes
subtype 'GoogAddrHref', as 'HashRef', where {
    ( exists $_->{address_1} && defined $_->{address_1} )
        && exists $_->{address_2}
        && ( exists $_->{city} && defined $_->{city} )
        && exists $_->{state}
        && ( exists $_->{country} && defined $_->{country} )
        && exists $_->{zip};
}, message { ( dump $_ ) . ' is not a valid Address Href!' };

subtype 'GoogAddr', as 'Str', where {
    defined($_)
        and ( length $_ >= 2 )
        and ( $_ =~ /,/ );
}, message { ( dump $_ ) . ' is not a valid Google Address String!' };

coerce 'GoogAddr',
    from 'Str',          via { $str_full_trim->($_) },
    from 'GoogAddrHref', via { $convert_href_to_addr_str->($_) },
    from 'ArrayRef[GoogAddr|GoogAddrHref]',
    via { $convert_aref_to_string_of_addresses->($_) };

#-------------------------------------------------------------------------------
#  Attributes
#-------------------------------------------------------------------------------
has 'output' => (
    is      => 'ro',
    isa     => 'GoogOutput',
    default => $JSON,
    coerce  => 1,
);

#-----  Travel sensor (like GPS ) true/false
has 'sensor' => (
    is      => 'ro',
    isa     => 'GoogBool',
    default => 'false',
    coerce  => 1,
);
has 'mode' => (
    is      => 'ro',
    isa     => 'GoogTravelMode',
    default => 'driving',
    coerce  => 1,
);
has 'language' => (
    is      => 'ro',
    isa     => 'GoogTravelLang',
    default => 'en',               # en = American
);
has 'avoid' => (
    traits  => [qw(MooseX::UndefTolerant::Attribute)],
    is      => 'ro',
    isa     => 'GoogTravelAvoid',
    default => '',
    coerce  => 1,
);

#------ Units of measurement
enum 'GoogTravelUnit', [qw(imperial metric)];
coerce 'GoogTravelUnit', from 'Str', via { $convert_to_valid_units{ lc $_ } };

has 'units' => (
    is      => 'ro',
    isa     => 'GoogTravelUnit',
    default => 'metric',
    coerce  => 1,
);


has 'origins' => (
    is  => 'rw',
    isa => 'GoogAddr',

    #   required => 1,
    coerce => 1,
);

#------ Array or destination addresses


has 'destinations' => (
    is  => 'rw',
    isa => 'GoogAddr',

    #    required => 1,
    coerce => 1,
);

#-------------------------------------------------------------------------------
#  Methods
#-------------------------------------------------------------------------------
sub build_the_request {
    my $self = shift;

    #------ May not need this
    #    my $origins      = $self->_format_origins();
    #    my $destinations = $self->_format_destinations();

#    my $i = 1;
#    $log->debug( 'Origins Array : ' . join "\nOrigin Address $i ", @$origins );
#    $log->debug( 'Destinations Array : ' . join "\nDestination Address $i++",
#        @$destinations );

#    my $q =
#"origins=\\@origins&destinations=\\@destinations&mode=" . $self->mode . "&language=en&sensor=false";

    my $query_params = $self->_matrix_query_params();

    my $uri = $self->_build_uri($query_params);

    my $response = $self->_call_google_api($uri);

    my $object;
    if ( $response->is_success ) {

       #            $log->debug('The Google response is : ' . dump $response);
        if ( $self->output eq $JSON ) {
            $object = $self->_convert_from_json($response);

           #            $log->debug( 'JSON decoded object: ' . dump $object );
        }
        else {
            $object = $self->_convert_from_xml($response);

            #            $log->debug( 'XML parsed data ' . $object );
        }
    }
    else {
        $log->error(
            "Got a bad response from Google.\n" . $response->status_line );
        confess $response->status_line;
    }
    return $object;
}

#-------------------------------------------------------------------------------
#  Stuff to put into a sub class
#-------------------------------------------------------------------------------


sub process_results {
    my $self   = shift;
    my $object = shift;

    $log->debug( 'Google Matrix Status : ' . $object->{status} );

    return $object->{status} unless ( $object->{status} eq $VALID_REQ );

}

#$matrix->{status}
#      $VALID_REQ               => 'OK';
#      $INVALID_REQ             => 'INVALID_REQUEST';
#      $MAX_ELEMENTS_EXCEEDED   => 'MAX_ELEMENTS_EXCEEDED';
#      $MAX_DIMENSIONS_EXCEEDED => 'MAX_DIMENSIONS_EXCEEDED';
#      $MAX_QUERY_LIMIT         => 'MAX_QUERY_LIMIT';
#      $REQ_DENIED              => 'REQUEST_DENIED';
#      $UNKNOWN_ERROR           => 'UNKNOWN_ERROR';


sub get_all_elements {
    my $self = shift;
    my %results_hash;
    my @elements_array;
    my $matrix = $self->build_the_request();

    $log->debug( 'Matrix status: ' . $matrix->{status} );
    return unless $matrix->{status} eq $VALID_REQ;

    #------ Get each combination for the origin destinationaddresses
    foreach my $origin_addr ( @{ $matrix->{origin_addresses} } ) {
        $log->debug( 'Origin Addr: ' . $origin_addr );

        #---Get results for current origination address
        my $row = shift @{ $matrix->{rows} };

        #------ Match origination address with all destination addressses
        foreach my $destination_addr ( @{ $matrix->{destination_addresses} } )
        {
            $log->debug( 'Destination Addr: ' . $destination_addr );

         #----- get the result for the current Origination -> Destination pair
            my $element = shift @{ $row->{elements} };

            #            $log->debug( 'Element: ' . dump $element );
            push @elements_array, {
                origin_address         => $origin_addr,
                destination_address    => $destination_addr,
                element_status         => $element->{status},
                element_duration_text  => $element->{duration}{text},
                element_duration_value => $element->{duration}{value},
                element_distance_text  => $element->{distance}{text},

                #------ This distance is ALWAYS in Meters.
                element_distance_value => $element->{distance}{value},
            };

        }
    }
    return \@elements_array;
}

#-------------------------------------------------------------------------------
#    Helper Methods
#-------------------------------------------------------------------------------


sub _get_formatted_addresses {
    my $self                   = shift;
    my $orig_or_dest_addresses = shift;
    return join( '|', @{ $self->$orig_or_dest_addresses } );
}

sub _get_formatted_origins {
    my $self = shift;
    return join( '|', @{ $self->origins } );
}


sub _get_formatted_destinations {
    my $self = shift;
    return join( '|', @{ $self->destinations } );
}


sub _matrix_query_params {
    my $self = shift;
    my $meta = __PACKAGE__->meta;
    my %query =
        map { $_->name => $self->{ $_->name } }

        #      grep { $_->name !~ /^(origins|destinations|output)/ }
        grep { $_->name !~ /^(output)/ } ( $meta->get_all_attributes );

  #    $query{origins}      = $self->_get_formatted_addresses('origins');
  #    $query{destinations} = $self->_get_formatted_addresses('destinations');

    #    $query{origins}      = $self->_get_formatted_origins;
    #    $query{destinations} = $self->_get_formatted_destinations;
    return \%query;
}


sub _build_uri {
    my $self          = shift;
    my $matrix_params = shift;

#Distance Matrix API URLs are restricted to 2048 characters,  before URL
#encoding. As some Distance Matrix API service URLs may involve many locations,
#be aware of this limit when constructing your URLs.
    my $uri = URI->new( $GOOGLE_TRAVEL_MATRIX_URL . $self->output . "?" );

    $uri->query_form($matrix_params);
    $log->debug( 'URI object : ' . dump $uri );
    return $uri;
}


sub _call_google_api {
    my $self = shift;
    my $uri  = shift;

    my $response;
    try {
        my $ua = LWP::UserAgent->new();

        #--- Examine these
        $ua->timeout(10);
        $ua->env_proxy;
        $response = $ua->get($uri);
    }
    catch {
        $log->error( "Failed to access Google API.\n" . $_ );
        confess($_);
    };

    $log->debug( 'LWP::UserAgent response is  '
            . ( $response->is_success ? 'OK!' : 'NOT OK!' ) );

    return $response;
}


sub _convert_from_json {
    my $self     = shift;
    my $response = shift;
    my $object;
    try {
        $object = decode_json $response->content;
    }
    catch {
        $log->error( "Failed to decode JSON Travel Matrix data.\n" . $_ );
    };
    return $object;
}


sub _convert_from_xml {
    my $self     = shift;
    my $response = shift;
    my ($xs);
    try {
        $xs =
            XMLin->( $response->content, ForceArray => [ 'row', 'element' ] );
    }
    catch {
        $log->error( "Failed to decode XML Travel Matrix data.\n" . $_ );
    };
    $log->debug( 'XML returned : ' . dump $xs );
    return $xs;
}

#-------------------------------------------------------------------------------
#  Private Subs
#-------------------------------------------------------------------------------

$is_valid_travel_mode = sub {
    my $mode = shift;
    for my $v_mode (@valid_travel_modes) {
        return $YES if ( $mode eq $v_mode );
    }
    return $NO;
};

$is_valid_travel_avoidance = sub {
    my $avoid = shift;
    for my $v_avoid (@valid_travel_avoids) {
        return $YES if ( lc($avoid) eq $v_avoid );
    }
    return $NO;
};

$is_valid_language_code = sub {
    return $language_code_hash{ lc shift };
};

$convert_href_to_addr_str = sub {
    my $addr_href = shift;
    return $str_full_trim->(
        $addr_href->{address_1}
            . (
            defined $addr_href->{address_2}
            ? ',' . $addr_href->{address_2}
            : q//
            )
            . ','
            . $addr_href->{city}
            . (
            defined $addr_href->{state} ? ',' . $addr_href->{state} : q// )
            . ','
            . $addr_href->{country}
            . ( defined $addr_href->{zip} ? ',' . $addr_href->{zip} : q// )
    );
};

$convert_aref_to_string_of_addresses = sub {
    my $addr_aref = shift;
    my $long_str;
    $long_str = join(
        '|',
        map {
            ( ref($_) eq 'HASH' )
                ? $convert_href_to_addr_str->($_)
                : ( $str_full_trim->($_) )
            } @$addr_aref
    );
    return $long_str;
};

$str_full_trim = sub {
    my $str = shift;
    $str =~ s/^\s+//s;
    $str =~ s/\s+$//s;
    $str =~ s/\s+/ /sg;
    return $str;
};

#-------------------------------------------------------------------------------
#  END
#-------------------------------------------------------------------------------
no Moose;
__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 NAME

Google::Travel::Matrix - To access the Google Travel Matrix API .

=head1 VERSION

version 0.1

=head2 origins
       An address string,  or string of addresses. Each address element must
       be delimited by a comma. If more than one address, then seperate each
       address with a '|'. 
       An address HashRef of this format 
       {
        address_1 => $address_1,
        address_2 => $address_2,
        city => $city,
        state => $state, 
        country => $country,
        zip => $zip, 
        }
        ,  will be coerced to a valid address string. 

       An arrayref of address strings and or address HashRefs  will be coerced into a compatible address(s)
       string(s).

=head2 destinations
    The destination addresses. Follows the same formatting rules as 'origins'

=head2 process_results
 See what we need from the results.
 Note::
      Each Row corresponds to an origin.
      Each element within a row corresponds to a paring of the origin 
      with a destination value.

=head2 get_all_elements
 Get the distances.
 Create a hash with the address,  

=head3 _get_formatted_origins
    Returns the origins address array, formatted for the Google API

=head3 _get_formatted_destinations
    Reurns the destinations address array, formatted for the Google API

=head3 _matrix_query_params
    Build and returns all the params for the Google Travel Matrix request
    as a HashRef.
    Use the formatted origins and destinations address's.
    Omits the requested output format specifier.

=head2 _build_uri
   Build and return the query URI.

=head2 _call_google_api
   Call the google travel matrix API.
   Returns the Google response

=head2 _convert_from_json
   Convert the Google response from JSON.

=head2 _convert_from_xml
   Convert the Google response from XML to a Perl Data Structure;

=head2 
    Readonly => %valid_google_languages (
        ar => ARABIC,
        eu => BASQUE,
        bg => BULGARIAN,
        bn => BENGALI,
        ca => CATALAN,
        cs => CZECH,
        da => DANISH,
        de => GERMAN,
        el => GREEK,
        en => ENGLISH,
        en-AU => ENGLISH(AUSTRALIAN),
        en-GB => ENGLISH( GREAT BRITAIN ),
        es => SPANISH,
        eu => BASQUE,
        fa => FARSI,
        fi => FINNISH,
        fil => FILIPINO,
        fr => FRENCH,
        gl => GALICIAN,
        gu => GUJARATI,
        hi => HINDI,
        hr => CROATIAN,
        hu => HUNGARIAN,
        id => INDONESIAN,
        it => ITALIAN,
        iw => HEBREW,
        ja => JAPANESE,
        kn => KANNADA,
        ko => KOREAN,
        lt => LITHUANIAN,
        lv => LATVIAN,
        ml => MALAYALAM,
        mr => MARATHI,
        nl => DUTCH,
        nn => NORWEGIAN NYNORSK,
        no => NORWEGIAN,
        or => ORIYA,
        pl => POLISH,
        pt => PORTUGUESE,
        pt-BR => PORTUGUESE(BRAZIL),
        pt-PT => PORTUGUESE(PORTUGAL),
        rm => ROMANSCH,
        ro => ROMANIAN,
        ru => RUSSIAN,
        sk => SLOVAK,
        sl => SLOVENIAN,
        sr => SERBIAN,
        sv => SWEDISH,
        tl => TAGALOG,
        ta => TAMIL,
        te => TELUGU,
        th => THAI,
        tr => TURKISH,
        uk => UKRAINIAN,
        vi => VIETNAMESE,
        zh-CN => CHINESE(SIMPLIFIED),
        zh-TW => CHINESE(TRADITIONAL),
    );

=head1 AUTHOR

Austin Kenny <aibistin.cionnaith@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Austin Kenny.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
