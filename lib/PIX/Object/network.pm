package PIX::Object::network;

use strict;
use warnings;
use base qw( PIX::Object );

our $VERSION = '1.00';

sub _init {
	my $self = shift;
	$self->SUPER::_init;

	$self->{debug} = 0;

	$self->{networks} = [];				# networks directly defined in this object group
	$self->{groups} = [];				# other groups that this object points to for networks

	$self->_nextline;				# remove the first line 'object-group blah'
	while (defined(my $line = $self->_nextline)) {
		my ($ip, $mask);
#		print "$self->{name}: $line\n";
		if ($line =~ /\s*network-object (\S+) (\S+)/) {
			($ip, $mask) = ($1, $2);
			if ($ip eq 'host') {
				$ip = $mask;
				$mask = '255.255.255.255';
			}
			$ip = $self->alias($ip);
			$self->add($ip, $mask);
		} elsif ($line =~ /^\s*group-object (\S+)/) {
			push(@{$self->{groups}}, $1);
		} elsif ($line =~ /^\s+description (.+)/) {
			$self->{desc} = $1;
		} else {
			warn "$self->{name}: Unknown network object line: $line\n"; 
		}
	}
#	use Data::Dumper;
#	print "$self->{name}:" . Dumper($self->{networks});
}

# searches the networks within our group for the IP given. 
# Deligates out to nested groups and maintains the state of the trace.
sub matchip {
	my ($self, $ip, $trace) = @_;
	my $ipint = ip2int($ip);
	my $found = undef;
	my $idx = 0;

	# first search our defined networks.
#	print "searching networks in $self->{name} ...\n" if $self->{debug};
	foreach my $net (@{$self->{networks}}) {
		$idx++;
		if ($ipint >= $net->[0] and $ipint <= $net->[1]) {
			push(@$trace, $self->{name}, $idx, int2ip($net->[0]) . "/" . $net->[2]) if defined $trace;
			return $self->{name};
		}
	}

	# search all nested groups, if any.
	$idx = 0;
#	print "searching groups in $self->{name} (" . (join(',', @{$self->{groups}})) . ")...\n" if $self->{debug} and scalar @{$self->{groups}};
	foreach my $name (@{$self->{groups}}) {
		$idx++;
		my $grp = $self->{walker}->obj($name) || next;
		my $localtrace = [ $self->{name}, 0, 0 ];
		next unless $grp->type eq 'network';
		my $found = $grp->matchip($ip, $localtrace);
		if ($found) {
			push(@$trace, @$localtrace) if defined $trace;
			return $grp->{name};
		}
	}	
}

sub networks { return wantarray ? @{$_[0]->{networks}} : $_[0]->{networks} }
sub groups { return wantarray ? @{$_[0]->{groups}} : $_[0]->{groups} }

sub add {
	my ($self, $ip, $mask) = @_;
	my ($first, $last, $bits);
	$bits = ipnumbits($mask);
	$first = ip2int($ip);
	$last = ip2int(ipbroadcast($first, $bits));
	push(@{$self->{networks}}, [ $first, $last, $bits ]);
}

# returns a list of networks
sub list {
	my $self = shift;
	my @list = ();
	for (my $i=0; $i<@{$self->{networks}}; $i++) {
		push(@list, int2ip($self->{networks}[$i][0]) . ($self->{networks}[$i][2] ne '32' ? '/' . $self->{networks}[$i][2] : ''));
	}
	foreach my $name ($self->groups) {
		my $grp = $self->{walker}->obj($name) || next;
		push(@list, $grp->list);
	}
	return @list;
}

sub ip2int {
	my ($ip, $port) = split(/:/, shift, 2);		# strip off any port if it's present
	my ($i1,$i2,$i3,$i4) = split(/\./, $ip);
	return ($i4) | ($i3 << 8) | ($i2 << 16) | ($i1 << 24);
}

sub int2ip {
	my $num = shift;
	return join(".", 
		($num & 0xFF000000) >> 24,
		($num & 0x00FF0000) >> 16,
		($num & 0x0000FF00) >> 8,
		($num & 0x000000FF)
	);
}

sub ipnetmask {
	my $bits = shift;
	return '0.0.0.0' unless $bits;
	my $num = 0xFFFFFFFF;
	my $mask = ($num >> (32 - $bits)) << (32 - $bits);
	return int2ip($mask);
}

sub ipwildmask {
	my $bits = shift;
	my $num = ip2int( ipnetmask($bits) );
	$num = $num ^ 0xFFFFFFFF;
	return int2ip($num);
}

sub ipbroadcast {
	my ($num, $bits) = @_;
	my @ip = split(/\./, int2ip($num));
	my @wc = split(/\./, ipwildmask($bits));
	my $bc = "";
	for (my $i=0; $i < 4; $i++) { $ip[$i] += $wc[$i]; }
	return join(".",@ip);
}

sub ipnumbits {
	my ($mask) = @_;
	my $bits = unpack('B32', pack('N', ip2int($mask)));
	return scalar grep { $_ eq '1' } split(//, $bits);
}


1;
