#!/usr/bin/env perl

=begin
	+------------------------------------------------------------------+
	| +--------------------------------------------------------------+ |
	| |   SERVICE & HOST - SMS Versand über gateway.mobilant.net     | |
	| |                                                              | |
	| |     Author: Enrico Labedzki <enrico.labedzki@netways.de>     | |
    | |     NETWAYS GmbH, www.netways.de, info@netways.de            | |
    | |     http://www.gnu.org/licenses/gpl-3.0.html                 | |
	| +--------------------------------------------------------------+ |
	+------------------------------------------------------------------+
=cut

use strict;
use warnings;
use feature qw( say switch );
use File::Basename qw( basename );
use LWP::UserAgent;
use Sys::Syslog;
use Try::Tiny;
use Getopt::Long;
use URI::Escape;
use Data::Dumper;
use constant {
	DEBUG		=> 0,
	OK			=> 0,
	WARNING		=> 1,
	CRITICAL	=> 2,
	UNKNOWN		=> 3
};

my $ssl			= 0;
my $proto		= "http";
my $help		= 0;
my $type		= undef;	# what type of check [service|host]
my $key			= "db2ec768d3b1350dfea9946208ecf09c";
#my $mobile		= "017661597565"; # pls don't use this number it's the authors private mobile
my $mobile		= "016090504799";

GetOptions(
	's|ssl'			=> \$ssl,
	'h|help'		=> \$help,
	't|type=s'		=> \$type,
	'k|key=s'		=> \$key,
	'm|mobile=s'	=> \$mobile
);

if( $help ) {
	say( "
		Usage: ". basename( $0 ) . " -t [host|service] -k CUSTOMERHASHKEY -m MOBILENUMBER
		Options:
			-h, --help
				Print detailed help screen
			-V, --version
				Print version information
			-t, --type
				What kind of Check this is a Host or Service as value [host|service]
			-k, --key
				The CustomerKey from mobilant.net
			-m, --mobile
				The Number to send that Notification.
		\n"
	);

	exit UNKNOWN;
}

unless( defined $type or defined $key or defined $mobile ) {
	say( "Usage: ". basename( $0 ) ." -t [host|service] -k CUSTOMERHASHKEY -m MOBILENUMBER" );
	exit UNKNOWN; 
}

my $object = {
	date	=> $ENV{LONGDATETIME}||"unknown",
	host	=> {
		name			=> $ENV{HOSTNAME}||"unknown",
		display_name	=> $ENV{HOSTALIAS}||"unknown",
		address			=> $ENV{HOSTADDRESS}||"unknown",
		state			=> $ENV{HOSTSTATE}||"unknown",
		state_type		=> $ENV{HOSTSTATETYPE}||"unknown",
		last_state		=> $ENV{HOSTLASTSTATE}||"unknown",
		last_state_type	=> $ENV{HOSTLASTSTATETYPE}||"unknown",
		output			=> $ENV{HOSTOUTPUT}||"unknown",
		perfdata		=> $ENV{HOSTPERFDATA}||"unknown"
	},
	service	=> {
		name			=> $ENV{SERVICEDESC}||"unknown",
		display_name	=> $ENV{SERVICEDISPLAYNAME}||"unknown",
		state			=> $ENV{SERVICESTATE}||"unknown",
		output			=> $ENV{SERVICEOUTPUT}||"unknown"
	},
	notification => {
		type	=> $ENV{NOTIFICATIONTYPE}||"unknown",
		comment	=> $ENV{NOTIFICATIONCOMMENT}||"unknown",
		author	=> $ENV{NOTIFICATIONAUTHORNAME}||"unknown"
	}
};

my $msg = ( lc($type) eq "host" )
			? uri_escape( 
				"***** Icinga  *****\n\n".
				"Notification Type: ". $object->{notification}->{type} ."\n".
				"Host: ". $object->{host}->{display_name} ."\n".
				"Address: ". $object->{host}->{address} ."\n".
				"State: ". $object->{host}->{state} ."\n\n".
				"Date/Time: ". $object->{date} ."\n\n".
				"Additional Info: ". $object->{host}->{output} ."\n\n".
				"Comment: [". $object->{notification}->{author} ."] ". $object->{notification}->{comment}
			)
			: uri_escape(
				"***** Icinga  *****\n\n".
				"Notification Type: ". $object->{notification}->{type} ."\n".
				"Service: ". $object->{service}->{name} ."\n".
				"Host: ". $object->{host}->{display_name} ."\n".
				"Address: ". $object->{host}->{address} ."\n".
				"State: ". $object->{service}->{state} ."\n\n".
				"Date/Time: ". $object->{date} ."\n\n".
				"Additional Info: ". $object->{service}->{output} ."\n\n".
				"Comment: [". $object->{notification}->{author} ."] ". $object->{notification}->{comment}
			);

my $ua		= undef;
if( $ssl ) {
	$proto	= "https";
	$ua		= LWP::UserAgent->new( ssl_opts => { verify_hostname => 1 } );
} else {
	$ua		= LWP::UserAgent->new();
}
$ua->timeout( 10 );

my $response = $ua->head( $proto."://gateway.mobilant.net/?key=".$key."&handynr=".$mobile."&text=".$msg."&service=live" );
 
if( $response->is_success() ) {
	if( $response->status_line =~ m/^\d+\s+.*/ ) {
		my( $code, $text ) = $response->status_line =~ m/^(\d+)\s+(.*)/;
		if( $code > 200 ) {
			syslogmsg( basename( $0 ).": http/REST return code: ". $code ." message: ". $text );
			exit CRITICAL;
		} else {
			exit OK;
		}
	} else {
		# a unknown error condition, should never be happend
		syslogmsg( basename( $0 ).": unknown http response" );
		exit UNKNOWN;
	}
}
else {
	# syslog message gateway possibly  down or a wrong http method/protocol
    syslogmsg( basename( $0 ).": a timeout occurred or SMS-gateway is down or unsupported method/protocol ???" );
	exit CRITICAL;
}

sub syslogmsg {
	$_ = shift;
	if( DEBUG ) {
		say( $_ );
	} else {
		openlog( "monitoring", "ndelay,pid,perror", LOG_DAEMON );
		syslog( LOG_ERR, $_ );
		closelog();
	}
}
