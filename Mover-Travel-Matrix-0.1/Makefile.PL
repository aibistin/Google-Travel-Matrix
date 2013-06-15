
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "To access the Google Travel Matrix API .",
  "AUTHOR" => "Austin Kenny <aibistin.cionnaith\@gmail.com>",
  "BUILD_REQUIRES" => {
    "Carp" => 0,
    "DateTime" => 0,
    "ExtUtils::MakeMaker" => 0,
    "File::Find" => 0,
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
    "Test::More" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Mover-Travel-Matrix",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Mover::Travel::Matrix",
  "PREREQ_PM" => {
    "Data::Dump" => 0,
    "JSON" => 0,
    "JSON::Any" => 0,
    "LWP::UserAgent" => 0,
    "Log::Any" => 0,
    "Moose" => 0,
    "Moose::Util::TypeConstraints" => 0,
    "MooseX::Params::Validate" => 0,
    "MooseX::UndefTolerant::Attribute" => 0,
    "Readonly" => 0,
    "Try::Tiny" => 0,
    "URI" => 0,
    "XML::Simple" => 0,
    "namespace::autoclean" => 0,
    "utf8::all" => 0
  },
  "VERSION" => "0.1",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


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



