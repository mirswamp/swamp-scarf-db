#! /usr/bin/perl -w

#  Copyright 2016 Pranav Mehendiratta
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


# importing the required libraries
use strict;
use 5.010;
use Getopt::Long;
use Switch;
use DBI;
use DBD::Pg;
use MongoDB;
use ScarfToHash;
use boolean;
use FindBin;
use lib $FindBin::Bin;

############################################## Main ######################################################

sub main
{
    my %options = parseCmdArgs();
    defaults(\%options);
    print "------------------Started--------------------\n";
    my ($sec,$min,$hour) = localtime(time);
    my ($name, $database, $create, $table) = 
	($options{'db-name'}, $options{'db-type'}, $options{'create'}, $options{'table'});
    
    my ($pkg_name, $pkg_ver, $plat) = ($options{'pkg-name'}, $options{'pkg-version'}, $options{'platform'});
    print "$pkg_name, $pkg_ver, $plat\n";
    

    if ($options{'scarf'} =~ /^.*.conf$/) {
	my @values = findScarf($options{'scarf'});
	if ($values[0] == 1) {   
	    my @tableNames = ("assess", "weaknesses", "locations", "methods", "metrics", "functions");
	    
	    # creating the database and tables depending upon the commandline arguments
	    if ($database eq 'postgres' || $database eq 'mariadb' || $database eq 'mysql')  {
	        if  ($create == 1 )  {
		    openDatabase($name, $database);
		    create_tables($name, $database, @tableNames);
		}  elsif  ($table == 1)  {
		    create_tables($name, $database, @tableNames);
		}
	    }

	    # Parsing the files
	    parse_files("$values[1]/$values[2]", $name, $pkg_name, $pkg_ver, $plat, $database,
			$options{'db-host'}, $options{'db-port'}, $options{'db-username'}, 
			$options{'db-password'}); 
	
	    # Deleting the extracted file
	    my $check = unlink "$values[1]/$values[2]";
	    if (!$check)  {
		die "Unable to unlink the file\n";
	    }
	    system("rm -rf $values[1]");
	} else {
	    die;
	}
    } elsif ($options{'scarf'} =~ /^.*.xml$/) {
        # Parsing the files
	parse_files($options{'scarf'}, $name, $pkg_name, $pkg_ver, $plat, $database,
		    $options{'db-host'}, $options{'db-port'}, $options{'db-username'}, 
		    $options{'db-password'}); 
    }
    
    print "Start Time: $hour:$min:$sec\n";
    
    ($sec,$min,$hour) = localtime(time);
    print "End Time: $hour:$min:$sec\n";
    
    print "------------------Finished--------------------\n";
}

########## sub-routine to parse the command line options and to find the type of bug file ##################
sub parseCmdArgs
{
    my %options = (
        'help'          => 0,
        'version'       => 0,
        'create'        => 0,
        'table'         => 0,
        'scarf'		=> undef,
        'db-name'       => undef,
        'db-type'       => undef,
	'pkg-name'	=> undef,
	'pkg-version' 	=> undef,
	'platform'      => undef,
	'db-host'	=> undef,
	'db-port'	=> undef,
	'db-password'	=> undef,
	'db-username'	=> undef
    );

    my @options = (
        "help|h!",
        "version|v!",
        "create|c!",
        "table|t!",
        "scarf|s|i=s",
        "db-type|D|j=s",
        "pkg-name|p|k=s",
        "pkg-version|V|l=s",
        "platform|P|m=s",
        "db-host|H|n=s",
        "db-port|a|o=s",
        "db-username|u|y=s",
        "db-password|q|b=s",
        "db-name|N|g=s",
        );

    Getopt::Long::Configure(qw/require_order no_ignore_case no_auto_abbrev/);
    my $ok = GetOptions(\%options, @options);

    if (!$ok) {
	die "Please enter valid options\n";
    }
    
    # To display the help menu and exit the script
    if ($options{help} == 1)  {
        printHelp();
        exit 0;
    }

    if ($options{version} == 1)  {
        printVersion();
        exit 0;
    }

    # Checking whether appropriate command line arguments are provided
    defined $options{'db-name'} or die 'No database name provided';
    defined $options{'pkg-name'} or die 'No pkg name provided';
    defined $options{'pkg-version'} or die 'No pkg version provided';
    defined $options{'platform'} or die 'No platform name provided';
    defined $options{'scarf'} or die 'Provide either scarf-file or results-conf argument';

    return %options;
}

################################# Subroutine to set default values #########################################
sub defaults
{

    my $options = $_[0];
    if (!defined $options->{'db-type'}) {
        $options->{'db-type'} = "mongodb"
    }
    if (!defined $options->{'db-host'}) {
	$options->{'db-host'} = "localhost";
    } 
    if (!defined $options->{'db-port'}) {
	$options->{'db-port'} = 27017;
    }

}

########################################## Subroutine to print help ##########################################
sub printHelp
{

    my $progname = $0;
    print STDERR <<EOF;

    Usage: $progname [options] <dir>...
    Find scarf file in the given directory name. Parse scarf file and save parsed results in a database.

    options:
    --help                                      -h print this message
    --version                                   -v print version
    --create                                    -c create database
    --table                                     -t create tables in the given database
    --dir=<dir-name>                            -d directory name
    --name=<database-name-to insert-data>       -n database name to insert data
    --database=<name of the database server>    -D Eg. postgres, mongodb, mysql etc.
    --pkg=<pkg-name>                            -p name of the package
    --ver=<pkg-version>       			-V version of the package
    --plat=<platform-name>    			-P name of the platform

EOF
}


#################################### Print version of the program #################################
sub printVersion
{
    my $version = '0.8.0 (July 14, 2016)';
    my $progname = $0;
    print "$progname version $version\n";
}

################################# Finds the scarf file in the given directory ################################
sub findScarf
{
    my $confFile = $_[0];	
    
    # Reading conf file
    my $conf = ReadConfFile($confFile);
    my $archive = $conf->{"parsed-results-archive"};
    my $tarDir = $conf->{"parsed-results-dir"};
    my $file = $conf->{"parsed-results-file"};

    defined $tarDir or (print "$confFile is not appropriate. Can't find the name of directory\n" and return 2);
    defined $archive or (print "$confFile is not appropriate. Can't find the name of archive\n" and return 2);
    defined $file or (print "$confFile is not appropriate. Can't find the name of file\n" and return 2);
   
    my @dir = split("/", $confFile);
    pop @dir;
    my $dirName;
    if (scalar @dir != 0) {
	$dirName = join("/", @dir);
    } else {
	$dirName = '.';
    }
        
    # Extracting the scarf from the given tar file
    system("tar -xzf $dirName/$archive $tarDir/$file") and 
    print "tar -xzf $dirName/$archive $tarDir/$file --verbose\n" and print "Could not untar the file\n" and return 3;
    
    return (1, $tarDir, $file);
}

############## subroutine to parse the necessary file #############################
sub parse_files
{

    # required private variables for the subroutine 
    my $id;
    my $count = 0;
    my %handlers;
    my $dbHandlers;

    # Getting the name of the file and type
    my ($file, $name, $pkg_name, $pkg_ver, $plat, $database, $host, $port, 
	$user, $pass) = @_;
    $handlers{'pkgName'} = $pkg_name;
    $handlers{'pkgVer'} = $pkg_ver;
    $handlers{'plat'} = $plat;
    $handlers{'count'} = $count;
    $handlers{'name'} = $database;

    my $dbh = openDatabase($name, $database, $host, $port, $user, $pass);
    $handlers{'handler'} = $dbh;
    

    if ($database eq 'postgres' || $database eq 'mysql' || $database eq 'mariadb')  {
	$handlers{'weakness'} = $dbh->prepare("INSERT INTO weaknesses VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"); 
	$handlers{'locations'} = $dbh->prepare("INSERT INTO locations VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"); 
	$handlers{'methods'} = $dbh->prepare("INSERT INTO methods VALUES (?, ?, ?, ?, ?);");
	$handlers{'metrics'} = $dbh->prepare("INSERT INTO metrics VALUES (?, ?, ?, ?, ?, ?, ?, ?);");
	$handlers{'functions'} = $dbh->prepare("INSERT INTO functions VALUES (?, ?, ?, ?, ?, ?);");
	$handlers{'counter'} = $count;

	my $callbackHash ={};

	$callbackHash->{'InitialCallback'} = \&init;
	$callbackHash->{'MetricCallback'} = \&metric;
	$callbackHash->{'BugCallback'} = \&bug;
	$callbackHash->{'databaseHandler'} = \%handlers;

	my $test_reader = new ScarfToHash("$file", $callbackHash);
	$test_reader->parse;
	
	$handlers{'handler'}->commit();
	$handlers{'handler'}->disconnect();
    
    }  else  {
	$handlers{'assess'} = $dbh->get_collection("assess")->initialize_ordered_bulk_op;
	$handlers{'assessId'} = MongoDB::OID->new->to_string;
	my $callbackHash ={};

	$callbackHash->{'InitialCallback'} = \&initMongo;
	$callbackHash->{'MetricCallback'} = \&metricMongo;
	$callbackHash->{'BugCallback'} = \&bugMongo;
	$callbackHash->{'databaseHandler'} = \%handlers;

	my $test_reader = new ScarfToHash("$file", $callbackHash);
	$test_reader->parse;
	if ( exists $handlers{'bug'} ) {
	    $handlers{'assess'}->execute;
	}  elsif( exists $handlers{'init'} )  {
	    $handlers{'assess'}->insert({  'assessId'      => $handlers{'assessId'},
	                                   'assessUuid'    => $handlers{'assessUuid'},
					   'pkgShortName'  => $handlers{'pkgName'},
					   'pkgVersion'    => $handlers{'pkgVer'},
					   'toolType'      => $handlers{'toolName'},
					   'toolVersion'   => $handlers{'toolVersion'},
					   'plat'          => $handlers{'plat'},
					});
	    $handlers{'assess'}->execute;
	}
    }
}

#################################### Subroutine to parse and save the values #######################################
sub init
{
    my ($details, $handlers)= @_;
    my ($startTs, $endTs) = ('NULL', 'NULL'); 
    my $insert =  "INSERT INTO assess (assessuuid, pkgshortname, pkgversion, tooltype,
						toolversion, plat, startts, endts) 
		    VALUES (\'$details->{'uuid'}\', \'$handlers->{'pkgName'}\', 
		    \'$handlers->{'pkgVer'}\', \'$details->{'tool_name'}\', \'$details->{'tool_version'}\', 
		    \'$handlers->{'plat'}\', $startTs, $endTs);";
    my $check = $handlers->{'handler'}->do($insert);
    
    if($check < 0){
	die "Unable to insert\n";
    }
    
    $handlers->{'assessId'} = $handlers->{'handler'}->last_insert_id("", "", "assess", "");
    $handlers->{'toolName'} = $details->{'tool_name'};
}

sub metric
{
    my ($metric, $handlers) = @_;
    
    my ($strVal, $startLine, $endLine) = ('NULL', undef, undef);
    $handlers->{'metric'} = 1; 

    my $classname ='NULL';
    if (exists $metric->{'Class'})  {
	$classname = $metric->{'Class'};
    }
    
    my $method_name ='NULL';
    if (exists $metric->{'Method'})  {
	$method_name = $metric->{'Method'};
    }

    if ($metric->{'Value'} =~ /^[0-9]+$/)  {
	my $check = $handlers->{'metrics'}->execute($handlers->{'assessId'}, $metric->{'MetricId'},
		     $metric->{'SourceFile'}, $classname, $method_name, $metric->{'Type'},
		     $strVal, $metric->{'Value'});
    
	if($check < 0){
	    die "Unable to insert\n";
	}
    
    } else  {
	$strVal = undef;
	my $check = $handlers->{'metrics'}->execute($handlers->{'assessId'}, $metric->{'MetricId'},
		     $metric->{'SourceFile'}, $classname, $method_name, $metric->{'Type'},
		     $metric->{'Value'}, $strVal);
	
	if($check < 0){
	    die "Unable to insert\n";
	}
    }

    my $check = $handlers->{'functions'}->execute($handlers->{'assessId'}, $metric->{'SourceFile'},
		 $classname, $method_name, $startLine, $endLine);
    
    if($check < 0){
	die "Unable to insert\n";
    }


}

sub bug
{
    my ($bug, $handlers) = @_;
    my $length = scalar @{$bug->{Methods}}; 
    
    if (exists $bug->{'Methods'} && $length != 0)  {
	
	foreach my $method (@{$bug->{Methods}}) {    	
	    my $check = $handlers->{'methods'}->execute($handlers->{'assessId'}, $bug->{'BugId'},
			$method->{'MethodId'}, $method->{'primary'}, $method->{'name'});
	    if($check < 0){
		die "Unable to insert\n";
	    }	
	}

    } else  {
	my ($methodId, $primary, $name) = (-1, undef, 'NULL');
	my $check = $handlers->{'methods'}->execute($handlers->{'assessId'}, $bug->{'BugId'},
		    $methodId, $primary, $name);
	if($check < 0){
	    die "Unable to insert\n";
	}	
    }

    $length = scalar @{$bug->{BugLocations}}; 
    if (exists $bug->{'BugLocations'} && $length != 0 )  {
	$handlers->{'loc'} = 1;
	my $locations = $bug->{'BugLocations'};
	foreach my $location ( @$locations )  {
	
	    my ($loc_start_col, $loc_end_col, $loc_expla, $loc_start_line
		    , $loc_end_line) = (undef, undef, 'NULL', undef, undef); 
	    
	    if (exists $location->{'StartLine'})  {
		$loc_start_line = $location->{'StartLine'};
	    }

	    if (exists $location->{'EndLine'})  {
		$loc_end_line = $location->{'EndLine'};
	    }
	    
	    if (exists $location->{'EndColumn'})  {
		$loc_end_col = $location->{'EndColumn'};
	    }
	    
	    if (exists $location->{'StartColumn'})  {
		$loc_start_col = $location->{'StartColumn'};
	    }
	    
	    if (exists $location->{'Explanation'})  {
		$loc_expla = $location->{'Explanation'};
	    }
	    
	    my $check = $handlers->{'locations'}->execute($handlers->{'assessId'}, $bug->{'BugId'}, 
			$location->{'LocationId'}, $location->{'primary'}, $location->{'SourceFile'}, 
			$loc_start_line, $loc_end_line, $loc_start_col, $loc_end_col, $loc_expla);
	    
	    if($check < 0){
		die "Unable to insert\n";
	    }
	}
    }
    
    my $bug_code ='NULL';
    if (exists $bug->{'BugCode'})  {
	$bug_code = $bug->{'BugCode'};
    }

    my $bug_group ='NULL';
    if (exists $bug->{'BugGroup'})  {
	$bug_group = $bug->{'BugGroup'};
    }
    
    my $bug_rank ='NULL';
    if (exists $bug->{'BugRank'})  {
	$bug_rank = $bug->{'BugRank'};
    }
    
    my $bug_sev ='NULL';
    if (exists $bug->{'BugSeverity'})  {
	$bug_sev = $bug->{'BugSeverity'};
    }
    
    my $res_sug ='NULL';
    if (exists $bug->{'ResolutionSuggestion'})  {
	$res_sug = $bug->{'ResolutionSuggestion'};
    }
    
    my $classname ='NULL';
    if (exists $bug->{'ClassName'})  {
	$classname = $bug->{'ClassName'};
    }
    
    if (exists $bug->{'CweIds'})  {	
	foreach my $cweid ( $bug->{'CweIds'} )  {  
	    my $check = $handlers->{'weakness'}->execute($handlers->{'assessId'}, $bug->{'BugId'},
			    $bug_code, $bug_group, $bug_rank, $bug_sev, $bug->{'BugMessage'},
			    $res_sug, $classname, $cweid);
	    if($check < 0){
		die "Unable to insert\n";
	    }
	}
    
    } else  {

	    my $cweid = 'NULL';
	    my $check = $handlers->{'weakness'}->execute($handlers->{'assessId'}, $bug->{'BugId'},
			    $bug_code, $bug_group, $bug_rank, $bug_sev, $bug->{'BugMessage'},
			    $res_sug, $classname, $cweid);
	    if($check < 0){
		die "Unable to insert\n";
	    }
    }

    if ($handlers->{'counter'}->() == 100000)  {
	$handlers->{'handler'}->commit();
	$handlers->{'counter'} = counter(0);	
    }
}

sub initMongo
{
    my ($details, $handlers)= @_;
    my ($startTs, $endTs) = ('NULL', 'NULL');
    $handlers->{'init'} = 1;
    $handlers->{'assessUuid'} = $details->{'uuid'};
    $handlers->{'toolName'} = $details->{'tool_name'};
    $handlers->{'toolVersion'}  = $details->{'tool_version'};
}

sub metricMongo
{
    my ($metric, $handlers) = @_;
    $handlers->{'bug'} = 1;
    
    my $classname ='NULL';
    if (exists $metric->{'Class'})  {
        $classname = $metric->{'Class'};
    }

    my $method_name ='NULL';
    if (exists $metric->{'Method'})  {
        $method_name = $metric->{'Method'};
    }
    my $id = $handlers->{'assess'}->insert 
    				    ({  'assessId'     	=> $handlers->{'assessId'},
					'assessUuid'   	=> $handlers->{'assessUuid'},
					'pkgShortName' 	=> $handlers->{'pkgName'},
					'pkgVersion'   	=> $handlers->{'pkgVer'},
					'toolType'     	=> $handlers->{'toolName'},
					'toolVersion'  	=> $handlers->{'toolVersion'},
					'plat'         	=> $handlers->{'plat'}, 
					'Value' 	=> $metric->{'Value'},
					'Type' 		=> $metric->{'Type'},
					'Method' 	=> $method_name, 
					'Class' 	=> $classname,
					'SourceFile' 	=> $metric->{'SourceFile'},
					'MetricId' 	=> int($metric->{'MetricId'})
					});

}

sub bugMongo
{
    my ($bug, $handlers) = @_;
    $handlers->{'bug'} = 1;
    
    my $bug_code ='NULL';
    if (exists $bug->{'BugCode'})  {
        $bug_code = $bug->{'BugCode'};
    }

    my $bug_group ='NULL';
    if (exists $bug->{'BugGroup'})  {
        $bug_group = $bug->{'BugGroup'};
    }

    my $bug_rank ='NULL';
    if (exists $bug->{'BugRank'})  {
	$bug_rank = $bug->{'BugRank'};
    }

    my $bug_sev ='NULL';
    if (exists $bug->{'BugSeverity'})  {
	$bug_sev = $bug->{'BugSeverity'};
    }
    
    my $res_sug ='NULL';
    if (exists $bug->{'ResolutionSuggestion'})  {
	$res_sug = $bug->{'ResolutionSuggestion'};
    }

    my $classname ='NULL';
    if (exists $bug->{'ClassName'})  {
	$classname = $bug->{'ClassName'};
    }
 
    my $length = scalar @{$bug->{Methods}};
    if (exists $bug->{'Methods'} && $length != 0)  {
        foreach my $method (@{$bug->{Methods}}) {
            $method->{'MethodId'} = int($method->{'MethodId'});
	    if ( $method->{'primary'} == 1)  {
                $method->{'primary'} = boolean::true;
            } else  {
                $method->{'primary'} = boolean::false;	
	    }
	}
    }

    $length = scalar @{$bug->{BugLocations}};
    if (exists $bug->{'BugLocations'} && $length != 0)  {
        foreach my $location (@{$bug->{BugLocations}}) {
            $location->{'LocationId'} = int($location->{'LocationId'});
            
	    if ( $location->{'primary'} == 1)  {
                $location->{'primary'} = boolean::true;
            } else  {
                $location->{'primary'} = boolean::false;	
	    }
    
	    if (exists $location->{'StartLine'})  {
		$location->{'StartLine'} = int($location->{'StartLine'});
	    }
    
	    if (exists $location->{'EndLine'})  {
	        $location->{'EndLine'} = int($location->{'EndLine'});
	    }

	    if (exists $location->{'EndColumn'})  {
	        $location->{'EndColumn'} = int($location->{'EndColumn'});
	    }

	    if (exists $location->{'StartColumn'})  {
		$location->{'StartColumn'} = int($location->{'StartColumn'});
	    }	
	}
    }

    my $id = $handlers->{'assess'}->insert 
    				    ({  'assessId'     	=> $handlers->{'assessId'},
					'assessUuid'   	=> $handlers->{'assessUuid'},
					'pkgShortName' 	=> $handlers->{'pkgName'},
					'pkgVersion'   	=> $handlers->{'pkgVer'},
					'toolType'     	=> $handlers->{'toolName'},
					'toolVersion'  	=> $handlers->{'toolVersion'},
					'plat'         	=> $handlers->{'plat'},
					'BugMessage'   	=> $bug->{'BugMessage'},
					'BugGroup'     	=> $bug_group,
					'Location'     	=> $bug->{'BugLocations'},
					'Methods'      	=> $bug->{'Methods'},
					'bugId'         => int($bug->{'BugId'}),
					'bugCode'          => $bug_code,
					'bugRank'          => $bug_rank,
					'bugSeverity'      => $bug_sev,
					'bugResolutionMsg' => $res_sug,
					'classname'        => $classname,		
					'bugCwe'           => $bug->{'CweIds'},
					});

}

########################################## Opening the database #############################################
sub openDatabase
{
    
    my ($name, $type, $host, $port, $user, $pass) = @_;

    if (lc($type) eq 'postgres')  {
        print "connected with postgres\n";
	my $driver   = "Pg";
        my $dsn = "DBI:$driver:dbname=$name;host=$host;port=$port;";
        my $dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1, AutoCommit => 0, async => 1, fsync => 0 })
                       or die $DBI::errstr;

	#Returning the database handle
	return $dbh;
    }
    elsif (lc($type) eq 'mongodb')  {

        print "connected with mongodb\n";
	my $client;
        if (defined $user and defined $pass) {
	    $client = MongoDB::MongoClient->new(host => $host, port => $port
					, username => $user, password => $pass); 
	} else  {
	    $client = MongoDB::MongoClient->new(host => $host, port => $port);
	}
	my $dbh = $client->get_database("$name");

	# Returning the database handle
	return $dbh;
    
    } else  {
    
	my $driver = "mysql";
	my $database = $_[0];
	my $dsn = "DBI:$driver:database=$name;host=$host;port=$port;";
	
	if (lc($type) eq 'mysql')  {
	    print "connected with mysql\n";
	
	}  else  {
	    print "connected with mariadb\n";
	}
	
	my $dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1, AutoCommit => 0, async => 1 }) 
	    or die $DBI::errstr;
    
	# Returning the database handle
	return $dbh;
    }
}

############################# Method to create tables in a specific database ####################################
sub create_tables
{

    # Required private variable for the subroutine
    my ($db_name , $type, @table_names) = @_;
    my $dbh = openDatabase($db_name, $type);
    my $counter = 0;
    my $create;
    my $check;
    my $primaryKey = "BIGSERIAL PRIMARY KEY";

    if (lc($type) eq 'mariadb' || lc($type) eq 'mysql')  {
	$primaryKey = "INT PRIMARY KEY AUTO_INCREMENT";
    }
    
    foreach my $table ( @table_names ) {	
	switch ( $table ) {
	    case 'assess' {
		$create = qq(CREATE TABLE $table_names[$counter]
		(assessId		$primaryKey,
		assessUuid		text			NOT NULL,
		pkgShortName		text			NOT NULL,
		pkgVersion		text,
		toolType		text			NOT NULL,
		toolVersion		text,
		plat			text			NOT NULL,
		startTs			real,
		endTs            	real
		););
	    }

	    case 'weaknesses' {
		$create = qq(CREATE TABLE $table_names[$counter]
		(assessId		integer			NOT NULL,
		bugId			integer			NOT NULL,
		bugCode			text,
		bugGroup		text,
		bugRank			text,
		bugSeverity		text,
		bugMessage		text,
		bugResolutionMsg	text,
		classname		text,
		bugCwe			text,
		PRIMARY KEY (assessId, bugId)	
		););
	    }

	    case 'locations' {
		$create = qq(CREATE TABLE $table_names[$counter]
		(assessId		integer			NOT NULL,
		bugId			integer			NOT NULL,
		locId			integer			NOT NULL,
		isPrimary		boolean			NOT NULL,
		sourceFile		text			NOT NULL,
		startLine		integer,
		endLine			integer,
		startCol		integer,
		endCol			integer,
		explanation		text,
		PRIMARY KEY (assessId, bugId, locId)	
		););
	    }
	
	    case 'methods' {
		$create = qq(CREATE TABLE $table_names[$counter]
		(assessId		integer			NOT NULL,
		bugId			integer			NOT NULL,
		methodId		integer,
		isPrimary        	boolean,
		methodName       	text,
		PRIMARY KEY (assessId, bugId, methodId)	
		););
	    }

	    case 'metrics' {
		$create = qq(CREATE TABLE $table_names[$counter]
		(assessId		integer			NOT NULL,
		metricId		integer,
		sourceFile		text,
		class			text,
		method			text,
		type			text,
		strVal			text,
		numVal			real,
		PRIMARY KEY (assessId, metricId)	
		););
	    }

	    case 'functions' {
		$create = qq(CREATE TABLE $table_names[$counter]
		(assessId		integer			NOT NULL,
		sourceFile		text,
		class			text,
		method			text,
		startLine		integer,
		endLine			integer
		););
	    }
    }

    # Creating the table with above fields		
    $check = $dbh->do($create);
	   
 
    # Checking whether the table is successfully created(works for each iteration)
    if ($check < 0)  {
    	print "$DBI::errstr\n";
    }
    $counter++;
}
    $dbh->commit();
}

###################################### reading the conf file #####################################################

# HasValue - return true if string is defined and non-empty
#
sub HasValue
{
    my ($s) = @_;
    return defined $s && $s ne '';
}

sub ReadConfFile
{
    my ($filename, $required) = @_;

    my $lineNum = 0;
    my $colNum = 0;
    my $linesToRead = 0;
    my $charsToRead = 0;
    my %h;
    $h{'#filenameofconffile'} = $filename;

    open my $confFile, "<$filename" or die "Open configuration file '$filename' failed: $!";
    my ($line, $k, $kLine, $err);
    while (1)  {
	if (!defined $line)  {
	    $line = <$confFile>;
	    last unless defined $line;
	    ++$lineNum;
	    $colNum = 1;
	}

	if ($linesToRead > 0)  {
	    --$linesToRead;
	    chomp $line if $linesToRead == 0;
	    $h{$k} .= $line;
	}  elsif ($charsToRead > 0)  {
	    my $v = substr($line, 0, $charsToRead, '');
	    $colNum = length $v;
	    $charsToRead -= $colNum;
	    $h{$k} .= $v;
	    redo if length $line > 0;
	}  elsif ($line !~ /^\s*(#|$)/)  {
	    # line is not blank or a comment (first non-whitespace is a '#')
	    if ($line =~ /^\s*(.*?)\s*(?::([^:]*?))?=(\s*(.*?)\s*)$/)  {
		my ($u, $wholeV, $v) = ($2, $3, $4);
		$k = $1;
		$kLine = $lineNum;
		if ($k eq '')  {
		    chomp $line;
		    $err = "missing key, line is '$line'";
		    last;
		}
		if (!defined $u)  {
		    # normal 'k = v' line
		    $h{$k} = $v;
		}  else  {
		    # 'k :<COUNT><UNIT>= v' line
		    $u = '1L' if $u eq '';
		    if ($u =~ /^(\d+)L$/i)  {
			$linesToRead = $1;
		    }  elsif ($u =~ /^(\d+)C$/i)  {
			$charsToRead = $1;
			$colNum = length($line) - length($wholeV);
		    }  else  {
			$err = "unknown units ':$u='";
			last;
		    }
		    $h{$k} = '';
		    $line = $wholeV;
		    redo;
		}
	    }  else  {
		chomp $line;
		$err = "bad line (no '='), line is '$line'";
		last;
	    }
	}
	undef $line;
    }
    close $confFile or defined $err or die "Close configuration file '$filename' failed: $!";

    if (defined $err)  {
	my $loc = "line $lineNum";
	$loc .= " column $colNum" unless $colNum == 1;
	die "Configuration file '$filename' $loc $err";
    }

    if ($linesToRead > 0)  {
	die "Configuration file '$filename' missing $linesToRead lines for key '$k' at line $kLine";
    }

    if ($charsToRead > 0)  {
	die "Configuration file '$filename' missing $charsToRead characters for key '$k' at line $kLine";
    }

    if (defined $required)  {
	my @missing = grep { !HasValue $h{$_}; } @$required;
	if (@missing)  {
	    die "Configuration file '$filename' missing required keys: " . join(", ", @missing);
	}
    }

    return \%h;
}

main();
