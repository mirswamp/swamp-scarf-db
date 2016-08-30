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

package ScarfJSONReader;
use strict;
use JSON::SL;
use Scalar::Util qw[openhandle];
use IO qw[Handle Seekable File Pipe];
use Data::Dumper;

##########Initialize Reader##########
sub new
{
    my ($class, $source) = @_;
    my $hashref = {};
    my $self->{hashref} = $hashref;
    $self->{source} = $source;
    $self->{callbacks} = {};
    $self->{parser} = JSON::SL->new();
    $self->{readSize} = 4096;
    bless $self, $class;
}

sub SetReadSize
{
    my ( $self, $size ) = @_;
    $self->{readSize} = $size;
    return 0;
}

sub GetReadSize
{
    my ( $self ) = @_;
    return $self->{readSize};
}

#################Callback accessors/mutators###################
sub getUTF8
{
    my ($self) = @_;
    return $self->{parser}->utf8;
}

sub setUTF8
{
    my ($self, $utf) = @_;
    $self->{parser}->utf8($utf);
}

sub SetInitialCallback
{
    my ($self, $callback) = @_;
    $self->{callbacks}->{InitialCallback} = $callback;
}

sub SetBugCallback
{
    my ($self, $callback) = @_;
    $self->{callbacks}->{BugCallback} = $callback;
}

sub SetMetricCallback
{
    my ($self, $callback) = @_;
    $self->{callbacks}->{MetricCallback} = $callback;
}

sub SetBugSummaryCallback
{
    my ($self, $callback) = @_;
    $self->{callbacks}->{BugSummaryCallback} = $callback;
}

sub SetMetricSummaryCallback
{
    my ($self, $callback) = @_;
    $self->{callbacks}->{MetricSummaryCallback} = $callback;
}

sub SetFinalCallback
{
    my ($self, $callback) = @_;
    $self->{callbacks}->{FinalCallback} = $callback;
}

sub SetCallbackData
{
    my ($self, $callbackData) = @_;
    $self->{callbacks}->{CallbackData} = $callbackData;
}


sub GetInitialCallback
{
    my ($self) = @_;
    return $self->{callbacks}->{InitialCallback};
}

sub GetBugCallback
{
    my ($self) = @_;
    return $self->{callbacks}->{BugCallback};
}

sub GetMetricCallback
{
    my ($self) = @_;
    return $self->{callbacks}->{MetricCallback};
}

sub GetBugSummaryCallback
{
    my ($self) = @_;
    return $self->{callbacks}->{BugSummaryCallback};
}

sub GetMetricSummaryCallback
{
    my ($self) = @_;
    return $self->{callbacks}->{MetricSummaryCallback};
}

sub GetFinalCallback
{
    my ($self) = @_;
    return $self->{callbacks}->{FinalCallback};
}

sub GetCallbackData
{
    my ($self) = @_;
    return $self->{callbacks}->{CallbackData};
}


##########Initiate parsing of file##########
sub Parse
{
    my ( $self ) = @_;
    my $parser = $self->{parser};
    my $hash = {};
    my $return = undef;
    my $lastElt = "";
    my $validStart = 0;
    my $validBody = 0;
    $parser->set_jsonpointer( [ ("/^/tool_name", "/^/tool_version", "/^/uuid", "/^/^/^") ] );
    my $fh;
    if (ref $self->{source} eq "SCALAR"){	
	open( $fh, "<", $self->{source} ) or die "Could not open specified string\n";
    } elsif ( openhandle($self->{source}) or ref $self->{source} eq "IO" ){
	$fh = $self->{source};
    } else {
	open( $fh, "<", $self->{source} ) or die "Could not open specified file\n";
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
				$return = $self->{callbacks}->{InitialCallback}->($hash, $self->{callbacks}->{CallbackData});
				if ( defined $return ) {
				    last FINISH;
				}
			    } else {
				$return = $self->{callbacks}->{InitialCallback}->($hash);
				if (defined $return) {
				    last FINISH;
				}
			    }
			}
		    }

		} elsif ($obj->{Path} =~ /(\/AnalyzerReport\/BugInstances\/)([0-9]+)/) {
		    my $bug = $obj->{Value};
		    my @bugLocs;
		    for my $loc( @{$bug->{BugLocations}} ) {
			if ($loc->{primary}){
			    $loc->{primary} = 1;
			} else {
			    $loc->{primary} = 0;
			}
#			push @bugLocs, $loc;
		    }
#		    $bug->{BugLocations} = \@bugLocs;
		    for my $method( @{$bug->{Methods}} ) {
			if ($method->{primary}){
			    $method->{primary} = 1;
			} else {
			    $method->{primary} = 0;
			}
		    }
		    if ( defined $self->{callbacks}->{CallbackData} ) {
			$return = $self->{callbacks}->{BugCallback}->($obj->{Value}, $self->{callbacks}->{CallbackData});
			if (defined $return) {
			    last FINISH;
			}
		    } else {
			$return = $self->{callbacks}->{BugCallback}->($obj->{Value});
			if (defined $return) {
			    last FINISH;
			}
		    }
		    $validBody = 1;
	    
		} elsif ($obj->{Path} =~ /(\/AnalyzerReport\/Metrics\/)([0-9]+)/) {
		    if ( defined $self->{callbacks}->{CallbackData} ) {
			$return = $self->{callbacks}->{MetricCallback}->($obj->{Value}, $self->{callbacks}->{CallbackData});
			if (defined $return) {
			    last FINISH;
			}
		    } else {
			$return = $self->{callbacks}->{MetricCallback}->($obj->{Value});
			if (defined $return) {
			    last FINISH;
			}
		    }
		    $validBody = 1;
	    
		} elsif ($obj->{JSONPointer} =~ /\/AnalyzerReport\/BugSummaries\//) {
		    if ( defined $self->{callbacks}->{CallbackData} ) {
			$return = $self->{callbacks}->{BugSummaryCallback}->($obj->{Value}, $self->{callbacks}->{CallbackData});
			if (defined $return) {
			    last FINISH;
			}
		    } else {
			$return = $self->{callbacks}->{BugSummaryCallback}->($obj->{Value});
			if (defined $return) {
			    last FINISH;
			}
		    }
	    
		} elsif ($obj->{JSONPointer} =~ /\/AnalyzerReport\/MetricSummaries\//) {
		    $hash = $obj->{Value};
		    if ( defined $self->{callbacks}->{CallbackData} ) {
			$return = $self->{callbacks}->{MetricSummaryCallback}->($hash, $self->{callbacks}->{CallbackData});
			if (defined $return) {
			    last FINISH;
			}
		    } else {
			$return = $self->{callbacks}->{MetricSummaryCallback}->($hash);
			if (defined $return) {
			    last FINISH;
			}
		    }
		}
    	    }	
        }
    }

    if ( defined $self->{callbacks}->{FinalCallback} ) {
	$return = $self->{callbacks}->{FinalCallback}->($return, $self->{callbacks}->{CallbackData});
    }
    if ( $validBody == 0 ) {
	print (" No BugInstances or Metrics found in file \n" );
    }
    return $return;
}






return 1;
