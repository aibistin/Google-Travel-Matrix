#!/usr/bin/perl
use Modern::Perl qw/2012/;
use DateTime;
use List::Util qw/sum/;
use List::MoreUtils qw/ all any/;
use Scalar::Util qw/reftype blessed/;
use Carp qw /confess/;
use Data::Dump qw/dump/;

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
my ( $test_moose_stuff, $test_get_travel_matrix );

#-------------------------------------------------------------------------------
#  And The Star Is.....
#-------------------------------------------------------------------------------
use Google::Travel::Matrix;

#-------------------------------------------------------------------------------
#  Test Switches
#-------------------------------------------------------------------------------

my $TEST_MOOSE_STUFF       = $TRUE;
my $TEST_GET_TRAVEL_MATRIX = $TRUE;

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

#my @origins      = (  'Sunnyside, New York');
my @origins =
    ( 'Austin,  Texas', 'Chicago,  Il', 'Sunnyside, New York, NY 11104' );

#my @destinations = (  'Akron,  OH' );
my @destinations = ( 'New York,  NY', 'Akron,  OH' );

my $sensor      = 0;
my $travel_mode = 'c';
my $language    = 'en';
my $avoid       = 'extorsion';
my $units       = 'i';

my @valid_test_data = (
    {   data => {
            origins => [
                'Austin,  Texas',
                'Chicago,  Il',
                'Sunnyside, New York, NY 11104'
            ],
            destinations => [ 'New York,  NY', 'Akron,  OH' ],
            sensor       => 0,
            travel_mode  => 'driving',
            language     => 'fr',
            avoid        => 'tolls',
            units        => 'imperial',
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
                [   qw /Akron
                        Ohio USA|Unis/
                ]
            ],
            google_status  => 'OK',
            element_status => 'OK',
            row_count      => 3,
            element_count  => 6,
            distance_text  => 'mi',
            duration_text  => 'jour|heure|minutes',

            #--my attributes
        },
    },
    {   data => {
            origins =>
                [ 'Paris,  France', 'Brussels,  Belgium', 'Bonn, Germany' ],
            destinations => [ 'London,  England', 'Moscow,  Russia' ],
            sensor       => 0,
            travel_mode  => 'cycling',
            language     => 'fr',

            #         avoid       => 'tolls',
            units => 'imperial',
        },
        test => {
            origins_count      => 3,
            destinations_count => 2,

            #--- Output from google
            have_in_origin_addrs => [
                [qw /Paris France/], [qw /Bruxelles Belgique/],
                [qw /Bonn/]
            ],
            have_in_dest_addrs =>
                [ [qw /Londres Royaume-Uni/], [qw /Moscou Russie/] ],
            google_status  => 'OK',
            element_status => 'OK',
            row_count      => 3,
            element_count  => 6,
            distance_text  => 'mi',
            duration_text  => 'heur',
        },
    },
    {   data => {
            origins      => [ 'Montreal,  Canada', 'Seattle,   USA' ],
            destinations => [ 'Ottawa,  ON',       'Anchorage,  Alaska' ],
            sensor       => 0,
            travel_mode  => 'driving',
            language     => 'en',

            #         avoid       => 'tolls',
            units => 'metric',
        },
        test => {
            origins_count      => 2,
            destinations_count => 2,

            #--- Output from google
            have_in_origin_addrs =>
                [ [qw /Montreal QC/], [qw /Seattle WA USA|Unis/] ],
            have_in_dest_addrs =>
                [ [qw /Ottawa ON Canada/], [qw /Anchorage AK USA|Unis/] ],
            google_status  => 'OK',
            element_status => 'OK',
            row_count      => 2,
            element_count  => 4,
            distance_text  => 'meters|km',
            duration_text  => 'day|hours|mins',

            #--my attributes
        },
    },
);

#-------------------------------------------------------------------------------
#  Testing
#-------------------------------------------------------------------------------
diag(
    "Testing Google::Travel::Matrix  Google::Travel::Matrix::VERSION, Perl $], $^X"
);
subtest $test_moose_stuff => sub {

    plan skip_all => 'Not testing Moose Stuff.'
        unless ($TEST_MOOSE_STUFF);

    my $MoTaMa = Google::Travel::Matrix->new(
        origins      => \@origins,
        destinations => \@destinations,
        sensor       => $sensor,
        travel_mode  => $travel_mode,
        language     => $language,
        avoid        => $avoid,
        units        => $units,
    );

    #------ Test Moose Attributes
    isa_ok( $MoTaMa, 'Google::Travel::Matrix',
        'Defined Google-Travel-Matrix instance' );

    diag 'Test Google::Travel::Matrix Moose stuff.';

    meta_ok( 'Google::Travel::Matrix',
        'Google::Travel::Matrix class has a metaclass.' );

    has_attribute_ok( 'Google::Travel::Matrix', 'origins',
        'Class has origins attribute.' );
    has_attribute_ok( 'Google::Travel::Matrix', 'destinations',
        'Class has destinations attribute.' );
    has_attribute_ok( 'Google::Travel::Matrix', 'sensor',
        'Class has sensor attribute.' );
    has_attribute_ok( 'Google::Travel::Matrix', 'travel_mode',
        'Class has travel_mode attribute.' );
    has_attribute_ok( 'Google::Travel::Matrix', 'language',
        'Class has language attribute.' );
    has_attribute_ok( 'Google::Travel::Matrix', 'avoid',
        'Class has avoid attribute.' );
    has_attribute_ok( 'Google::Travel::Matrix', 'units',
        'Class has units attribute.' );

    has_method_ok(
        'Google::Travel::Matrix',
        (   qw/build_the_request
                /
        )
    );

};    #--- End testing of Moose stuff

#-------------------------------------------------------------------------------
#  Test get_travel_matrix
#-------------------------------------------------------------------------------

subtest $test_get_travel_matrix => sub {

    plan skip_all => 'Not testing Get Travel Matrix.'
        unless ($TEST_GET_TRAVEL_MATRIX);

    my $test_data;

    for ( my $i = 0; $i <= $#valid_test_data; $i++ ) {

        #    for ( my $i = 0 ; $i < 1 ; $i++ ) {
        $test_data = $valid_test_data[$i]{data};
        my $GoogMx = Google::Travel::Matrix->new($test_data);

        my $test_expect = $valid_test_data[$i]{test};

        isa_ok( $GoogMx, 'Google::Travel::Matrix',
            'Created Google-Travel-Matrix object.' );

        #---Test formatting
        my $got_origins_count      = scalar @{ $GoogMx->origins };
        my $got_destinations_count = scalar @{ $GoogMx->destinations };
        my @got_formatted_origins  = split '\|',
            $GoogMx->get_formatted_origins;
        my @got_formatted_destinations = split '\|',
            $GoogMx->get_formatted_destinations;
        my $formatted_origins_count      = @got_formatted_origins;
        my $formatted_destinations_count = @got_formatted_destinations;

        cmp_ok( $got_origins_count, '==', $test_expect->{origins_count},
            'Module has correct number of origins, '
                . $test_expect->{origins_count} );

        cmp_ok( $formatted_origins_count, '==', $test_expect->{origins_count},
            'Module formatted the correct number of origins, '
                . $test_expect->{origins_count} );

        cmp_ok(
            $got_destinations_count,
            '==',
            $test_expect->{destinations_count},
            'Module has the correct number of destinations, '
                . $test_expect->{destinations_count}
        );

        cmp_ok(
            $formatted_destinations_count,
            '==',
            $test_expect->{destinations_count},
            'Module formatted the correct number of destinations, '
                . $test_expect->{destinations_count}
        );

        my $matrix = $GoogMx->build_the_request();
        ok( $matrix, 'Got the Matrix' );

        #------- test that Google returned the right amount of addresses
        my $goog_origin_addr_count = scalar @{ $matrix->{origin_addresses} };
        cmp_ok(
            $goog_origin_addr_count, '==',
            $test_expect->{origins_count},
            'Google processed correct number of origins.'
        );

        my $goog_dest_addr_count =
            scalar @{ $matrix->{destination_addresses} };
        cmp_ok(
            $goog_dest_addr_count, '==',
            $test_expect->{destinations_count},
            'Google processed correct number of destinations.'
        );

        #------ Test the overall google return code
        is( $matrix->{status},
            $test_expect->{google_status},
            'Google gave the all OK! '
        );
        my $row_count = scalar @{ $matrix->{rows} };

        #---- Should be one row for each origin address
        cmp_ok(
            $row_count, '==',
            $test_expect->{row_count},
            'Correct number of matrix rows is ' . $test_expect->{row_count}
        );

        my $element_count;
        for my $row ( @{ $matrix->{rows} } ) {
            for my $got_element ( @{ $row->{elements} } ) {
                $element_count += 1;

                is( $got_element->{status}, $test_expect->{element_status},
                    'The element status is '
                        . $test_expect->{element_status} );
                like(
                    $got_element->{distance}{text},
                    qr/$test_expect->{distance_text}/,
                    'Correct measurement units are '
                        . $test_expect->{distance_text}
                );

                #------ Test the language used in the duration units
                like(
                    $got_element->{duration}{text},
                    qr/$test_expect->{duration_text}/,
                    'Correct language.'
                );
            }
        }

  #------ Total elements should match the (# of origins) * (# of destinations)
        cmp_ok(
            $element_count, '==', $test_expect->{element_count},
            'Correct number of matrix
       element_count is ' . $test_expect->{element_count}
        );

        #------ Test that google is processing the correct  addresses
        #       by checking the addresses that Google returns
        #-------Origin Addresses
        my @got_addresses = @{ $matrix->{origin_addresses} };

        #---array of arrays
        my @expected_addresses = @{ $test_expect->{have_in_origin_addrs} };

        for ( my $i = 0; $i < $goog_origin_addr_count; $i++ ) {
            my $got_address        = $got_addresses[$i];
            my @expected_addr_data = @{ $expected_addresses[$i] };
            for my $expected_this (@expected_addr_data) {
                like( $got_address, qr/$expected_this/,
                    'Google processed an origin containing '
                        . $expected_this );
            }
        }

        #-------Destination Addresses
        @got_addresses      = @{ $matrix->{destination_addresses} };
        @expected_addresses = @{ $test_expect->{have_in_dest_addrs} };
        for ( my $i = 0; $i < $goog_dest_addr_count; $i++ ) {
            my $got_address        = $got_addresses[$i];
            my @expected_addr_data = @{ $expected_addresses[$i] };
            for my $expect_this (@expected_addr_data) {
                like(
                    $got_address, qr/$expect_this/,
                    'Google processed an destination with
             containing ' . $expect_this
                );
            }
        }
    }

};    # End testing get_travel_matrix

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

        join "", map {"         $_\n"} @$expected;

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
#  Temporary end marker
#-------------------------------------------------------------------------------
done_testing();
__END__
