# $Id$
##############################################################################
#
#     70_Growl.pm
#     An FHEM Perl module to send push messages via https://www.Growlapp.com/
#
#     Copyright by Oli Merten
#     e-mail: oli.merten at gmail.com
#
#     This file luckily is not part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
# 	  Changelog:
#	  09.10.2016: Initial Version 
#	  11.10.2016: Version 0.1.01: added disabled attribute
##############################################################################

package main;

use strict;
use warnings;
use HttpUtils;

my $missingModul;
eval "use Data::Dumper;1" or $missingModul .= "Data:Dumper ";
eval "use Growl::GNTP;1" or $missingModul .= "Growl::GNTP ";

my $version     = "0.1.00";

###################################
sub Growl_Initialize($) {
    my ($hash) = @_;

    # Module specific attributes
    my @Growl_attr =( 
		"default_prio:-2,-1,0,1,2", 
		"default_event", 
		"default_application", 
		"default_sticky:true,false", 
		"Growl_passwd",
		"disable:0,1"
		);

    $hash->{GetFn}    = "Growl_Get";
    $hash->{SetFn}    = "Growl_Set";
    $hash->{DefFn}    = "Growl_Define";
    $hash->{UndefFn}  = "Growl_Undefine";
    $hash->{AttrFn}   = "Growl_Attr";
    $hash->{AttrList} = join( " ", @Growl_attr ) . " " . $readingFnAttributes;

}
###################################
sub Growl_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

	
	return "Error: Perl moduls ".$missingModul."are missing on this system" if $missingModul;
	
    my $usage = "syntax: define <name> Growl [<host>]";

	if ( int(@a) < 2 or int(@a) > 3) {
        return $usage;
    }
	
    my ( $name, $type) = @a;
	
	my $host = "localhost";
	if ($a[2]) {
		$host = $a[2];
	};
	$hash->{DEF} = $host;
	
    Log3 $name, 3, "Growl defined: $name $type $host";

    $hash->{VERSION} = $version;

    if (!Growl_addExtension( $name, "Growl_Callback", $name )) 
		{return "Extension with $name alreay existing?";}
	
    if ($init_done){
    	#Growl_GetUpdate($hash);
    }

    return undef;
}

###################################
sub Growl_Undefine($$) {

    my ( $hash, $name ) = @_;

    RemoveInternalTimer($hash);
	Growl_removeExtension( $hash->{fhem}{$name} );

    return undef;
}

###################################
sub Growl_Set($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{STATE};

    return "No Argument given" if ( !defined( $a[1] ) );
	if ( AttrVal( $name, "disable", 0 ) == 1 ) {
		Log3 $name, 5, "Growl $name: Unable to send message: Device is disabled";
		return "Unable to send message: Device is disabled";
	}
	  
	  
	Log3 $name, 5, "Growl $name: called function Growl_Set() with " . Dumper(@a);
    
	my $usage = "Unknown argument " . $a[1] . ", choose one of msg";
	
    # Send a message
    if ( $a[1] eq "msg" ) {
        return Growl_SendMessage( $hash, splice( @a, 2 ) );
    }

    # return usage hint
    else {
        return $usage;
    }
    return undef;
}
###################################
sub Growl_Get($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{STATE};

    return "No Argument given" if ( !defined( $a[1] ) );
	
	# Log3 $name, 5,
      # "Growl $name: called function Growl_Get() with " . Dumper(@a);

    my $usage =
       "Unknown argument " . $a[1] . ", choose one of url";
    my $error = undef;

    
    if ( $a[1] eq "url" ) {
		my $link = "/$name";
        $error = Dumper(%FW_httpheader->{Host});
    }

    # # get a token
    # elsif ( $a[1] eq "token" ) {
        # $error = Growl_GetToken($hash);
    # }

    # return usage hint
    else {
        return $usage;
    }
    return $error;
}

###################################
sub Growl_Attr($) {

    my ( $cmd, $name, $aName, $aVal ) = @_;

    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    if ( $cmd eq "set" ) {

        # Priroity has to be between -2 and 2
        if ( $aName eq "default_prio" ) {
            if ( $aVal > 2 or $aVal < -2 ) {
                Log3 $name, 3,
                  "$name: $aName is a value between -2 and +2: $aVal";
                return "Attribute " . $aName
                  . " has to be a value between -2 and +2";
            }
        }
        elsif ( $aName eq "default_sticky" ) {
            if ( $aVal ne "true" and $aVal ne "false" ) {
                Log3 $name, 3,
                  "$name: $aName is either 'true' or 'false': $aVal";
                return "Attribute " . $aName
                  . " has to be either 'true' or 'false'";
            }
        }
		
	}
    return undef;
}
###################################
# Helper Functions                #
###################################

sub Growl_SendMessage($@) {
    my ( $hash, @a ) = @_;
   
    my $name   = $hash->{NAME};

    my $msgStr = join( " ", @a );

    Log3 $name, 5, "Growl $name received $msgStr";
    
	my ( $desc, $prio, $sticky, $event, $app ) = split /:/, $msgStr;
    
	if ( !$desc ) {
        Log3 $name, 1, "Growl $name Message requires a text";
        return "set msg: Message requires a text";
    }
    
	if ( !$prio ) {
        $prio = AttrVal( $name, "default_prio", "1" );
    }
    if ( !$event ) {
        $event = AttrVal( $name, "default_event", "Nachricht" );
    }
    if ( !$app ) {
        $app = AttrVal( $name, "default_application", "FHEM" );
    }
    if ( !$sticky ) {
        $sticky = AttrVal( $name, "default_sticky", "false" );
    }

	my $pass = AttrVal( $name, "Growl_passwd", "");
	
	my $callback="http://".%FW_httpheader->{Host}."/fhem/$name";
	
	eval {
	
		my $growl = Growl::GNTP->new(
			AppName => "FHEM Growl Module", 
			PeerHost => $hash->{DEF}, 
			Password => $pass, 
			Debug=>"0"
		);
	  
		$growl->register([
			{
			Name        => $app,
			DisplayName => $app,
			#Enabled     => 'True',
			#Sticky      => 'False',
			#Priority    => 0,  # -2 .. 2 low -> severe
			#Icon        => ''
			}
		]);
		$growl->wait('WAIT_ALL');
		$growl->notify(
			Event               => $app, # name of notification
			Title               => $event,
			Message             => $desc,
			#Icon                => 'http://www.example.com/myface.png',
			CallbackTarget      => $callback, # Used for causing a HTTP/1.1 GET request exactly as specificed by this URL. Exclusive of CallbackContext
			CallbackContextType => time,
			CallbackContext     => $hash,
			#CallbackFunction    => \&Growl_Callback, 
			# should only be used when a callback in use, and CallbackContext in use.
			#ID                  => '', # allows for overriding/updateing an existing notification when in use, and discriminating between alerts of the same Event
			#Custom              => { CustomHeader => 'value' }, # These will be added as custom headers as X-KEY : value, where 'X-' is prefixed to the key
			Priority            => $prio,
			Sticky             => $sticky
		); 
		$growl->wait('WAIT_ALL');
	};
	if ($@) {
		Log3 $name, 1, "Growl $name Error: ".Dumper($@) ;
		readingsBeginUpdate($hash);
		readingsBulkUpdate( $hash, "lastError", $@ );
		readingsBulkUpdate( $hash, "state", "error");
		readingsEndUpdate( $hash, 1 );
	}
	else {
		Log3 $name, 3, "Growl $name sent message: $desc";
		readingsBeginUpdate($hash);
		readingsBulkUpdate( $hash, "lastMessage", $desc);
		readingsBulkUpdate( $hash, "state", "success");
		readingsEndUpdate( $hash, 1 );
	}
}
###################################
sub Growl_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";

    return 0
      if ( defined( $data{FWEXT}{$url} )
        && $data{FWEXT}{$url}{deviceName} ne $name );

    Log3 $name, 2,
      "Growl $name: Registering Growl with URL $url ...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
    
    return 1;
}

###################################
sub Growl_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2,
      "Growl $name: Unregistering Growl for URL $url...";
    delete $data{FWEXT}{$url};
    
}
###################################
sub Growl_Callback(@) {
	my ($request) = @_;
	Log3 "growl2", 3, "Growl received Callback: ".Dumper($request);
	my $hash;
    my $name = "";
    my $link = "";
    my $URI  = "";
	my $msg = "ok";

    # data received
    if ( $request =~ m,^(/[^/]+?)(?:\&|\?)(.*)?$, ) {
        $link = $1;
        $URI  = $2;
	
	# get device name
    $name = $data{FWEXT}{$link}{deviceName} if ( $data{FWEXT}{$link} );
    $hash = $defs{$name};
	}
	
	Log3 $name, 3, "Growl $name received Callback: ".Dumper($request);


	return ( "text/plain; charset=utf-8", $msg );
}
