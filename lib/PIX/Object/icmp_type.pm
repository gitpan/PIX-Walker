package PIX::Object::icmp_type;

use strict;
use warnings;
use base qw( PIX::Object );

our $VERSION = '1.00';

sub _init {
	my $self = shift;
	$self->SUPER::_init;

	$self->{debug} = 0;

	$self->{icmptypes} = [];			# icmp-types directly defined in this object group
	$self->{groups} = [];				# other groups that this object points to for icmptypes

	# ... currently objects of this type are not processed ...
}

sub icmptypes { return wantarray ? @{$_[0]->{icmptypes}} : $_[0]->{icmptypes} }
sub groups { return wantarray ? @{$_[0]->{groups}} : $_[0]->{groups} }

sub add {
	my ($self, $i) = @_;
	push(@{$self->{icmptypes}}, $i);
}

sub list {
	my $self = shift;
	my @list = @{$self->{icmptypes}};
	foreach my $name ($self->groups) {
		my $grp = $self->{walker}->obj($name) || next;
		push(@list, $grp->list);
	}
	return @list;
}


1;
