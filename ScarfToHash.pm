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

package ScarfToHash;
use strict;
use XML::Parser;
use Scalar::Util qw[openhandle];
use IO qw[Handle Seekable File Pipe];
##########Initialize Reader##########
sub new
{
    my ($class, $source, $callbacks) = @_;
    my $hashref = {};
    my $self->{hashref} = $hashref;
    $self->{lastElt} = "";
    $self->{source} = $source;
    die "no callbacks detected" if !(defined $callbacks);
    $self->{callbacks} = $callbacks; 
    $self->{parser} = new XML::Parser ();
    $self->{validStart} = 0;
    $self->{validBody} = 0;

    bless $self, $class;

}


##########Initiate parsing of file##########
sub parse
{
    my ( $self ) = @_;
    my $hash = {};
    my $lastElt = "";
    $self->{parser}->setHandlers(
				    "Start", sub { $hash = startHandler( \$hash, \$lastElt, 
					    $self->{callbacks}->{InitialCallback}, \$self->{validStart}, 
					    \$self->{validBody}, $self->{callbacks}->{CallbackData},  @_ ) },
				    "End", sub { $hash = endHandler( \$hash, \$lastElt, 
					    $self->{callbacks}->{BugCallback},  $self->{callbacks}->{MetricCallback},
					    $self->{callbacks}->{BugSummaryCallback}, $self->{callbacks}->{MetricSummaryCallback},
					    \$self->{validBody}, $self->{callbacks}->{FinishCallback}, $self->{callbacks}->{CallbackData}, @_ ) },
				    "Char", sub { $hash = charHandler( \$hash, \$lastElt, @_ ) },
				    "Default" ,\&defaultHandler
				);
    #possibly use xsdValidator to verify scarf
    #$self->{parser}->parsefile($self->{source});
    if (openhandle($self->{source}) or ref $self->{source} eq "IO"){ 
	$self->{parser}->parse($self->{source});
    } elsif ( ref $self->{source} eq "SCALAR" ) {
	my $file;
	open($file, "<", ${$self->{source}}) or die "Can't open source with filename ${$self->{source}}";
	$self->{parser}->parse($file);
    } else {
	$self->{parser}->parse($self->{source});
    }
}


##########Handler for start tags##########
sub startHandler
{
    my ( $hash, $lastElt, $initialcallback, $validStart, $validBody, $data, $parser, $elt, %atts ) = @_;
    if ( $elt eq "AnalyzerReport" ) {
	if (defined $initialcallback){
	    if ( $$validStart ) {
		print ("Invalid SCARF File: Multiple Start Tags");
	    } else {
		$$validStart = 1;
	    }
	    $$hash = { tool_name => $atts{tool_name}, tool_version => $atts{tool_version}, uuid => $atts{uuid} };
	    $initialcallback->( $$hash, $data ) and $parser->finish;
	    $$hash = {};
	}

    } else {
	if ( $$validStart == 0 ) {
	    print ("Invalid SCARF File: No Analyzer Report Start Tag");
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
	    $finishcallback, $data, $parser, $elt ) = @_;    
    if ( $elt eq "BugInstance" && defined $bugcallback ) {
	$bugcallback->( $$hash, $data ) and $parser->finish;
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
	$metriccallback->( $$hash, $data ) and $parser->finish;
        $$hash = {};

    } elsif ( $elt eq "BugSummary" && defined $bugsumcallback ) {
	$bugsumcallback->( $$hash, $data ) and $parser->finish; 
	$$hash = {};

    } elsif ( $elt eq "MetricSummaries" && defined $metricsumcallback ) {
	$metricsumcallback->( $$hash, $data ) and $parser->finish;
        $$hash = {};

    } elsif ( $elt eq "AnalyzerReport") {
	if ( ! $$validBody ) {
	    printf "No BugInstances or Metrics found in file.";
	}
	if ( defined $finishcallback ) {
	    $finishcallback->($data);
	}
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
	    $$hash->{$elt} = $chars;
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
        $$hash->{$elt} = $chars;
        return $$hash;
    }
    if ( $elt eq "Type" && exists $$hash->{Type} ) {
        $$hash->{$elt} = $chars;
        return $$hash;
    }
    if ( $elt eq "Method" && exists $$hash->{Method} ) {
        $$hash->{$elt} = $chars;
        return $$hash;
    }

    if ( $elt eq "CweID" ) {
	if ( exists $$hash->{CweIds} ) {
	    push @{$$hash->{CweIds}}, $chars;
	} else {
	    $$hash->{CweIds} = ($chars);
	}
	return $$hash;
    }

    if ( $elt eq "Method" && defined $$hash->{Methods}) {
	@{$$hash->{Methods}}[-1]->{name} = $chars;
	return $$hash;
    }

    for my $locElt ( qw/EndColumn EndLine Explanation StartLine SourceFile StartColumn/ ) {
	if ( $elt eq $locElt && defined $$hash->{BugLocations}) {
	    @{$$hash->{BugLocations}}[-1]->{$elt} = $chars;
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






