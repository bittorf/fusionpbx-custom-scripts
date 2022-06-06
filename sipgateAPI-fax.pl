#!/usr/bin/perl -w
#
# Sam Buca, indigo networks GmbH, 08/2007
#
# This script is a very basic perl-client to the SAMURAI service 
# provided by sipgate (indigo networks GmbH) without any claim to 
# completeness and without any warranty!
#
# The following code shows how to use the service to send fax-messages
# using a sipgate account. 
# Note: This example does not check for the state / success of the 
# sending process, so you will have to check that on the sipgate website.
# If you need such functionality in your code check the documentation for 
# the provided XMLRPC-method "samurai.SessionStatusGet" !
#

use strict;
use Frontier::Client;	# needed for XMLRPC
use MIME::Base64;		# we need to encode the PDF Base64

# declare some variables for later use:
my $VERSION = "1.0";
my $NAME	= "sipgateAPI-fax.pl";
my $VENDOR	= "indigo networks GmbH";
my $url;
my $xmlrpc_client;
my $xmlrpc_result;
my $args_identify;
my $args;
my $content_binary;
my $content_base64;

# check the count of commandline parameters and show usage information 
# if not matching:
unless (@ARGV == 4) {
	print "\n";
	print "This script needs 4 parameters supplied on the commandline:\n";
	print "\n";
	print "parameter 1 -> the username (not SIPID) used to login to sipgate\n";
	print "parameter 2 -> the password associated with the username\n";
	print "parameter 3 -> the number to send the fax-message to\n";
	print "               (with national prefix, e.g. 4921xxxxxxxxx)\n";
	print "parameter 4 -> the name of the PDF-file to send\n";
	print "\n";

	exit 0;
}

# define URL for XMLRPC:

#$url = "https://$ARGV[0]:$ARGV[1]\@samurai.sipgate.net/RPC2";		# other
$url = "https://$ARGV[0]:$ARGV[1]\@api.sipgate.net/RPC2";		# team

#print "url: '$url'\n";

# create an instance of the XMLRPC-Client:

$xmlrpc_client = Frontier::Client->new( 'url' => $url );

# identify the script to the server calling XMLRPC-method "samurai.ClientIdentify"
# providing client-name, -version and -vendor:

$args_identify = { ClientName => $NAME, ClientVersion => $VERSION, ClientVendor => $VENDOR };

$xmlrpc_result = $xmlrpc_client->call( "samurai.ClientIdentify", $args_identify );

# the check for success is not necessary in this case since the Frontier::Client module 
# dies with an exception in case of a fault, but we do it for completeness:

if ($xmlrpc_result->{'StatusCode'} == 200) {
    print "Successfully identified to the server!\n";
} else {
	# we should never get here!
	print "There was an error during identification to the server!\n";
}

# read the PDF file ...

open( PDF, $ARGV[3] ) or die ("Cannot open PDF file!\n");
binmode( PDF );
while ( my $line = <PDF>) {
	$content_binary .= $line;
}
close( PDF );

# ... and encode it Base64:

$content_base64 = MIME::Base64::encode($content_binary);

# create the input argument set for XMLRPC:

$args = { RemoteUri => "sip:$ARGV[2]\@sipgate.net", TOS => "fax", Content => $content_base64 };

# do the call and store the result / answer to $xmlrpc_result

$xmlrpc_result = $xmlrpc_client->call( "samurai.SessionInitiate", $args );

# again we do the check on success for completeness:

if ($xmlrpc_result->{'StatusCode'} == 200) {
    print "Your request was successfully send to the server!\n";
	print "The request was assigned the ID '".$xmlrpc_result->{'SessionID'}."'.\n";
	print "You may use this ID to reference the request in other XMLRPC methods, e.g. 'samurai.SessionStatusGet' to obtain the status of the sending process.\n";
} else {
	# we should never get here!
	print "There was an error!\n";
}
