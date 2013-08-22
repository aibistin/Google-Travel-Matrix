
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "To access the Google Distance Matrix API .",
  "AUTHOR" => "Austin Kenny <aibistin.cionnaith\@gmail.com>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Google-Travel-Matrix",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Google::Travel::Matrix",
  "PREREQ_PM" => {
    "Data::Dump" => 0,
    "JSON" => 0,
    "LWP::UserAgent" => 0,
    "Log::Any" => 0,
    "Moose" => 0,
    "Moose::Util::TypeConstraints" => 0,
    "MooseX::UndefTolerant::Attribute" => 0,
    "Readonly" => 0,
    "Try::Tiny" => 0,
    "URI" => 0,
    "namespace::autoclean" => 0,
    "utf8::all" => 0
  },
  "TEST_REQUIRES" => {
    "Capture::Tiny" => 0,
    "Carp" => 0,
    "DateTime" => 0,
    "ExtUtils::MakeMaker" => 0,
    "File::Spec::Functions" => 0,
    "File::Temp" => 0,
    "List::MoreUtils" => 0,
    "List::Util" => 0,
    "Log::Any::Adapter" => 0,
    "Log::Log4perl" => 0,
    "Modern::Perl" => 0,
    "Scalar::Util" => 0,
    "Test::Exception" => 0,
    "Test::Moose::More" => 0,
    "Test::More" => "0.88",
    "blib" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "VERSION" => "0.2",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
  my $br = $WriteMakefileArgs{BUILD_REQUIRES};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



