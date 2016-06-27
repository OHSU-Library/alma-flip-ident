#!/usr/bin/perl
#
# alma_flip_ident.pl - iterate through file of Alma primary IDs and brute force flip 
# Barcode ident to internal
#
# Format of input file:
# user_primary_id1
# user_primary_id2
# user_primary_idN...
#
# last updated: 6/26/16, np, OHSU Library

#----------------------------------------------------------------------------------------#
# 										DECLARATIONS
#----------------------------------------------------------------------------------------#
use strict;
use warnings;
use utf8;

use Cwd qw();
use File::Slurp;
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use LWP::UserAgent;
use Time::Piece;
use XML::Twig;

#----------------------------------------------------------------------------------------#
# 										  GLOBALS
#----------------------------------------------------------------------------------------#

# Alma API login/url:
my $API_USER 		= 'AlmaSDK-alma_api-institutionCode-01ALLIANCE_OHSU';
my $API_PASS 		= '3u63p,nctJX58}V';
my $API_BURL 		= 'https://na01.alma.exlibrisgroup.com:443/almaws/v1/users';

#----------------------------------------------------------------------------------------#
# 											MAIN
#----------------------------------------------------------------------------------------#

# exit and warn user if no data file is given:
if ($#ARGV == -1) {
	print "Please give me a file of Alma user primary_ids to process!\n";
	print "Script usage:  <" . $0 . "> <data_file.txt> <pre_change.xml> <post_change.xml>\n";
   	exit;
}

# get our current working dir:
my $path = Cwd::cwd() . '/';

# timestamp:
my $ts = localtime->strftime('%Y%m%d_%H%M%S');

# setup our file handler locations:
my $data_file = $ARGV[0];
my ($pre_change, $post_change, $fh_pre, $fh_post);
if (exists $ARGV[1]) {
	$pre_change = $ARGV[1];
	print "Sending pre_change data to file: " . $pre_change . "\n";
}
else {
	$pre_change = $path . $ts . '_pre_change.xml';
	print "No pre_change file path given, sending pre_change to file: " . $pre_change . "\n";
}
if (exists $ARGV[2]) {
	$post_change = $ARGV[2];
	print "Sending post_change data to file: " . $post_change . "\n";
}
else {
	$post_change = $path . $ts . '_post_change.xml';
	print "No post_change file path given, sending post_change to file: " . $post_change . "\n";
}

#open and prep FHs:
open $fh_pre, '>', $pre_change or do {
	warn "$0: open $pre_change: $!";
	return;
};
open $fh_post, '>', $post_change or do {
	warn "$0: open $post_change: $!";
	return;
};
print $fh_pre '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n";
print $fh_post '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' . "\n";

# create request obj and set content_type to XML:
my $ua = LWP::UserAgent->new(keep_alive => 0, 
								timeout => 45, 
								sl_opts => {SSL_verify_mode => 
											IO::Socket::SSL::SSL_VERIFY_NONE, 
											verify_hostname => 0});

# iterate through user list:
my @lines = read_file($data_file);
print "Begin processing file: " . $data_file . "\n";

foreach my $line (@lines){
	# our primary ID:
	my $api_pri_id = $line;
	chomp($api_pri_id);

	# make sure to get full record view (for barcodes and primary_id):
	my $req = new HTTP::Request(GET => ($API_BURL . '/' . $api_pri_id . '?view=full'));
	$req->content_type('application/xml');
	$req->authorization_basic($API_USER, $API_PASS);
	my $response = $ua->request($req);
	
	# user is a match, process it:
	if ($response->is_success) {
		# format and flush pre modified XML:
		my $twig_pre = XML::Twig->new(
			pretty_print => 'indented_a',
			keep_atts_order => 1,
			no_prolog => 1
		);
		$twig_pre->parse( $response->content );
		$twig_pre->flush( $fh_pre );
	
		# create post modified XML parser:	
		my $twig_post = XML::Twig->new(
        	pretty_print => 'indented_a',
        	keep_atts_order => 1,
			no_prolog => 1,  
        	twig_handlers => { 
           		q(user/user_identifiers/user_identifier[string(id_type)="BARCODE"]) => \&set_att,
        	}   
		);
		$twig_post->parse( $response->content );
		my $mod_xml = $twig_post->sprint;
		
		# attempt to PUT new XML:
		my $put = new HTTP::Request(GET =>($API_BURL . '/' . $api_pri_id . '?view=full'));
		use bytes;
		my $length = length($mod_xml);
		#no bytes;
		use utf8;

		#debug
		#print $mod_xml . "\n";

		$put->method('PUT');
		$put->content($mod_xml);
		$put->content_type('application/xml;charset=UTF-8');
		$put->content_length($length);
		$put->authorization_basic($API_USER, $API_PASS);

		my $put_res = $ua->request($put);

		if ($put_res->is_success) {
			# update client:
    		print "Barcode set to INTERNAL for user " . $api_pri_id . "\n";
		}
		else {
			print "Error setting INTERNAL barcode for user " . $api_pri_id . ": " . $put_res->status_line() . "\n";
		}
		
		# dump post XML data:
		$twig_post->flush( $fh_post );
	}
	else {
		print "No user found for primary_id = " . $api_pri_id . "\n";
	}
}

# cleanup:
close $fh_pre or warn "$0: close $fh_pre: $!";
close $fh_post or warn "$0: close $fh_post: $!";

print "Finished!\n";

#----------------------------------------------------------------------------------------#
# 											SUBS
#----------------------------------------------------------------------------------------#

# set_att() - set attribute segment_type to "Internal"
sub set_att {
    my ($t, $e) = @_;
    
    # set attribute:
    $e->set_att(segment_type => 'Internal');
}