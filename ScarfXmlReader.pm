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

package ScarfXmlReader;
use strict;
use XML::Parser;
use Scalar::Util qw[openhandle];
use IO qw[Handle Seekable File Pipe];
##########Initialize Reader##########
sub new
{
    my ($class, $source) = @_;
    my $hashref = {};
    my $self->{hashref} = $hashref;
    $self->{lastElt} = "";
    $self->{source} = $source;
    $self->{callbacks} = {};
    $self->{parser} = new XML::Parser ();
    $self->{validStart} = 0;
    $self->{validBody} = 0;
    $self->{encoding} = "UTF-8";
    $self->{return} = undef;

    bless $self, $class;

}

#################Callback accessors/mutators###################
sub SetEncoding 
{
my ($self, $enc) = @_;
$self->{encoding} = $enc;
}
sub GetEncoding
{
my ($self) = @_;
return $self->{encoding};
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
    my $hash = {};
    $self->{return} = undef;
    my $lastElt = "";
    $self->{parser}->setHandlers(
				    "Start", sub { $hash = startHandler( \$hash, \$lastElt, 
					    $self->{callbacks}->{InitialCallback}, \$self->{validStart}, 
					    \$self->{validBody}, $self->{callbacks}->{CallbackData}, \$self->{return},  @_ ) },
				    "End", sub { $hash = endHandler( \$hash, \$lastElt, 
					    $self->{callbacks}->{BugCallback},  $self->{callbacks}->{MetricCallback},
					    $self->{callbacks}->{BugSummaryCallback}, $self->{callbacks}->{MetricSummaryCallback},
					    \$self->{validBody}, $self->{callbacks}->{FinalCallback}, $self->{callbacks}->{CallbackData}, \$self->{return}, @_ ) },
				    "Char", sub { $hash = charHandler( \$hash, \$lastElt, @_ ) },
				    "Default" ,\&defaultHandler
				);
    #possibly use xsdValidator to verify scarf
    #$self->{parser}->parsefile($self->{source});
    if (openhandle($self->{source}) or ref $self->{source} eq "IO" or ref $self->{source} eq "SCALAR"){ 
	$self->{parser}->parse($self->{source}, ProtocolEncoding => $self->{encoding});
    } else {
	my $file;
	open($file, "<", $self->{source}) or die "Can't open source with filename ${$self->{source}}\n";
	$self->{parser}->parse($file, ProtocolEncoding => $self->{encoding});
    }
    if ( $lastElt eq "FINISHED" ) {
	return $self->{return};
    } else {
	if (exists $self->{callbacks}->{FinalCallback}){
	    return $self->{callbacks}->{FinalCallback}->($self->{return}, $self->{callbacks}->{CallbackData});
	} else {
	    return $self->{return};
	}
    }
}


##########Handler for start tags##########
sub startHandler
{
    my ( $hash, $lastElt, $initialcallback, $validStart, $validBody, $data, $ret, $parser, $elt, %atts ) = @_;
    if ( $elt eq "AnalyzerReport" ) {
	if (defined $initialcallback){
	    if ( $$validStart ) {
		print ("Invalid SCARF File: Multiple Start Tags\n");
	    } else {
		$$validStart = 1;
	    }
	    $$hash = { tool_name => $atts{tool_name}, tool_version => $atts{tool_version}, uuid => $atts{uuid} };
	    $$ret = $initialcallback->( $$hash, $data );
	    if ( defined $$ret ) {
		$parser->finish;
	    }
	    $$hash = {};
	} else { 
	    $$validStart = 1;
	}

    } else {
	if ( $$validStart == 0 ) {
	    print ("Invalid SCARF File: No Analyzer Report Start Tag\n");
	}
        if ( $elt eq "BugInstance" ) {
            $$hash->{BugId} = $atts{id};
	    $$validBody = 1;
        } elsif ( $elt eq "Metric" ) {
            $$hash = {#Value => undef, Class => undef, 
            		    SourceFile => undef, MetricId => $atts{id}, Method => undef, Type => undef
            		    };  
	    $$validBody = 1;
        } elsif ( $elt eq "BugCategory" ) {
            $$hash->{$atts{code}}->{$atts{group}} = { bytes => $atts{bytes}, count => $atts{count} };
        } elsif ( $elt eq "MetricSummaries" ) {
            my @metricSum = ();
            $$hash->{MetricSummaries} = [@metricSum];
        } elsif ( $elt eq "MetricSummary" ) {
            my $sum = {};
            push @{$$hash->{MetricSummaries}}, $sum;
        } elsif ( $elt eq "Methods" ) {
            my @methods = ();
            $$hash->{Methods} = [@methods];
        } elsif ( $elt eq "Method" && defined $$hash->{Methods} ) {
            my $primary;
            if ( $atts{primary} eq "true" ) {
                $primary = 1;
            } else {
                $primary = 0;
            }
            my $method = {MethodId => $atts{id}, primary => $primary};
            push @{$$hash->{Methods}}, $method;
        } elsif ( $elt eq "BugLocations" ) {
            my @locs = ();
            $$hash->{BugLocations} = [@locs];
        } elsif ( $elt eq "Location" && defined $$hash->{BugLocations} ) {
            my $primary;
            if ( $atts{primary} eq "true" ) {
                $primary = 1;
            } else {
                $primary = 0;
            }
            my $loc = {LocationId => $atts{id}, primary => $primary};
            push @{$$hash->{BugLocations}}, $loc;
        } elsif ( $elt eq "InstanceLocation" ) {
            $$hash->{InstanceLocation} = {};
        } elsif ( $elt eq "LineNum" && defined $$hash->{InstanceLocation} ) {
            $$hash->{InstanceLocation}->{LineNum} = {};
        }
    }
    $$lastElt = $elt;
    return $$hash;
}


#########Handler for end Tags###########
sub endHandler
{
    my ( $hash, $lastElt, $bugcallback, $metriccallback, $bugsumcallback, $metricsumcallback, $validBody, 
	    $finishcallback, $data, $ret, $parser, $elt ) = @_;    
    for my $cmpElt ( qw/AssessmentReportFile BugCode BugRank ClassName BugSeverity BugGroup BugMessage ResolutionSuggestion Class/ ) {
	if ( $elt eq $cmpElt ) {
	    $$hash->{$elt} =~ s/(^\s+)|(\s+$)//g;
	}
    }
    for my $locElt ( qw/Explanation/ ) {
	if ( $elt eq $locElt ) {
	    @{$$hash->{BugLocations}}[-1]->{$elt} =~ s/(^\s+)|(\s+$)//g;	    
	}
    }

    if ( $elt eq "BugInstance" && defined $bugcallback ) {
	$$ret = $bugcallback->( $$hash, $data );
	if (defined $$ret){
	    $parser->finish;
	}
	$$hash = {};
    } elsif ( $elt eq "Metric" && defined $metriccallback ) {
	if( ! defined $$hash->{SourceFile} ) {
	    delete $$hash->{SourceFile};
	}
	if( ! defined $$hash->{Type} ) {
	    delete $$hash->{Type};
	}
	if( ! defined $$hash->{Method} ) {
	    delete $$hash->{Method};
	}
	$$ret = $metriccallback->( $$hash, $data );
	if (defined $$ret) {
	    $parser->finish;
	}
        $$hash = {};

    } elsif ( $elt eq "BugSummary" && defined $bugsumcallback ) {
	$$ret = $bugsumcallback->( $$hash, $data );
	if (defined $$ret){
	    $parser->finish; 
	}
	$$hash = {};

    } elsif ( $elt eq "MetricSummaries" && defined $metricsumcallback ) {
	$$ret = $metricsumcallback->( $$hash, $data );
	if (defined $$ret) {
	    $parser->finish;
	}
        $$hash = {};

    } elsif ( $elt eq "AnalyzerReport") {
	if ( ! $$validBody ) {
	    printf "No BugInstances or Metrics found in file.\n";
	}
	if ( defined $finishcallback ) {
	    $$ret = $finishcallback->($$ret, $data);
	    if (defined $$ret) {
		$$lastElt = "FINISHED";
		$parser->finish;
		return $$hash;
	    }
	}
    } elsif ( $elt eq "Metric" or $elt eq "BugInstance" or $elt eq "BugSummary" or $elt eq "MetricSummaries" ) {
	$$hash = {};
    }
    $$lastElt = "";
    return $$hash;
}


##########Handler for content of elements##########
sub charHandler
{
    my ( $hash, $lastElt, $parser, $chars ) = @_;
    my $elt = $$lastElt;
    for my $simpleElt ( qw/AssessmentReportFile BuildId BugCode BugId BugRank ClassName BugSeverity BugGroup
    BugMessage ResolutionSuggestion Class Value/ ) {
	if ( $elt eq $simpleElt ) {
	    if ( not exists $$hash->{$elt} ) {
		$$hash->{$elt} = $chars;
	    } else {
		$$hash->{$elt} .= $chars;
	    }
	    return $$hash;
	}
    }

    for my $metricSumElt ( qw/Type Count Sum SumOfSquares Minimum Maximum Average StandardDeviation/ ) {
	if ( $elt eq $metricSumElt && defined $$hash->{MetricSummaries} ) {
	    @{$$hash->{MetricSummaries}}[-1]->{$metricSumElt} = $chars;
	    return $$hash;
	}
    }

    if ( $elt eq "SourceFile" && exists $$hash->{SourceFile} ) {
        if ( not exists $$hash->{SourceFile} ) {
	    $$hash->{SourceFile} = $chars;
	} else {
	    $$hash->{SourceFile} .= $chars;
	}
        return $$hash;
    }
    if ( $elt eq "Type" && exists $$hash->{Type} ) {
        if ( not exists $$hash->{Type} ) {
	    $$hash->{Type} = $chars;
        } else {
	    $$hash->{Type} .= $chars;
	}
	return $$hash;
    }
    if ( $elt eq "Method" && exists $$hash->{Method} ) {
        if ( not exists $$hash->{Type} ) {
	    $$hash->{Method} = $chars;
	} else {
	    $$hash->{Method} .= $chars;
	}
        return $$hash;
    }

    if ( $elt eq "CweId" ) {
	if ( exists $$hash->{CweIds} ) {
	    push @{$$hash->{CweIds}}, $chars;
	} else {
	    @{$$hash->{CweIds}} = ($chars);
	}
	return $$hash;
    }

    if ( $elt eq "Method" && defined $$hash->{Methods}) {
	@{$$hash->{Methods}}[-1]->{name} = $chars;
	return $$hash;
    }

    for my $locElt ( qw/EndColumn EndLine Explanation StartLine SourceFile StartColumn/ ) {
	if ( $elt eq $locElt && defined $$hash->{BugLocations}) {
	    if ( not exists @{$$hash->{BugLocations}}[-1]->{$elt} ) {
		@{$$hash->{BugLocations}}[-1]->{$elt} = $chars;
	    } else {
		@{$$hash->{BugLocations}}[-1]->{$elt} .= $chars;
	    }
	    return $$hash;
	}
    }	
   
    if ( $elt eq "Xpath" && defined $$hash->{InstanceLocation} ) {
        $$hash->{InstanceLocation}->{Xpath} = $chars;
        return $$hash;
    }
    if ( $elt eq "Start" && exists $$hash->{InstanceLocation}->{LineNum} ) {
        $$hash->{InstanceLocation}->{LineNum}->{$elt} = $chars;
        return $$hash;
    }
    if ( $elt eq "End" && exists $$hash->{InstanceLocation}->{LineNum} ) {
        $$hash->{InstanceLocation}->{LineNum}->{$elt} = $chars;
        return $$hash;
    }
 
    return $$hash;
}


##########Default handler needed for optimal runtime of parser##########
sub defaultHandler
{
    #throw everything away
}



1;






