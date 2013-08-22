#===============================================================================
#
#         FILE: Matrix.pm
#
#  DESCRIPTION: Module to access the Google Distance Matrix
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

# ABSTRACT: To access the Google Distance Matrix API .
our $VERSION = '0.2';
use Moose;
use Moose::Util::TypeConstraints;

#use MooseX::Params::Validate;
use MooseX::UndefTolerant::Attribute;
use namespace::autoclean;
use Try::Tiny;

use LWP::UserAgent;
use JSON;
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

#------ LWP Globals
Readonly my $time_out => 180;    #This is the timeout from LWP::UserAgent

#------ API Globals
Readonly my $JSON => 'json';
Readonly my $XML  => 'xml';
Readonly my $GOOGLE_TRAVEL_MATRIX_URL =>
  "http://maps.googleapis.com/maps/api/distancematrix/";

#------ Google Matrix Response status messages
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
my (
    $is_valid_travel_mode,                $is_valid_travel_avoidance,
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
subtype 'GoogDistanceMode', as 'Str', where { $is_valid_travel_mode->($_) },
  message {
"$_ is not a valid Google travel mode. Pick either driving, walking, or bicycling.";
  };
coerce 'GoogDistanceMode', from 'Str',
  via { $convert_to_valid_travel_mode{ lc $_ } };

# Supported Languages Spreadsheet can be found here
# https://spreadsheets.google.com/pub?key=p9pdwsai2hDMsLkXsoM05KQ&gid=1
subtype 'GoogDistanceLang', as 'Str',
  where { $is_valid_language_code->($_) },
  message { "$_ is not a valid Google language code" };

#------ What type of routes to avoid
subtype 'GoogDistanceAvoid', as 'Str',
  where { $is_valid_travel_avoidance->($_) or ( $_ eq q// ) },
  message { "$_ is not a valid Google travel avoidance." };
coerce 'GoogDistanceAvoid', from 'Str',
  via { $convert_to_valid_avoidance{ lc $_ } };

#------        Address's
#------        These are the only required attributes
subtype 'GoogAddrHref', as 'HashRef', where {
         exists $_->{address_1}
      && exists $_->{address_2}
      && exists $_->{city}
      && exists $_->{state}
      && exists $_->{country}
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
#------ JSON is the preferred output for this module
has 'output' => (
    is      => 'rw',
    isa     => 'GoogOutput',
    default => $JSON,
    coerce  => 1,
);

#-----  Distance sensor (like GPS ) true/false
has 'sensor' => (
    is      => 'ro',
    isa     => 'GoogBool',
    default => 'false',
    coerce  => 1,
);
has 'mode' => (
    is      => 'ro',
    isa     => 'GoogDistanceMode',
    default => 'driving',
    coerce  => 1,
);
has 'language' => (
    is      => 'ro',
    isa     => 'GoogDistanceLang',
    default => 'en',                 # en = American
);
has 'avoid' => (
    traits  => [qw(MooseX::UndefTolerant::Attribute)],
    is      => 'ro',
    isa     => 'GoogDistanceAvoid',
    default => '',
    coerce  => 1,
);

#------ Units of measurement
enum 'GoogDistanceUnit', [qw(imperial metric)];
coerce 'GoogDistanceUnit', from 'Str', via { $convert_to_valid_units{ lc $_ } };

has 'units' => (
    is      => 'ro',
    isa     => 'GoogDistanceUnit',
    default => 'metric',
    coerce  => 1,
);


has 'origins' => (
    is     => 'rw',
    isa    => 'GoogAddr',
    coerce => 1,
);

#------ Array or destination addresses


has 'destinations' => (
    is     => 'rw',
    isa    => 'GoogAddr',
    coerce => 1,
);

#-------------------------------------------------------------------------------
#  Methods
#------------------------------------------------------------------------------e
before qw/
  get_raw_google_matrix_data
  get_google_matrix_data_as_scalar_ref
  get_all_elements
  convert_google_json_to_perl
  / => sub {
    confess 'Must call as an object method!' unless ( $_[0] && ref( $_[0] ) );
  };

before qw/
  get_matrix_status_message
  get_matrix_origin_addresses
  get_matrix_destination_addresses
  / => sub {
    confess 'Must call as an object method!' unless ( $_[0] && ref( $_[0] ) );
    confess 'Must pass a reference paramater to this method!'
      unless ( $_[1] && ref( $_[1] ) );
  };


sub get_raw_google_matrix_data {
    my $self         = shift;
    my $query_params = $self->_matrix_query_params();
    my $uri          = $self->_build_uri($query_params);
    return $self->_call_google_api($uri);
}

#-------------------------------------------------------------------------------
#  Stuff to put into a sub class
#-------------------------------------------------------------------------------


sub get_google_matrix_data_as_scalar_ref {
    my $self = shift;
    $self->output($JSON);
    return $self->convert_google_json_to_perl(
        $self->get_raw_google_matrix_data() );
}


sub get_all_elements {
    my $self = shift;
    my $matrix = shift || $self->get_google_matrix_data_as_scalar_ref();

    my $google_status = $self->get_matrix_status_message($matrix);

    if ( ( not $google_status ) || ( $google_status ne $VALID_REQ ) ) {

        $log->debug( 'Google return status message is: '
              . ( $google_status // 'No Google Status' ) );
        return $FAIL;
    }

    #------ Preserve the Original address sent to Google
    #       as it may be needed later.
    #       Yet again,  this is something I would prefer 
    #       to put into a Child Class
    my $original_origins      = $self->_get_array_of_origins();
    my $original_destinations = $self->_get_array_of_destinations();

    #------ Get each combination for the origin destination addresses
    my $origin_ct = 0;
    my @elements_array;
    foreach my $origin_addr ( @{ $self->get_matrix_origin_addresses($matrix) } )
    {
        my $original_origin_addr = $original_origins->[ $origin_ct++ ];
        $log->debug( 'Original origin address is : ' . $original_origin_addr );

        #---Get results for current origination address
        my $row = shift @{ $matrix->{rows} };

        #------ Match origination address with all destination addressses
        my $dest_ct = 0;
        foreach my $destination_addr (
            @{ $self->get_matrix_destination_addresses($matrix) } )
        {

            my $original_destination_addr =
              $original_destinations->[ $dest_ct++ ];

            $log->debug( 'Original destination address is : '
                  . $original_destination_addr );

           #----- get the result for the current Origination -> Destination pair
            my $element = shift @{ $row->{elements} };

            push @elements_array,
              {
                origin_address               => $origin_addr,
                destination_address          => $destination_addr,
                original_origin_address      => $original_origin_addr,
                original_destination_address => $original_destination_addr,
                element_status               => $element->{status},
                element_duration_text        => $element->{duration}{text},
                element_duration_value       => $element->{duration}{value},
                element_distance_text        => $element->{distance}{text},
                element_distance_value       => $element->{distance}{value},
              };
        }
    }
    $log->debug(
        'Array of all elements returned by Google:  ' . dump @elements_array );
    return \@elements_array;
}


sub convert_google_json_to_perl {
    my $self     = shift;
    my $response = shift;
    return $self->_convert_from_json($response)
      if ( $response && $self->output eq $JSON );
}


sub get_matrix_status_message {
    my $self = shift;
    return $_[0]->{status};
}


sub get_matrix_origin_addresses {
    my $self   = shift;
    my $matrix = shift;
    return $matrix->{origin_addresses} || [];
}


sub get_matrix_destination_addresses {
    my $self   = shift;
    my $matrix = shift;
    return $matrix->{destination_addresses} || [];
}

#-------------------------------------------------------------------------------
#    Helper Methods
#-------------------------------------------------------------------------------


sub _get_array_of_origins {
    my $self = shift;
    my @original_origins = split( '\|', $self->origins() );
    return \@original_origins;
}


sub _get_array_of_destinations {
    my $self = shift;
    my @original_destinations = split( '\|', $self->destinations() );
    return \@original_destinations;
}


sub _matrix_query_params {
    my $self = shift;
    my $meta = __PACKAGE__->meta;
    my %query =
      map { $_->name => $self->{ $_->name } }
      grep { $_->name !~ /^(output)/ } ( $meta->get_all_attributes );

    return \%query;
}


sub _build_uri {
    my $self          = shift;
    my $matrix_params = shift;

#------Distance Matrix API URLs are restricted to 2048 characters,  before URL
#      encoding. As some Distance Matrix API service URLs may involve many locations,
#      be aware of this limit when constructing your URLs.
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
        $ua->timeout($time_out);
        $response = $ua->get($uri);
    }
    catch {
        $log->error( "Failed to access Google API.\n" . $_ );
        confess($_);
    };

    return $response;
}


sub _convert_from_json {
    my $self     = shift;
    my $response = shift;
    return try {
        decode_json $response->content;
    }
    catch {
        $log->error( "Failed to decode JSON Distance Matrix data.\n" . $_ );
        $FAIL;
    };
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
          . ( defined $addr_href->{state} ? ',' . $addr_href->{state} : q// )
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

Google::Travel::Matrix - To access the Google Distance Matrix API .

=head1 VERSION

version 0.2

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

=head2 get_raw_google_matrix_data
    Builds the request and gets the Google Distance Matrix data based on the 
    Origin and Destination addresses.
    Returns the raw Google Matrix response in either JSON or XML format.

=head2 get_google_matrix_data_as_scalar_ref
    Builds the request and gets the Google Distance Matrix data based on the 
    Origin and Destination addresses.
    Returns the Google Matrix response as a scalar reference to a Perl data structure.
    Note: The output attribute will be set to the default, "JSON". 

=head2 get_all_elements
 Given the Google Distance Matrix output as a scalar reference to a Perl data
 structure, returns an ArrayRef of Matrix elements or undef.
 If no Google Output data passed, then it will create one using the Origin and
 destination addresses;
 It would be a good idea to check that the Google Matrix Return is 'OK' before calling
 this method.

=head2 convert_google_json_to_perl
   Convert the Google response from JSON to a Perl data reference.

=head2 get_matrix_status_message
  Given the decoded Google response, return a string wich contains the google
  status message as a string.

  These are the status messages from Google.
  'OK',
  'INVALID_REQUEST',
  'MAX_ELEMENTS_EXCEEDED',
  'MAX_DIMENSIONS_EXCEEDED',
  'MAX_QUERY_LIMIT',
  'REQUEST_DENIED',
  'UNKNOWN_ERROR',

=head2 get_matrix_origin_addresses
 Get the origin address(s) returned by Google.
 Returns an ArayRef;

=head2 get_matrix_destination_addresses
 Get the destination address(s) returned by Google.
 Returns an ArayRef;

=head2 _get_array_of_origins
    Returns the string of the original input origins as an arrayRef of individual addresses.

=head2 _get_array_of_destinations
    Returns the string of the original input destinations as an arrayRef of individual addresses.

=head2 _matrix_query_params
    Build and returns all the params for the Google Distance Matrix request
    as a HashRef.
    Use the formatted origins and destinations address's.
    Omits the requested output format specifier.

=head2 _build_uri
   Build and return the query URI.

=head2 _call_google_api
   Call the google travel matrix API.
   Returns the Google response.

=head2 _convert_from_json
   Convert the Google response from JSON.

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
