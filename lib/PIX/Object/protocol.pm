package PIX::Object::protocol;

use strict;
use warnings;
use base qw( PIX::Object );

our $VERSION = '1.00';

sub _init {
	my $self = shift;
	$self->SUPER::_init;

	$self->{debug} = 1;

	$self->{protocols} = [];				# protocols directly defined in this object group
	$self->{groups} = [];				# other groups that this object points to for protocols

	$self->_nextline;				# remove the first line 'object-group blah'
	while (defined(my $line = $self->_nextline)) {
#		print "$self->{name}: $line\n";
		if ($line =~ /\s*protocol-object (\S*)/) {
			$self->add($1);
		} elsif ($line =~ /^\s*group-object (\S+)/) {
			push(@{$self->{groups}}, $1);
		} elsif ($line =~ /^\s+description (.+)/) {
			$self->{desc} = $1;
		} else {
			warn "$self->{name}: Unknown protocol object line: $line\n"; 
		}
	}
#	use Data::Dumper; print "$self->{name}:" . Dumper($self->{protocols});
}

sub protocols { return wantarray ? @{$_[0]->{protocols}} : $_[0]->{protocols} }
sub groups { return wantarray ? @{$_[0]->{groups}} : $_[0]->{groups} }

sub add {
	my ($self, $p) = @_;
	push(@{$self->{protocols}}, $p);
}

sub list {
	my $self = shift;
	my @list = @{$self->{protocols}};
	foreach my $name ($self->groups) {
		my $grp = $self->{walker}->obj($name) || next;
		push(@list, $grp->list);
	}
	return @list;
}

1;
