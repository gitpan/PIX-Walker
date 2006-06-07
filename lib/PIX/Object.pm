package PIX::Object;
# Factory class for the various object-groups found in a PIX config

use strict;
use warnings;

use Carp;

our $VERSION = '1.00';

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { };
	my ($type, $name, $config, $walker) = @_;
	croak("Must provide the object-group type, name and config block") unless ($type and $name and $config);

	$class .= "::" . lc $type;
	$class =~ tr/-/_/;
	eval "require $class";
	if ($@) {
		die("Object subclass '$class' has compile time errors:\n$@\n");
	} 

	$self->{class} = $class;
	$self->{name} = $name;
	$self->{type} = $type;
	$self->{config} = [ @$config ];
	$self->{config_block} = [ @$config ];
	$self->{walker} = $walker;

	bless($self, $class);
	$self->_init;

	return $self;
}

sub type { $_[0]->{type} }
sub name { $_[0]->{name} }
sub list { }
sub first { ($_[0]->list)[0] }

sub alias {
	my $self = shift;
	my $string = shift;
	return defined $self->{walker} ? $self->{walker}->alias($string) : $string;
}

sub _init {
	my $self = shift;

	if (@{$self->{config_block}}[0] !~ /^object-group \S+ \S+/i) {
		carp("Invalid config block passed to $self->{class}");
		return undef;
	}
}

sub _nextline { shift @{$_[0]->{config_block}} }
sub _rewind { unshift @{$_[0]->{config_block}}, $_[1] }

1;
