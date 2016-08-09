#!/usr/bin/perl -w

#  Copyright 2016 Brandon G. Klein
# 
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#  

package JSONToHash;
use strict;
use JSON::SL;
use Scalar::Util qw[openhandle];
use IO qw[Handle Seekable File Pipe];
use Data::Dumper;

##########Initialize Reader##########
sub new
{
    my ($class, $source, $callbacks) = @_;
    my $hashref = {};
    my $self->{hashref} = $hashref;
    $self->{source} = $source;
    die "no callbacks detected" if !(defined $callbacks);
    $self->{callbacks} = $callbacks;
    $self->{parser} = JSON::SL->new();
    $self->{readSize} = 4096;
    bless $self, $class;
}

sub setReadSize
{
    my( $self, $size ) = @_;
    $self->{readSize} = $size;
    return 0;
}


##########Initiate parsing of file##########
sub parse
{
    my ( $self ) = @_;
    my $parser = $self->{parser};
    my $hash = {};
    my $lastElt = "";
    my $validStart = 0;
    my $validBody = 0;
    $parser->set_jsonpointer( [ ("/^/tool_name", "/^/tool_version", "/^/uuid", "/^/^/^") ] );
    my $fh;
    if (ref $self->{source} eq "SCALAR"){
	open( $fh, "<", ${$self->{source}} );
    } elsif ( openhandle($self->{source}) or ref $self->{source} eq "IO" ){
	$fh = $self->{source};
    } else {
	print("Invalid source file\n");
	exit(1);
    }
    local $/ = \$self->{readSize}; 
    FINISH: {
	while (my $buf = <$fh>) {
	    $parser->feed($buf); #parse what you can
	    #fetch anything that completed the parse and matches the JSON Pointer

	    while (my $obj = $parser->fetch) {
		my $tempHash = {};
		if ( ! ( $validStart ) ) {
		    if ( $obj->{JSONPointer} eq "/^/tool_name" ) { 
			$hash->{tool_name} = $obj->{Value};
		    } elsif ( $obj->{JSONPointer} eq "/^/tool_version" ) { 
			$hash->{tool_version} = $obj->{Value};
		    } elsif ( $obj->{JSONPointer} eq "/^/uuid" ) { 
			$hash->{uuid} = $obj->{Value};
		    }	 
		    if ( defined $hash->{tool_name} && defined $hash->{tool_version} && defined $hash->{uuid} ) {
			$validStart = 1;
			if ( defined $self->{callbacks}->{InitialCallback} ) {
			    if ( defined $self->{callbacks}->{CallbackData} ) {
				$self->{callbacks}->{InitialCallback}->($hash, $self->{callbacks}->{CallbackData}) and last FINISH;
			    } else {
				$self->{callbacks}->{InitialCallback}->($hash) and last FINISH;
			    }
			}
		    }

		} elsif ($obj->{Path} =~ /(\/AnalyzerReport\/BugInstances\/)([0-9]+)/) {
		    my $bug = $obj->{Value};
		    my @bugLocs;
		    for my $loc( @{$bug->{BugLocations}} ) {
			if ($loc->{primary} eq "true"){
			    $loc->{primary} = 1;
			} else {
			    $loc->{primary} = 0;
			}
#			push @bugLocs, $loc;
		    }
#		    $bug->{BugLocations} = \@bugLocs;
		    for my $method( @{$bug->{Methods}} ) {
			if ($method->{primary} eq "true"){
			    $method->{primary} = 1;
			} else {
			    $method->{primary} = 0;
			}
		    }
		    if ( defined $self->{callbacks}->{CallbackData} ) {
			$self->{callbacks}->{BugCallback}->($obj->{Value}, $self->{callbacks}->{CallbackData}) and last FINISH;#$hash);
		    } else {
			$self->{callbacks}->{BugCallback}->($obj->{Value}) and last FINISH;#$hash);
		    }
		    $validBody = 1;
	    
		} elsif ($obj->{Path} =~ /(\/AnalyzerReport\/Metrics\/)([0-9]+)/) {
		    if ( defined $self->{callbacks}->{CallbackData} ) {
			$self->{callbacks}->{MetricCallback}->($obj->{Value}, $self->{callbacks}->{CallbackData}) and last FINISH;#$hash);
		    } else {
			$self->{callbacks}->{MetricCallback}->($obj->{Value}) and last FINISH;#$hash);
		    }
		    $validBody = 1;
	    
		} elsif ($obj->{JSONPointer} =~ /\/AnalyzerReport\/BugSummaries\//) {
		    if ( defined $self->{callbacks}->{CallbackData} ) {
			$self->{callbacks}->{BugSummaryCallback}->($obj->{Value}, $self->{callbacks}->{CallbackData}) and last FINISH;#$hash);
		    } else {
			$self->{callbacks}->{BugSummaryCallback}->($obj->{Value}) and last FINISH;#$hash);
		    }
	    
		} elsif ($obj->{JSONPointer} =~ /\/AnalyzerReport\/MetricSummaries\//) {
		    $hash = $obj->{Value};
		    if ( defined $self->{callbacks}->{CallbackData} ) {
			$self->{callbacks}->{MetricSummaryCallback}->($hash, $self->{callbacks}->{CallbackData}) and last FINISH;
		    } else {
			$self->{callbacks}->{MetricSummaryCallback}->($hash) and last FINISH;
		    }
		}
    	    }	
        }
    }

    if ( defined $self->{callbacks}->{FinishCallback} ) {
	$self->{callbacks}->{FinishCallback}->($self->{callbacks}->{CallbackData});
    }
    if ( $validBody == 0 ) {
	print (" No BugInstances or Metrics found in file \n" );
    }
}






return 1;
