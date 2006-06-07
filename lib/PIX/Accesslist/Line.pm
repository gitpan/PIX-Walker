package PIX::Accesslist::Line;

use strict;
use warnings;

our $VERSION = '1.00';

=pod

=head1 NAME

PIX::Accesslist::Line - Object for each line of an ACL line.

=head1 SYNOPSIS

PIX::Accesslist::Line is used by PIX::Accesslist to hold a single line of an ACL.

See B<PIX::Accesslist> for more information regarding PIX Accesslists.

 $line = new PIX::Accesslist::Line(
	$action, $proto, $source, 
	$sport, $dest, $dport, $idx
 );

=head1 METHODS

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { };
	my ($action, $protocol, $source, $sport, $dest, $dport, $idx) = @_;

	$self->{class} = $class;
	$self->{action} = lc $action;
	$self->{proto} = $protocol;
	$self->{source} = $source;
	$self->{sport} = $sport;
	$self->{dest} = $dest;
	$self->{dport} = $dport;
	$self->{idx} = $idx || 0;

	bless($self, $class);
	$self->_init;

	return $self;
}

sub _init { }

=item B<elements()>

=over

Returns the total elements (ACE) for the ACL line.
B<Note:> It's not wise to call this over and over again. Store the result
in a variable and use that variable if you need to use this result in multiple
places.

=back

=cut
sub elements {
	my $self = shift;
	my $total = 0;
	foreach my $proto ($self->{proto}->list) {
		$total++ unless $self->{source}->list;
		foreach my $src ($self->{source}->list) {
			$total++ unless $self->{dest}->list;
			foreach my $dest ($self->{dest}->list) {
				my @dport_list = $self->{dport} ? $self->{dport}->list : ();
				$total += scalar @dport_list ? @dport_list : 1;
			}
		}
	}
#	print "LINE " . $self->num . " has $total elements\n";
	return $total;
}

=item B<match(%args)>

=over

Returns a true value if the criteria given matches the logic of the ACL line. 
'Loose' matching is performed. For example, If you supply a single IP or port
a match may return TRUE on a line even though the final logic of the line might
overwise be FALSE according to the OS on the firewall. If you want to be sure 
you get accurate matching you must provide all criteria shown below.

=over

* source  Source IP

* sport   Source Port

* dest    Destination IP

* dport   Destionation Port

* proto   Protocol

=back

B<Note:> source port is not generally used. You will usually only want to use {dport}.

=back

=cut
sub match {
	my $self = shift;
	my $arg = ref $_[0] ? $_[0] : { @_ };
	my $ok = undef;
	$arg->{proto} ||= 'ip';		# default to IP

	# does the protocol match?
	if ($arg->{proto} eq 'ip') {
		$ok = 1;
	} else {
		$ok = scalar grep { lc $_ eq 'ip' or lc $_ eq $arg->{proto} } $self->{proto}->list;
	}
#	print "PROTO=".($ok||'')."\n";

	# does the source IP match our group?
	if ($ok and $arg->{source}) {
		$ok = $self->{source}->matchip($arg->{source});
		if ($ok and $arg->{sport} and $self->{sport}) {
			$ok = $self->{sport}->matchport($arg->{sport});
#			print "SPORT=".($ok||'')."\n";
		}
	}
#	print "SOURCE=".($ok||'')."\n";

	# does the destination IP match our group?
	if ($ok and $arg->{dest}) {
		$ok = $self->{dest}->matchip($arg->{dest});
		if ($ok and $arg->{dport} and $self->{dport}) {
			$ok = $self->{dport}->matchport($arg->{dport});
#			print "DPORT=".($ok||'')."\n";
		}
	}
#	print "DEST=".($ok||'')."\n";

	return $ok;
}

=item B<print()>

=over

Pretty prints the ACL line. Tries to make it easy to read. If object-group's are used
the names are printed instead of IP's if more than a single IP is present for a line.

  1)  permit (tcp)   192.168.0.0/24 -> 0.0.0.0/0 [Web_Services_tcp: 80,443]

=back

=cut
sub print {
	my $self = shift;
	my $output = '';

	$output .= sprintf("%3d) ", $self->{idx});
	$output .= sprintf("%6s %-10s", $self->{action}, "(" . join(',', $self->{proto}->list) . ")");
#	$output .= " -> ";
	$output .= $self->{source}->name =~ /^unnamed/ && $self->{source}->list == 1 ? $self->{source}->first : $self->{source}->name;
	if ($self->{proto}->first !~ /^(ip|icmp)$/ && $self->{sport}) {
		$output .= sprintf(" [%s]", $self->{sport}->name =~ /^unnamed/ && $self->{sport}->list == 1 ? $self->{sport}->first : $self->{sport}->name);
	}
	$output .= " -> ";
	$output .= $self->{dest}->name =~ /^unnamed/ && $self->{dest}->list == 1 ? $self->{dest}->first : $self->{dest}->name;
	if ($self->{proto}->first !~ /^(ip|icmp)$/) {
		if ($self->{dport}) {
			$output .= sprintf(" [%s]", $self->{dport}->name =~ /^unnamed/ && $self->{dport}->enumerate == 1  
				? join(',',$self->{dport}->enumerate) 
				: $self->{dport}->enumerate <= 4
					? $self->{dport}->name . ": " .join(',',$self->{dport}->enumerate) 
					: $self->{dport}->name . " (" . $self->{dport}->list . " ranges; " . $self->{dport}->enumerate . " ports)"
			);
		} else {
			$output .= " [any]";
		}
	}

	return $output;
}

=item B<num()>

=over

Returns the line number for the ACL line

=back

=cut
sub num { $_[0]->{idx} }

=item B<action(), permit(), deny()>

=over 

Returns the action string 'permit' or 'deny' of the ACL line, 
or true if the ACL line is a permit or deny, respectively.

=back

=cut
sub permit { $_[0]->{action} eq 'permit' }
sub deny   { $_[0]->{action} eq 'deny' }
sub action { $_[0]->{action} }

1; 


__DATA__

=head1 AUTHOR

Jason Morriss, C<< <lifo at liche.net> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-pix-walker at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=PIX-Walker>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

    perldoc PIX::Walker
    perldoc PIX::Accesslist
    perldoc PIX::Accesslist::Line

=head1 COPYRIGHT & LICENSE

Copyright 2006 Jason Morriss, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

