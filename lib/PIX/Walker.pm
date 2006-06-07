package PIX::Walker;

use strict;
use warnings;

use Carp;
use PIX::Object;
use PIX::Accesslist;

BEGIN {
	use Exporter();

	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	$VERSION = '1.02';

	@ISA = qw(Exporter);
	@EXPORT = qw();
	@EXPORT_OK = qw();
	%EXPORT_TAGS = ();

}

=pod

=head1 NAME

PIX::Walker - Process Cisco PIX configs and 'walk' access-lists

=head1 SYNOPSIS

PIX::Walker is an object that allows you to process PIX firewall configs and 'walk' an access-list for matches.
PIX OS versions 6 and 7 are supported.

B<** This module is still in very early development **>

'Loose' ACL matching performed. This means that you can specify as little as a source IP to match what line(s) that IP
would match in the ACL on the firewall. Or you can provide every detail including source/dest IPs, ports, and protocol to 
match a specific line of an ACL. Loose matching allows you to see potential lines in a large ruleset that a single source or
destination IP might match.

More than just the first line match can be returned. 
If your search criteria can technically match multiple lines they will all be returned.
This is useful for seeing extra matches in your ACL that might also match and can help you optimize your ACL.

=head1 EXAMPLE

  use PIX::Walker;

  my $config = ' ... string of full firewall config ... ';
  my $fw = new PIX::Walker($config);
  my $acl = $fw->acl('outside_access') || die("ACL does not exist");

  my $matched = 0;
  foreach my $line ($acl->lines) {
    if ($line->match(
        source => '10.0.1.100', 
        dest => '192.168.1.3', 
        port => '80', 
        protocol => 'tcp')) {
      print "Matched ACL $acl->name ($acl->elements ACE)\n" if !$matched++;
      print $line->print, "\n";
    }
  }

=head1 METHODS

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { debug => 0 };
	my ($fw_config) = @_;
	my $conf;
	croak("Must provide firewall configuration") unless $fw_config;

	bless($self, $class);

	$self->{firewall} = '';

	my ($file, $host);

	$file = (split(/\n/, $fw_config, 2))[0];
	$host = (split(/\./, $file, 2))[0];

	if (-f $file) {
#		print "Reading from file\n";
		open(F, "<$file") or die("Error opening file for reading: $!");
		$conf = join('', <F>);
		close(F);
	} elsif (-f "$file.conf") {
#		print "Reading from conf file\n";
		open(F, "<$file.conf") or die("Error opening file for reading: $!");
		$conf = join('', <F>);
		close(F);
	} elsif (-f "$host") {
		print "Reading from host file\n";
#		open(F, "<$host") or die("Error opening file for reading: $!");
		$conf = join('', <F>);
		close(F);
	} elsif (-f "$host.conf") {
#		print "Reading from host conf file\n";
		open(F, "<$host.conf") or die("Error opening file for reading: $!");
		$conf = join('', <F>);
		close(F);
	} else {
		$conf = $fw_config;
	}
	croak("No firewall configuration found") unless $conf;
	$self->{config} = [ split(/\n/, $conf) ];
	$self->{config_block} = [ split(/\n/, $conf) ];

	$self->_init;
	$self->_process;

	return $self;
}

sub _init {
	my $self = shift;
	$self->{objects} = {};
	$self->{acls} = {};
	$self->{alias} = {};
	$self->{ports} = {
		# insert static entries here...
		'imap4'			=> '143',
		'h323'			=> '1720',
		'sqlnet'		=> '1521',
		'pcanywhere-data'	=> '5631',
		'pcanywhere-status'	=> '5632',
		'citrix-ica'		=> '1494',

		# cisco PIX defined
		'bgp'			=> '179',
		'biff'			=> '512',
		'bootpc'		=> '68',
		'bootps'		=> '67',
		'chargen'		=> '19',
		'cmd'			=> '514',
		'daytime'		=> '13',
		'discard'		=> '9',
		'domain'		=> '53',
		'dnsix'			=> '195',
		'echo'			=> '7',
		'exec'			=> '512',
		'finger'		=> '79',
		'ftp'			=> '21',
		'ftp-data'		=> '20',
		'gopher'		=> '70',
		'hostname'		=> '101',
		'https'			=> '443',
		'nameserver'		=> '42',
		'ident'			=> '113',
		'irc'			=> '194',
		'isakmp'		=> '500',
		'klogin'		=> '543',
		'kshell'		=> '544',
		'ldap'			=> '389',
		'ldaps'			=> '636',
		'lpd'			=> '515',
		'login'			=> '513',
		'mobile-ip'		=> '434',
		'netbios-ns'		=> '137',
		'netbios-dgm'		=> '138',
		'netbios-ssn'		=> '139',
		'nntp'			=> '119',
		'ntp'			=> '123',
		'pim-auto-rp'		=> '496',
		'pop2'			=> '109',
		'pop3'			=> '110',
		'rip'			=> '520',
		'smtp'			=> '25',
		'snmp'			=> '161',
		'snmptrap'		=> '162',
		'ssh'			=> '22',
		'sunrpc'		=> '111',
		'syslog'		=> '514',
		'tacacs'		=> '49',
		'talk'			=> '517',
		'telnet'		=> '23',
		'tftp'			=> '69',
		'time'			=> '37',
		'uucp'			=> '540',
		'who'			=> '513',
		'whois'			=> '43',
		'www'			=> '80',
		'xdmcp'			=> '177',
	};

	# look for services files (nmap is better) and build a translation table.
	# this reads ALL the files listed and merges the results into a single hash lookup table.
	# the first name-to-port lookup found is used and is not overwritten
#	my @files = qw( ./port-numbers /usr/local/share/nmap/nmap-services /usr/share/nmap/nmap-services /etc/services );
	my @files = qw( /usr/local/share/nmap/nmap-services /usr/share/nmap/nmap-services /etc/services );
	while (0 && defined(my $file = shift @files)) {
		next unless -f $file;
		open(F, "<$file") or next;
		while (defined(my $line = <F>)) {
			$line =~ s/^\s+//;
			$line =~ s/\s+$//;
			next if $line eq '' or $line =~ /^#/;
			my ($name, $str) = split(/\s+/, $line);
			my $port = (split(/\//, $str))[0];
			$self->{ports}{$name} = $port unless exists $self->{ports}{$name};
		}
		close(F);
#		last;	# uncomment this to only read the FIRST file found
	}
}

# INTERNAL: processes the configuration and breaks things apart into different bits
sub _process {
	my $self = shift;

	# continue until all config lines are gone
	while (defined(my $line = $self->_nextline)) {
		if ($line =~ /^object-group (\S+) (\S+)/i) {
			my ($type, $name) = ($1,$2);
			my $conf = [ $line ];
			$line = $self->_nextline;
			while (defined $line && $line =~ /^\s*(\w+-object|desc)/) {
				push(@$conf, $line);
				$line = $self->_nextline;
			}
			$self->_rewind($line);		# rewind 1 line so we don't skip past it on the next iteration
			$self->{objects}{$name} = new PIX::Object($type, $name, $conf, $self);
		} elsif ($line =~ /^access-list (\S+)/) {
			my $name = $1;
			next if $name eq 'compiled';
			my $conf = [ $line ];
			$line = $self->_nextline;
			while (defined $line && $line =~ /^access-list $name/) {
				push(@$conf, $line);
				$line = $self->_nextline;
			}
			$self->_rewind($line);
			$self->{acls}{$name} = new PIX::Accesslist($name, $conf, $self);			

		} elsif ($line =~ /^name (\S+) (.+)/) {
			$self->{alias}{$2} = $1;
		}
	}

}

=item B<acl($name)>

=over

Returns an B<PIX::Accesslist> object for the ACL named by $name.

=back

=cut
sub acl {
	my $self = shift;
	my $name = shift;
	return exists $self->{acls}{$name} ? $self->{acls}{$name} : undef;
}

=item B<acls()>

=over

Returns an array of PIX::Accesslist objects for each access-list 
found in the firewall configuration. Returns undef if there is no
matching ACL.

=back

=cut
sub acls { keys %{$_[0]->{acls}} }

=item B<alias($string)>

=over

Returns the IP of the alias given in $alias. If no alias is found than the
string is returned unchanged.

=back

=cut
sub alias {
	my $self = shift;
	my $string = shift;
	return exists $self->{alias}{$string} ? $self->{alias}{$string} : $string;
}

=item B<findip($ip, [$trace])>

=over

Matches the IP to an existing network-group. Does not validate it within any ACL.
If a single group is matched a scalar is returned with the name, otherwise an 
array reference is returned containing all matches.

* I<$ip> is an IP address to look for.

* I<$trace> is an optional reference to a trace buffer. 
If an IP is found in a nested group the trace will allow you to find out where 
it was nested. See L<tracedump()> for more information.

=back

=cut
sub findip {
	my ($self, $ip, $trace) = @_;
	my $found = [];

	foreach my $obj (keys %{$self->{objects}}) {
		my $grp = $self->{objects}{$obj};
		next unless $grp->type eq 'network';	# we only care about network groups
		my $localtrace = [];
		my $match = $grp->matchip($ip, $localtrace);
		if ($match) {
			push(@$trace, $localtrace) if defined $trace;
			push(@$found, $match);
		}
	}
	if (scalar @$found) {
		my %u;
		my @uniq = grep { !$u{$_}++ } sort @$found;
		return (scalar @uniq == 1) ? $uniq[0] : \@uniq;
	}
	return undef;
}

=item B<findport($port, [$trace])>

=over

Matches the PORT to an existing service-group. Does not validate it within any ACL.
If a single group is matched a scalar is returned with the name, otherwise an 
array reference is returned containing all matches.

* I<$port> is the PORT to look for.

* I<$trace> is an optional reference to a trace buffer. 
If a PORT is found in a nested group the trace will allow you to find out where 
it was nested. See L<tracedump()> for more information.

=back

=cut
sub findport {
	my ($self, $port, $trace) = @_;
	my $found = [];

	foreach my $obj (keys %{$self->{objects}}) {
		my $grp = $self->{objects}{$obj};
		next unless $grp->type eq 'service';	# we only care about service groups
		my $localtrace = [];
		my $match = $grp->matchport($port, $localtrace);
		if ($match) {
			push(@$trace, $localtrace) if defined $trace;
			push(@$found, $match);
		}
	}
	if (scalar @$found) {
		my %u;
		my @uniq = grep { !$u{$_}++ } sort @$found;
		return (scalar @uniq == 1) ? $uniq[0] : \@uniq;
	}
	return undef;
}

=item B<obj($name)>

=over

Returns an B<PIX::Object> object for the object-group that matches the $name given.

=back

=cut
sub obj {
	my $self = shift;
	my $name = shift;
	return exists $self->{objects}{$name} ? $self->{objects}{$name} : undef;
}


sub portnum { 
	my ($self, $port) = @_;
	return $port if $port =~ /^\d+$/;
	# using die() below is a bit harsh but I don't have a better way to deal with it for now.
	return exists $self->{ports}{$port} ? $self->{ports}{$port} : die("Unknown port name '$port'");
}

=item B<tracedump($trace)>

=over

Prints out the trace dump given. This will allow you to see where IP's and PORT's are being 
matched within their object-groups even if they are nested.

=over

	$matched = $fw->findip($ip, $trace);
	$fw->tracedump($trace);

=back

=cut
sub tracedump {
	my ($self, $trace) = @_;
	return '' unless defined $trace;
	print "\nMatch Trace: \n" if @$trace;
#	use Data::Dumper; print Dumper($trace); return;
	foreach my $tr (@$trace) {
		my $idx = 0;
		for (my $i=0; $i<@$tr; $i=$i+3) {
			my ($name, $line, $extra) = @$tr[$i..$i+2];
#			print "\t"x($idx++) . $name;
			print " -> " if $idx++;
			print $name;
			print " (match: $extra)" if $extra;
			print " (idx: $line)" if $line;
#			print "\n";
		}
		print "\n";
	}
	print "\n";
}

sub _nextline { shift @{$_[0]->{config_block}} }
sub _rewind { unshift @{$_[0]->{config_block}}, $_[1] }
sub _reset { $_[0]->{config_block} = $_[0]->{config} }

sub total_config_lines {
	my $self = shift;
	return 0 unless defined $self->{config};
	return scalar @{$self->{config}};
}
sub total_network_objects { my $self=shift; return scalar grep { $self->{objects}{$_}->{class} =~ /network$/ } keys %{$self->{objects}} }
sub total_service_objects { my $self=shift; return scalar grep { $self->{objects}{$_}->{class} =~ /service$/ } keys %{$self->{objects}} }
sub total_protocol_objects { my $self=shift; return scalar grep { $self->{objects}{$_}->{class} =~ /protocol$/ } keys %{$self->{objects}} }
sub total_icmp_type_objects { my $self=shift; return scalar grep { $self->{objects}{$_}->{class} =~ /icmp_type$/ } keys %{$self->{objects}} }
sub total_object_groups { return scalar keys %{$_[0]->{objects}} }
##sub total_acl_lines { return scalar @{$_[0]->{acl}} }

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

This POD document is the only support you will receive on this module.

=head1 ACKNOWLEDGEMENTS

B<Peter Vargo> - For pushing me to make this module and for supplying me with endless ideas.

=head1 COPYRIGHT & LICENSE

Copyright 2006 Jason Morriss, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
