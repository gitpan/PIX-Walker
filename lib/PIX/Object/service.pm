package PIX::Object::service;

use strict;
use warnings;
use base qw( PIX::Object );

sub _init {
	my $self = shift;
	$self->SUPER::_init;

	$self->{debug} = 1;

	$self->{services} = [];				# services directly defined in this object group
	$self->{groups} = [];				# other groups that this object points to for services

	$self->_nextline;				# remove the first line 'object-group blah'
	while (defined(my $line = $self->_nextline)) {
		my ($type, $p1, $p2);
#		print "$self->{name}: $line\n";
		if ($line =~ /\s*port-object (eq|gt|lt|range) (\S+)\s*(\S*)/) {
			($type, $p1, $p2) = ($1, $2, $3);	# 'range' is handled automatically if it's present
			if ($type eq 'eq') {
				$p2 = $p1;
			} elsif ($type eq 'lt') {
				$p2 = $p1;
				$p1 = 0;
			} elsif ($type eq 'gt') {
				$p2 = 65535;
			}
			$p1 = $self->{walker}->portnum($p1);
			$p2 = $self->{walker}->portnum($p2);
			$self->add($p1, $p2);
		} elsif ($line =~ /^\s*group-object (\S+)/) {
			push(@{$self->{groups}}, $1);
		} elsif ($line =~ /^\s+description (.+)/) {
			$self->{desc} = $1;
		} else {
			warn "$self->{name}: Unknown service object line: $line\n"; 
		}
	}
#	use Data::Dumper; print "$self->{name}:" . Dumper($self->{services});
}

# searches the services within our group for the PORT given
# Deligates out to nested groups and maintains the state of the trace.
sub matchport {
	my ($self, $portstr, $trace) = @_;
	my $port = $self->{walker}->portnum($portstr);
	my $found = undef;
	my $idx = 0;

	# first search our defined services.
#	print "searching services in $self->{name} ...\n" if $self->{debug};
	foreach my $p (@{$self->{services}}) {
#		use Data::Dumper; print Dumper($p);
		$idx++;
		if ($port >= $p->[0] and $port <= $p->[1]) {
			push(@$trace, $self->{name}, $idx, 0) if defined $trace;
			return 1; #$self->{name};
		}
	}

	# search all nested groups, if any.
	$idx = 0;
#	print "searching groups in $self->{name} (" . (join(',', @{$self->{groups}})) . ")...\n" if $self->{debug} and scalar @{$self->{groups}};
	foreach my $name (@{$self->{groups}}) {
		$idx++;
		my $grp = $self->{walker}->obj($name) || next;
		my $localtrace = [ $self->{name}, 0, 0 ];
		next unless $grp->type eq 'service';
		my $found = $grp->matchport($port, $localtrace);
		if ($found) {
			push(@$trace, @$localtrace) if defined $trace;
			return 1; #$grp->{name};
		}
	}

	return 0;
}

sub services { return wantarray ? @{$_[0]->{services}} : $_[0]->{services} }
sub groups { return wantarray ? @{$_[0]->{groups}} : $_[0]->{groups} }

sub add {
	my ($self, $p1, $p2) = @_;
	push(@{$self->{services}}, [ $p1, $p2 ]);
}

# returns a complete list of ports
sub enumerate {
	my $self = shift;
	my @list = ();
	for (my $i=0; $i < @{$self->{services}}; $i++) {
		my $low = $self->{services}[$i][0];
		my $high = $self->{services}[$i][1];
		for (my $j=$low; $j <= $high; $j++) {
			push(@list, $j);
		}
	}
	foreach my $name ($self->groups) {
		my $grp = $self->{walker}->obj($name) || next;
		push(@list, $grp->enumerate);
	}
	return @list;
}

sub list {
	my $self = shift;
	my @list = @{$self->{services}};
	foreach my $name ($self->groups) {
		my $grp = $self->{walker}->obj($name) || next;
		push(@list, $grp->list);
	}
	return @list;
}

1;
