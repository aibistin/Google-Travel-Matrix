#!/usr/bin/perl
use Modern::Perl qw/2012/;
use DateTime;
use List::Util qw/sum/;
use List::MoreUtils qw/ all any/;
use Scalar::Util qw/reftype blessed/;
use Carp qw /confess/;
use Data::Dump qw/dump/;
use Try::Tiny;

use Log::Any::Adapter qw/Stdout/;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);

#Log::Log4perl->easy_init($DEBUG);

use Test::More;
use Test::Exception;

use Test::Moose::More;

use Readonly;

#  uses  Readonly::XS;
Readonly my $TRUE      => 1;
Readonly my $FALSE     => 0;
Readonly my $FAIL      => undef;
Readonly my $EMPTY_STR => q//;
Readonly my $EMPTY     => q/<empty>/;
my ( $test_moose_stuff, $test_get_distances );

#-------------------------------------------------------------------------------
#  And The Star Is.....
#-------------------------------------------------------------------------------
use Google::Travel::Matrix;

#-------------------------------------------------------------------------------
#  Test Switches
#-------------------------------------------------------------------------------

my $TEST_GET_DISTANCES = $TRUE;

#-------------------------------------------------------------------------------
#  Test Data
#-------------------------------------------------------------------------------
my %valid_travel_modes = (
    d         => 'driving',
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
    c         => 'bicycling',
    cycling   => 'bicycling',
    cycle     => 'bicycling',
);

#------- Google only permits one avoidance
my %valid_travel_avoids = (
    t         => 'tolls',
    tolls     => 'tolls',
    toll      => 'tolls',
    extorsion => 'tolls',
    h         => 'highways',
    highway   => 'highways',
    highways  => 'highways',
    potholes  => 'highways',
);
my %valid_units = (
    i          => 'imperial',
    imperial   => 'imperial',
    miles      => 'imperial',
    cavemanish => 'imperial',
    m          => 'metric',
    metric     => 'metric',
    meters     => 'metric',
    metres     => 'metric',
);
my @languages = qw/
  ar  eu  bg  bn  ca  cs  da  de  el  en
  es  eu  fa  fi  fil  fr  gl gu  hi  hr
  hu  id  it  iw  ja  kn  ko lt  lv   ml
  mr  nl  nn  no  or  pl  pt pt-BR  pt-PT
  rm  ro  ru  sk  sl  sr  sv  tl  ta  te
  th  tr  uk  vi  zh-CN  zh-TW  /;

my $sensor      = 0;
my $travel_mode = 'c';
my $language    = 'en';
my $avoid       = 'extorsion';
my $units       = 'i';

my @valid_test_data = (
    {
        data => {
            origins => [
                '    1 Columbus Circle  , New         York,  NY 1019',

             #                '    163 Exterior St , Bronx         ,  NY 1019',
             #                '    224 West 74 St      , New         York,  NY',
             #                '10 West Bowery St., Akron,  OH'
            ],
            destinations => [
                '10 Madison Avenue, Bridgeport,  Connecticut 06604',
                '39-63 45th Street, Sunnyside, New York, NY 11104',
                '10 Tremont Street, Boston, MA 02108'

                  #                '10 E5th Street, Austin,  Texas',
                  #                '1200 S Federal Street, Chicago,  Il',
            ],
            sensor   => 0,
            mode     => 'driving',
            language => 'en',
            units    => 'imperial',
        },
        test => {
            origins_count      => 3,
            destinations_count => 2,

            #--- Output from google
            have_in_origin_addrs => [
                [qw /Austin Texas USA|Unis/], [qw /Chicago Il/],
                [ 'New York', 11104, 'USA|Unis' ]
            ],
            have_in_dest_addrs => [
                [ 'New York', 'USA|Unis' ],
                [
                    qw /Akron
                      Ohio USA|Unis/
                ]
            ],
            google_status  => 'OK',
            element_status => 'OK',
            row_count      => 3,
            element_count  => 6,
            distance_text  => 'mi',
            duration_text  => 'day|hour|min',

            #------ Distance from Austin to NY,  Austin-> Akron,
            #------ Distance from Chicago to NY,  Chicago-> Akron,
            #------ Distance from Sunnyside NY to NYC,  Sunnyside -> Akron,
            #------ Distance from Columbus Ave NYC to Sunnyside 4.3 miles
            #------ Distance from Columbus Ave NYC to 10 madison ave ,
            #       Bridgeport Ct 60.5
            #------ Distance from Columbus Ave NYC to 10 Tremont Street,
            #       Boston MA  ,  212 miles (207 miles from Exterior St)
            distance_values => [ 60.5, 4.1, 212 ],
        },
    },
);

#-------------------------------------------------------------------------------
#  Testing
#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
#  Test get_distances
#-------------------------------------------------------------------------------

subtest $test_get_distances => sub {

    plan skip_all => 'Not testing Get Distances'
      unless ($TEST_GET_DISTANCES);

    my $test_data;

    for ( my $i = 0 ; $i <= $#valid_test_data ; $i++ ) {

        $test_data = $valid_test_data[$i]{data};
        my $GoogMx      = Google::Travel::Matrix->new($test_data);
        my $test_expect = $valid_test_data[$i]{test};
        isa_ok( $GoogMx, 'Google::Travel::Matrix',
            'Created Google-Travel-Matrix object.' );

        diag 'The origins array : ' . dump $GoogMx->origins;

        #---Test formatting
        my $got_origins_count      = ( split '\|', $GoogMx->origins );
        my $got_destinations_count = ( split '\|', $GoogMx->destinations );

        cmp_ok( $got_origins_count, '==', $test_expect->{origins_count},
            'Module has correct number of origins, '
              . $test_expect->{origins_count} );

        my $elements = $GoogMx->get_all_elements();
        ok( $elements, 'Got the Elements array' );
        isa_ok( $elements, 'ARRAY', 'Elements array is an ARRAY ref' );

        if ( exists $test_expect->{distance_values} ) {
            diag 'Testing distance value values.';
            foreach my $itinerary (@$elements) {

                my $expected_distance =
                  shift @{ $test_expect->{distance_values} };

                my $text_miles =
                  get_value_from_text( $itinerary->{element_distance_text} );

                my $actual_text_dist_in_meters = get_miles_convert_to_meters(
                    $itinerary->{element_distance_text} );

                #-----Google gives the distance in meters.
                my $expected_dist_in_meters =
                  convert_from_miles_to_meters($expected_distance);

                my $actual_dist_in_miles = convert_from_meters_to_miles(
                    $itinerary->{element_distance_value} );

                cmp_ok( $text_miles, '==', $expected_distance,
                    "Expect distance $expected_distance,  and got from text  "
                      . $text_miles );

                diag '******************************************************';
                diag 'The final DOT time is : '
                  . convert_to_dot_time($actual_dist_in_miles);
                diag '******************************************************';
            }
        }

    }

};    # End testing get_distances_only

#-------------------------------------------------------------------------------
#  Useful Subs
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#  Pass actual result,  ArayRef of expected results and test name.
#-------------------------------------------------------------------------------
sub is_any {

    my ( $actual, $expected, $name ) = @_;

    $name ||= '';

    ok( ( any { $_ eq $actual } @$expected ), $name )

      or diag "Received: $actual\nExpected:\n" .

      join "", map { "         $_\n" } @$expected;

}

#-------------------------------------------------------------------------------
#  Convert HashRef to String
#  Converts Key Value pairs to a string % key : value % key : value % ....
#  Converts DateTime Value to string also.
#-------------------------------------------------------------------------------
sub convert_href_to_str {
    my $href = shift;
    return fail('Must send a HashRef to convert_href_to_str !')
      unless ( ref($href) eq 'HASH' );
    my $hash_as_str = q//;
    for my $key ( keys %$href ) {
        $hash_as_str .= ', ' if length($hash_as_str);
        my $value;
        if ( $href->{$key} and blessed( $href->{$key} eq 'DateTime' ) ) {
            $value = 'From DateTime Object: '
              . convert_datetime_to_str( $href->{$key} );
        }
        else {
            $value = $href->{$key};
        }
        $hash_as_str .= $key . ' : ' . ( $value // $EMPTY );
    }
    return $hash_as_str;
}

#-------------------------------------------------------------------------------
#  Get value from text
#  Given a string containing a numeric value, return the value.
#-------------------------------------------------------------------------------
sub get_value_from_text {
    #<<<   perltidy skip
    #------ remove commas
    my $stripped_text = $_[0] =~ s/,//rg;

    return $stripped_text =~ s/(\d+\.\d+|\.\d+|\d+\.|\d+).*/$1/rg;
    #>>>

    #               my $stripped_text =
    #                 $stripped_dist =~ s/[^0-9.]//gr;
}

#-------------------------------------------------------------------------------
#  Strip miles from text and convert to meters
#-------------------------------------------------------------------------------
sub get_miles_convert_to_meters {
    #<<<   perltidy skip
    #------ remove commas
    my $stripped_text = $_[0] =~ s/,//rg;
    #>>>
    return $stripped_text =~ s/(\d+\.\d+|\.\d+|\d+\.|\d+).*/$1 * 1609.34/er;

}

#-------------------------------------------------------------------------------
#  Convert meters to miles.
#-------------------------------------------------------------------------------
sub convert_from_meters_to_miles {
    my $miles = $_[0] * 0.000621371;
    return sprintf( "%.1f", $miles );
}

sub convert_from_miles_to_meters {
    return $_[0] * 1609.34;
}

#-------------------------------------------------------------------------------
#  Convert Miles To Truck Travel Time
#  Returns the time in minutes;
#-------------------------------------------------------------------------------
sub convert_to_dot_time {

    my $distance = abs shift;
    if ( $distance <= 20 ) {
        return 60;
    }

    #------ First 20 miles is 60 minutes.
    #       Each 40 miles after that is 60 minutes,
    #       iequivalent Each 10 miles after that is 15 mins
    #       Note: 15 minutes is the smallest unit of calc.
    #       Note: Milage is converted to an intiger,  therefore
    #       removing any fractions.
    #       Note: Integer Milage is rounded up to highest 10 miles.

    #

    my $time = 60;
    $distance -= 20;

    diag 'Distance un-rounded is : ' . $distance;

    my $mod;
    diag 'Using My Own Function';
    my $dist_rounded =
      ( ( $mod = $distance % 10 ) == 0 )
      ? int $distance
      : int( $distance += ( 10 - $mod ) );
    diag 'Time Moduo is : ' . $mod;

    diag 'Distance rounded is : ' . $dist_rounded;

    $time += $dist_rounded * 15;

    return $time;

}

#-------------------------------------------------------------------------------
#  Temporary end marker
#-------------------------------------------------------------------------------
done_testing();
__END__
