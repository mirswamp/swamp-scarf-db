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
use FindBin;
use lib $FindBin::Bin;
use ScarfToHash;
# required for SQL databases
use DBI;
# required for MongoDB
use boolean;
use MongoDB;

############################################## Main ######################################################

sub main
{
    my %options = ProcessOptions();
    my ($name, $database) = 
	($options{db_name}, $options{db_type});
    
    my ($pkg_name, $pkg_ver, $plat) = 
	($options{pkg_name}, $options{pkg_version}, $options{platform});
   
    if ($options{scarf} =~ /^.*.conf$/) {
	my ($retVal, %names) = findScarf($options{scarf});
	if ($retVal == 1) {   
	    my @tableNames = ("assess", "weaknesses", "locations", "methods", "metrics", "functions");
	    
	    # creating the database and tables depending upon the commandline arguments
	    if ($database eq 'postgres' || $database eq 'mariadb' || $database eq 'mysql'
		   || $database eq 'sqlite')  {
		ProcessTableOptions($options{delete_tables}, $options{create_tables}, $name, 
				    $database, $options{db_host}, $options{db_port}, 
				    $options{db_username}, $options{db_password}, @tableNames);
	    }

	    # Parsing the files
	    parse_files($name, $pkg_name, $pkg_ver, $plat, $database,
			$options{db_host}, $options{db_port}, $options{db_username}, 
			$options{db_password}, $options{db_commits}, \%names); 
	
	} else {
	    print "Please fix the above errors\n";
	    exit 1;
	}
    } elsif ($options{scarf} =~ /^.*.xml$/) {
        # Parsing the files
	parse_files($name, $pkg_name, $pkg_ver, $plat, $database,
		$options{db_host}, $options{db_port}, $options{db_username}, 
		$options{db_password}, $options{db_commits}, \$options{scarf}); 
    }
}

###################################### Process command line options #######################################
sub ProcessOptions
{
    my %optionDefaults = (
	help            => 0,
	version         => 0,
	authenticate   	=> undef,
	db_params	=> undef,
	db_type		=> 'mongodb',
	db_host		=> 'localhost',
	create_tables	=> undef,
	delete_tables	=> undef,
	db_port		=> undef,
	db_commits	=> undef,
	db_name		=> undef,
	scarf		=> undef,
	pkg_name	=> undef,
	pkg_version	=> undef,
	platform	=> undef,
	just_print	=> undef,
	db_username	=> undef,
	db_password	=> undef,
	);

    # for options that contain a '-', make the first value be the
    # same string with '-' changed to '_', so quoting is not required
    # to access the key in the hash $option{input_file} instead of
    # $option{'input-file'}
    
    my @options = (
	"help|h!",
	"version|v!",
	"authenticate|conf_file|a=s",
	"db_params|conf_file2|c=s",
	"db_type|type|t=s",
	"db_host|host|H=s",
	"create_tables|T!",
	"delete_tables|d!",
	"db_port|port|p=s",
	"db_commits|commits|C=s",
	"db_name|database|D=s",
	"scarf|S=s",
	"pkg_name|name|n=s",
	"pkg_version|ver|V=s",
	"platform|P=s",
	"just_print|j!",
	"db_username|u=s",
	"db_password|U=s",
    );

    
    Getopt::Long::Configure(qw/require_order no_ignore_case no_auto_abbrev/);
    my %getoptOptions;
    my $ok = GetOptions(\%getoptOptions, @options);

    # Checking whether appropriate command line options were given
    my @confFileOptions;
    
    (defined $getoptOptions{db_params} and push @confFileOptions, 'db_params')
	    or die "No database parameters file provided\n";
    defined $getoptOptions{authenticate} and push @confFileOptions, 'authenticate'; 
    
    my %options = %optionDefaults;
    my %optSet;

    while (my ($k, $v) = each %getoptOptions)  {
	$options{$k} = $v;
        $optSet{$k} = 1;
    }

    my @errs;

    if ($ok)  {
        foreach my $opt (@confFileOptions)  {
            if (exists $options{$opt})  {
		my $fn = $options{$opt};
		if ($optSet{$opt} || -e $fn)  {
		    if (-f $fn)  {
			my $h = ReadConfFile($fn, undef, \@options);
			while (my ($k, $v) = each %$h)  {
			    next if $k =~ /^#/;
			    $options{$k} = $v;
			    $optSet{$k} = 1;
			}			
		    }  else  {
			push @errs, "option '$opt' option file '$fn' not found";
		    }
		}
	    }
	}
	while (my ($k, $v) = each %getoptOptions)  {
	    $options{$k} = $v;
	    $optSet{$k} = 1;
	}
    }

    if (!$ok || $options{help})  {
	printHelp(\%optionDefaults);
	exit !$ok;
    }

    if ($ok && $options{version})  {
	printVersion();
	exit 0;
    }

    # printing out the execution commands
    if (defined $options{just_print})  {
	justPrint();
	exit 0;
    }
    
    # Setting the defaults 
    defaults(\%options);
    
    # Checking whether appropriate options were present in the configuration files
    my @errors;
    $options{db_type} = lc($options{db_type});
    my %types = (
	'postgres'	=> 0, 
	'mongodb'	=> 0, 
	'mariadb'	=> 0, 
	'sqlite'	=> 0,
	'mysql'		=> 0,
    );
    
    if (exists($types{$options{db_type}})) {
	if ($options{db_type} eq 'postgres' || $options{db_type} eq 'mysql'
		|| $options{db_type} eq 'mariadb') {
	    if (!defined $getoptOptions{authenticate}) {
		push @errors, "No authenticate.conf file provided\n";	
	    }
	}
    } else {
	push @errors, "Database type \'$options{db_type}\' is incorrect\n";
    }
    
    if (!defined $options{db_name})  {
	push @errors, "No database name provided\n";
    }
    
    if (!defined $options{pkg_name})  {
	push @errors, "No package name provided\n";
    } 
    
    if (!defined $options{pkg_version})  {
	push @errors, "No package version provided\n";
    }
    
    if (!defined $options{platform})  {
	push @errors, "No platform name provided\n";
    }
    
    if (!defined $options{scarf})  {
	push @errors, "No scarf file or results conf file provided\n";
    }

    # Checking the errors array for any errors
    if (@errors) {
	print @errors;
	exit(1);
    }

    return %options;
}

################################# Subroutine to set default values #########################################
sub defaults
{

    my ($options) = @_;
    my %dbPorts = (
	postgres	=> 5432,
	mariadb		=> 3306,
	mysql		=> 3306,
	mongodb		=> 27017,
    );

    my $dbType = $options->{db_type};
    defined $options->{db_port} or $options->{db_port} = $dbPorts{$dbType};
    
    my %size = (
	postgres	=> 'INF',
	mariadb		=> 'INF',
	mysql		=> 'INF',
	mongodb		=> 1500,
	sqlite		=> 'INF',
    );
   
    defined $options->{db_commits} or ($options->{db_commits} = $size{$dbType});
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
    --authenticate=<conf file>		      	-a conf file containing the username 
						    and password for database
    --db_params=<database params>  		-c conf file containing the database parameters
    --db_type					-t Database type - It can be any of the databases supported, 
						    default: mongodb,
    --db_host					-H Hostname of the DBMS server, 
						    default: localhost,
    --create_tables				-T Creates tables for SQL databases,
    --delete_tables				-d Deletes tables for SQL databases,
    --db_port					-p Port on which the DBMS server listens on. 
						    default: 27017 (MongoDB), 5432 (PostgreSQL) 
								or 3306 (MySQL, MariaDB),
    --db_commits				-C Number of Bugs/Metric instances to commit at once.
						    default: INF(infinity) for SQL databases
							     1500 for MongoDB,
    --db_name					-D Name of the database in which you want to save scarf results to. 
						    For eg: test, scarf, swamp. 
						    MongoDB and SQLite creates the database if it does not exist,
    --scarf					-S  Path to the SCARF results XML (parsed_results.xml) file 
							or parsed_results.conf file,
    --pkg_name					-n Name of the software package that was assessed,
    --pkg_version				-V Version of the software package that was assessed,
    --platform					-P Platform the assessment was run on,
    --just_print				-j Just prints out the create, insert, deletion statements,
    --db_username 				-u Username for DBMS
    --db_password				-U Password for DBMS

EOF
}


#################################### Print version of the program #################################
sub printVersion
{
    my $version = '0.9.0 (July 19, 2016)';
    my $progname = $0;
    print "$progname version $version\n";
}

#################################### Printing the database commands #################################
sub justPrint
{
    my ($paramter) = @_;
    my %createStatements = SQLStatements('create');
    my %insertStatements = SQLStatements('insert');
    my %metricStatement = MongoDBStatements('metric');
    my %bugStatement = MongoDBStatements('bug');
    my ($deleteStatement, @tableNames) = SQLStatements('delete');
    
    print "\n\t\t\t-- SQL STATEMENTS --\n";
    print "\n\t\t\t- INSERT STATEMENTS -\n\n";
    while (my ($k, $v) = each %insertStatements) {
	print "$v\n";
    }
    print "\n\t\t\t- CREATE STATEMENTS -\n\n";
    while (my ($k, $v) = each %createStatements) {
	print "$v\n";
    }
    print "\n\t\t\t- DELETE STATEMENTS -\n\n";
    foreach my $table (@tableNames) {
	print "$deleteStatement $table;\n";
    }

    print "\n\t\t\t-- MongoDB STATEMENTS --\n";
    print "\n\t\t\t- BUGS STATEMENT -\n\n";
    while (my ($k, $v) = each %bugStatement) {
	print "$k => $v\n";
    }
    print "\n\t\t\t- METRIC STATEMENT -\n\n";
    while (my ($k, $v) = each %metricStatement) {
	print "$k => $v\n";
    }
    print "\n";
}


#################################### SQL database commands #################################
sub SQLStatements
{
	my ($parameter) = @_; 
	my %insertStatements = (
	    assess	=>  "INSERT INTO assess (assessuuid, pkgshortname, pkgversion, tooltype,
		toolversion, plat) VALUES (?, ?, ?, ?, ?, ?);", 
	    weaknesses	=> "INSERT INTO weaknesses VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
	    locations	=> "INSERT INTO locations VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", 
	    methods	=> "INSERT INTO methods VALUES (?, ?, ?, ?, ?);",
	    metrics	=> "INSERT INTO metrics VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
	    functions	=> "INSERT INTO functions VALUES (?, ?, ?, ?, ?, ?);",
	);

	my %createStatements = (
	    assess	=> qq(CREATE TABLE assess ( 
			    assessId		?,
			    assessUuid		text		NOT NULL,
			    pkgShortName	text		NOT NULL,
			    pkgVersion		text,
			    toolType		text		NOT NULL,
			    toolVersion		text,
			    plat		text		NOT NULL
			    );),

	    weaknesses	=> qq(CREATE TABLE weaknesses (
			    assessId		integer		NOT NULL,
			    bugId		integer		NOT NULL,
			    bugCode		text,
			    bugGroup		text,
			    bugRank		text,
			    bugSeverity		text,
			    bugMessage		text,
			    bugResolutionMsg	text,
			    classname		text,
			    bugCwe		text,
			    PRIMARY KEY (assessId, bugId)	
			    );),

	    locations	=> qq(CREATE TABLE locations (
			    assessId		integer		NOT NULL,
			    bugId		integer		NOT NULL,
			    locId		integer		NOT NULL,
			    isPrimary		boolean		NOT NULL,
			    sourceFile		text		NOT NULL,
			    startLine		integer,
			    endLine		integer,
			    startCol		integer,
			    endCol		integer,
			    explanation		text,
			    PRIMARY KEY (assessId, bugId, locId)	
			    );),
	
	    methods	=> qq(CREATE TABLE methods (
			    assessId		integer		NOT NULL,
			    bugId		integer		NOT NULL,
			    methodId		integer,
			    isPrimary        	boolean,
			    methodName       	text,
			    PRIMARY KEY (assessId, bugId, methodId)	
			    );),

	    metrics	=> qq(CREATE TABLE metrics (
			    assessId		integer		NOT NULL,
			    metricId		integer,
			    sourceFile		text,
			    class		text,
			    method		text,
			    type		text,
			    strVal		text,
			    numVal		real,
			    PRIMARY KEY (assessId, metricId)	
			    );),

	    functions	=> qq(CREATE TABLE functions ( 
			    assessId		integer		NOT NULL,
			    sourceFile		text,
			    class		text,
			    method		text,
			    startLine		integer,
			    endLine		integer
			    );),
	);

	my @tableNames = ("assess", "weaknesses", "locations", "methods", "metrics", "functions");
	
	if ($parameter eq 'create')  {
	    return (%createStatements);
	} elsif ($parameter eq 'insert')  {
	    return (%insertStatements);
	} elsif ($parameter eq 'delete') {
	    return ("DROP TABLE ", @tableNames);
	} 
}

######################################## Inserting MongoDB commands ##################################
sub MongoDBStatements
{
    my ($parameter) = @_;
    my %metricInstance = (  assessId     	=> '?', 
			    assessUuid   	=> '?', 
			    pkgShortName 	=> '?', 
			    pkgVersion   	=> '?',
			    toolType     	=> '?',
			    toolVersion  	=> '?',
			    plat         	=> '?',
			    Value 		=> '?',
			    Type 		=> '?',
			    Method 		=> '?',
			    Class 		=> '?',
			    SourceFile	 	=> '?',
			    MetricId 		=> '?',
			);

    my %bugInstance = ( assessId     	=> '?',
			assessUuid   	=> '?',
			pkgShortName 	=> '?',
			pkgVersion   	=> '?',
			toolType     	=> '?',
			toolVersion  	=> '?',
			plat         	=> '?',
			BugMessage   	=> '?',
			BugGroup     	=> '?',
			Location     	=> '?',
			Methods      	=> '?',
			BugId 	        => '?',
			BugCode          => '?',
			BugRank          => '?',
			BugSeverity      => '?',
			BugResolutionMsg => '?',
			classname        => '?',	
			BugCwe           => '?',
			);

    if ($parameter eq 'metric') {
	return %metricInstance;
    } elsif ($parameter eq 'bug') {
	return %bugInstance;
    }

}

################################# Finds the scarf file in the given directory ################################
sub findScarf
{
    my ($confFile) = @_;	

    # Reading conf file
    my $conf = ReadConfFile($confFile);
    my $archive = $conf->{"parsed-results-archive"};
    my $tarDir = $conf->{"parsed-results-dir"};
    my $file = $conf->{"parsed-results-file"};

    my @errors;
    
    if (!defined $tarDir)  {
	push @errors, "$confFile is not appropriate. Can't find the name of directory\n";
    }

    if (!defined $archive)  { 
	push @errors, "$confFile is not appropriate. Can't find the name of archive\n";
    }
    
    if (!defined $file)  { 
	push @errors, "$confFile is not appropriate. Can't find the name of file\n";
    }

    # Checking the errors array for any errors
    if (@errors) {
	print @errors;
	return 2;
    }

    my $confFileDir;

    # Finding the directory name
    if ($confFile =~ /(.*)\/.*/) {
	$confFileDir = $1;
    } else {
	$confFileDir = '.';
    }
    
    # Extracting the scarf from the given tar file
    my @cmd = ("tar", "-xzf", "$confFileDir/$archive", "$tarDir/$file", "-O"); 
    my %names = (
	dir	=> $confFileDir,
	archive => $archive,
	tarDir  => $tarDir,
	file	=> $file,
    );
    return (1, %names);
}

############## subroutine to parse the necessary file #############################
sub parse_files
{
    # Getting the name of the file and type
    my ($name, $pkg_name, $pkg_ver, $plat, $database, $host, $port, 
	$user, $pass, $commits, $names) = @_;

    # required private variables for the subroutine 
    my $id;
    my %data = (
	pkgName		=> $pkg_name,
	pkgVer 		=> $pkg_ver,
	plat		=> $plat,
	db_count	=> 0,
	name		=> $database,
	db_commits	=> $commits,
    );

    my $dbh = openDatabase($name, $database, $host, $port, $user, $pass);
    $data{db} = $dbh;
    
    my $scarf;

    # untaring the file to a handler
    if (ref($names) eq "HASH") {
	my @cmd = ("tar", "-xzf", "$names->{dir}/$names->{archive}", 
    		    "$names->{tarDir}/$names->{file}", "-O"); 
	open $scarf, '-|', @cmd;
    } else {
	$scarf = $names;
    }

    my %callbacks;

    if ($database ne 'mongodb')  {
	# Getting the SQL statements
	my %insertStatements = SQLStatements('insert');
	while (my ($k, $v) = each (%insertStatements)) {
	    if ($k ne 'assess') {
		$data{$k} = $dbh->prepare($v); 
	    }
	}
	
	%callbacks = (
	    InitialCallback 	=> \&init,
	    MetricCallback 	=> \&metric,
	    BugCallback 	=> \&bug,
	    FinishCallback	=> \&finish,
	    CallbackData 	=> \%data,
	);
    }  else  {
	$data{assess} = $dbh->get_collection("assess");
	$data{assessId} = MongoDB::OID->new->to_string;

	%callbacks = (
	    InitialCallback 	=> \&initMongo,
	    MetricCallback 	=> \&metricMongo,
	    BugCallback 	=> \&bugMongo,
	    FinishCallback	=> \&finish,
	    CallbackData 	=> \%data,
	);
    }
    
    # Parsing the file and uploading the data
    my $test_reader = new ScarfToHash($scarf, \%callbacks);
    $test_reader->parse;
	
    if (ref($names) eq "HASH") {
	close $scarf;
    }
}

#################################### Subroutine to parse and save the values #######################################
sub init
{
    my ($details, $data) = @_;
    
    # Getting the SQL statements
    my %insertStatements = SQLStatements('insert');
    my $insert = $insertStatements{assess};
    if ($insert =~ /^(.*?)\(\?/s) {
	$insert =  $1 . "(\'$details->{uuid}\', \'$data->{pkgName}\', 
			\'$data->{pkgVer}\', \'$details->{tool_name}\', 
			\'$details->{tool_version}\', \'$data->{plat}\');" ; 
    }

    my $check = $data->{db}->do($insert);
    if ($check < 0)  {
	die "Unable to insert\n";
    }
    
    $data->{assessId} = $data->{db}->last_insert_id("", "", "assess", "");
    $data->{toolName} = $details->{tool_name};
    $data->{SQL} = 'SQL';
    return 0;
}

sub metric
{
    my ($metric, $data) = @_;
    
    my ($strVal, $startLine, $endLine) = ('NULL', undef, undef);

    my $classname = 'NULL';
    if (exists $metric->{Class})  {
	$classname = $metric->{Class};
    }
    
    my $method_name = 'NULL';
    if (exists $metric->{Method})  {
	$method_name = $metric->{Method};
    }

    if ($metric->{Value} =~ /^[0-9]+$/)  {
	my $check = $data->{metrics}->execute($data->{assessId}, $metric->{MetricId},
		     $metric->{SourceFile}, $classname, $method_name, $metric->{Type},
		     $strVal, $metric->{Value});
    
	if ($check < 0)  {
	    die "Unable to insert\n";
	}
    
    } else  {
	$strVal = undef;
	my $check = $data->{metrics}->execute($data->{assessId}, $metric->{MetricId},
		     $metric->{SourceFile}, $classname, $method_name, $metric->{Type},
		     $metric->{Value}, $strVal);
	
	if ($check < 0)  {
	    die "Unable to insert\n";
	}
    }

    my $check = $data->{functions}->execute($data->{assessId}, $metric->{SourceFile},
		 $classname, $method_name, $startLine, $endLine);
    
    if ($check < 0)  {
	die "Unable to insert\n";
    }
    
    $data->{db_count}++;
    if ($data->{db_commits} != 'INF' && $data->{db_commits} == $data->{db_count})  {
	$data->{db}->commit();
	$data->{db_count} = 0;	
    }
    return 0;
}

sub bug
{
    my ($bug, $data) = @_;
    my $length = scalar @{$bug->{Methods}}; 
    
    if (exists $bug->{Methods} && $length != 0)  {
	
	foreach my $method (@{$bug->{Methods}}) {    	
	    my $check = $data->{methods}->execute($data->{assessId}, $bug->{BugId},
			$method->{MethodId}, $method->{primary}, $method->{name});
	    if ($check < 0)  {
		die "Unable to insert\n";
	    }	
	}

    } else  {
	my ($methodId, $primary, $name) = (-1, undef, 'NULL');
	my $check = $data->{methods}->execute($data->{assessId}, $bug->{BugId},
		    $methodId, $primary, $name);
	if ($check < 0)  {
	    die "Unable to insert\n";
	}	
    }

    $length = scalar @{$bug->{BugLocations}}; 
    if (exists $bug->{BugLocations} && $length != 0 )  {
	$data->{loc} = 1;
	my $locations = $bug->{BugLocations};
	foreach my $location ( @$locations )  {
	
	    my ($loc_start_col, $loc_end_col, $loc_expla, $loc_start_line
		    , $loc_end_line) = (undef, undef, 'NULL', undef, undef); 
	    
	    if (exists $location->{StartLine})  {
		$loc_start_line = $location->{StartLine};
	    }

	    if (exists $location->{EndLine})  {
		$loc_end_line = $location->{EndLine};
	    }
	    
	    if (exists $location->{EndColumn})  {
		$loc_end_col = $location->{EndColumn};
	    }
	    
	    if (exists $location->{StartColumn})  {
		$loc_start_col = $location->{StartColumn};
	    }
	    
	    if (exists $location->{Explanation})  {
		$loc_expla = $location->{Explanation};
	    }
	    
	    my $check = $data->{locations}->execute($data->{assessId}, $bug->{BugId}, 
			$location->{LocationId}, $location->{primary}, $location->{SourceFile}, 
			$loc_start_line, $loc_end_line, $loc_start_col, $loc_end_col, $loc_expla);
	    
	    if ($check < 0)  {
		die "Unable to insert\n";
	    }
	}
    }
    
    my $bug_code = 'NULL';
    if (exists $bug->{BugCode})  {
	$bug_code = $bug->{BugCode};
    }

    my $bug_group = 'NULL';
    if (exists $bug->{BugGroup})  {
	$bug_group = $bug->{BugGroup};
    }
    
    my $bug_rank = 'NULL';
    if (exists $bug->{BugRank})  {
	$bug_rank = $bug->{BugRank};
    }
    
    my $bug_sev = 'NULL';
    if (exists $bug->{BugSeverity})  {
	$bug_sev = $bug->{BugSeverity};
    }
    
    my $res_sug = 'NULL';
    if (exists $bug->{ResolutionSuggestion})  {
	$res_sug = $bug->{ResolutionSuggestion};
    }
    
    my $classname = 'NULL';
    if (exists $bug->{ClassName})  {
	$classname = $bug->{ClassName};
    }
    
    if (exists $bug->{CweIds})  {	
	foreach my $cweid ( $bug->{CweIds} )  {  
	    my $check = $data->{weaknesses}->execute($data->{assessId}, $bug->{BugId},
			    $bug_code, $bug_group, $bug_rank, $bug_sev, $bug->{BugMessage},
			    $res_sug, $classname, $cweid);
	    if ($check < 0)  {
		die "Unable to insert\n";
	    }
	}
    
    } else  {

	    my $cweid = 'NULL';
	    my $check = $data->{weaknesses}->execute($data->{assessId}, $bug->{BugId},
			    $bug_code, $bug_group, $bug_rank, $bug_sev, $bug->{BugMessage},
			    $res_sug, $classname, $cweid);
	    if ($check < 0)  {
		die "Unable to insert\n";
	    }
    }
    
    $data->{db_count}++;
    if ($data->{db_commits} != 'INF' && $data->{db_commits} == $data->{db_count})  {
	$data->{db}->commit();
	$data->{db_count} = 0;	
    }
    return 0;
}

sub initMongo
{
    my ($details, $data) = @_;
    $data->{init} = 1;
    $data->{assessUuid} = $details->{uuid};
    $data->{toolName} = $details->{tool_name};
    $data->{toolVersion}  = $details->{tool_version};
    $data->{NOSQL} = 'NOSQL';
    return 0;
}

sub metricMongo
{
    my ($metric, $data) = @_;
    
    my $classname = 'NULL';
    if (exists $metric->{Class})  {
        $classname = $metric->{Class};
    }

    my $method_name = 'NULL';
    if (exists $metric->{Method})  {
        $method_name = $metric->{Method};
    }

    my %metricInstance = (  assessId     	=> $data->{assessId},
			    assessUuid   	=> $data->{assessUuid},
			    pkgShortName 	=> $data->{pkgName},
			    pkgVersion   	=> $data->{pkgVer},
			    toolType     	=> $data->{toolName},
			    toolVersion  	=> $data->{toolVersion},
			    plat         	=> $data->{plat}, 
			    Value 		=> $metric->{Value},
			    Type 		=> $metric->{Type},
			    Method 		=> $method_name, 
			    Class 		=> $classname,
			    SourceFile	 	=> $metric->{SourceFile},
			    MetricId 		=> int($metric->{MetricId})
			);

    push @{$data->{scarf}}, \%metricInstance;
    
    $data->{db_count}++;
    if ($data->{db_commits} != 'INF' && $data->{db_commits} == $data->{db_count}) {
	my $res = $data->{assess}->insert_many(\@{$data->{scarf}});
	$data->{db_count} = 0;
	delete $data->{scarf};
    }
    return 0;
}

sub bugMongo
{
    my ($bug, $data) = @_;
    
    my $bug_code = 'NULL';
    if (exists $bug->{BugCode})  {
        $bug_code = $bug->{BugCode};
    }

    my $bug_group = 'NULL';
    if (exists $bug->{BugGroup})  {
        $bug_group = $bug->{BugGroup};
    }

    my $bug_rank = 'NULL';
    if (exists $bug->{BugRank})  {
	$bug_rank = $bug->{BugRank};
    }

    my $bug_sev = 'NULL';
    if (exists $bug->{BugSeverity})  {
	$bug_sev = $bug->{BugSeverity};
    }
    
    my $res_sug = 'NULL';
    if (exists $bug->{ResolutionSuggestion})  {
	$res_sug = $bug->{ResolutionSuggestion};
    }

    my $classname = 'NULL';
    if (exists $bug->{ClassName})  {
	$classname = $bug->{ClassName};
    }
 
    my $length = scalar @{$bug->{Methods}};
    if (exists $bug->{Methods} && $length != 0)  {
        foreach my $method (@{$bug->{Methods}}) {
            $method->{MethodId} = int($method->{MethodId});
	    if ( $method->{primary} == 1)  {
                $method->{primary} = boolean::true;
            } else  {
                $method->{primary} = boolean::false;	
	    }
	}
    }

    $length = scalar @{$bug->{BugLocations}};
    if (exists $bug->{BugLocations} && $length != 0)  {
        foreach my $location (@{$bug->{BugLocations}}) {
            $location->{LocationId} = int($location->{LocationId});
            
	    if ( $location->{primary} == 1)  {
                $location->{primary} = boolean::true;
            } else  {
                $location->{primary} = boolean::false;	
	    }
    
	    if (exists $location->{StartLine})  {
		$location->{StartLine} = int($location->{StartLine});
	    }
    
	    if (exists $location->{EndLine})  {
	        $location->{EndLine} = int($location->{EndLine});
	    }

	    if (exists $location->{EndColumn})  {
	        $location->{EndColumn} = int($location->{EndColumn});
	    }

	    if (exists $location->{StartColumn})  {
		$location->{StartColumn} = int($location->{StartColumn});
	    }	
	}
    }

    my %bugInstance = ( assessId     	=> $data->{assessId},
			assessUuid   	=> $data->{assessUuid},
			pkgShortName 	=> $data->{pkgName},
			pkgVersion   	=> $data->{pkgVer},
			toolType     	=> $data->{toolName},
			toolVersion  	=> $data->{toolVersion},
			plat         	=> $data->{plat},
			BugMessage   	=> $bug->{BugMessage},
			BugGroup     	=> $bug_group,
			Location     	=> $bug->{BugLocations},
			Methods      	=> $bug->{Methods},
			BugId 	        => int($bug->{BugId}),
			BugCode          => $bug_code,
			BugRank          => $bug_rank,
			BugSeverity      => $bug_sev,
			BugResolutionMsg => $res_sug,
			classname        => $classname,		
			BugCwe           => $bug->{CweIds},
			);
    
    push @{$data->{scarf}}, \%bugInstance;
    
    $data->{db_count}++;
    if ($data->{db_commits} != 'INF' && $data->{db_commits} == $data->{db_count}) {
	my $res = $data->{assess}->insert_many(\@{$data->{scarf}});
	$data->{db_count} = 0;
	delete $data->{scarf};
    }
    return 0;
}

sub finish
{
    my ($data) = @_;
    
    # Executing the remaining instances 
    if (exists $data->{SQL}) {
	$data->{db}->commit();
	$data->{db}->disconnect();
    } elsif (exists $data->{NOSQL}) {
	if (($data->{db_count} != 0 && exists $data->{bug}) 
			|| $data->{db_commits} eq 'INF') {
	    my $res = $data->{assess}->insert_many(\@{$data->{scarf}});
	    delete $data->{scarf};
	}  elsif (($data->{db_count} != 0 && exists $data->{init}) 
			|| $data->{db_commits} eq 'INF')  {
	    $data->{assess}->insert({  'assessId'      => $data->{assessId},
	                                   'assessUuid'    => $data->{assessUuid},
					   'pkgShortName'  => $data->{pkgName},
					   'pkgVersion'    => $data->{pkgVer},
					   'toolType'      => $data->{toolName},
					   'toolVersion'   => $data->{toolVersion},
					   'plat'          => $data->{plat},
					});
	}
    }   
    return 0;
}

########################################## Opening the database #############################################
sub openDatabase
{
    
    my ($name, $type, $host, $port, $user, $pass) = @_;
    if ($type eq 'postgres')  {
	my $driver = "Pg";
        my $dsn = "DBI:$driver:dbname=$name;host=$host;port=$port";
        my $dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1, AutoCommit => 0, async => 1, fsync => 0 })
                       or die $DBI::errstr;
	
	#Returning the database handle
	return $dbh;
    }  elsif ($type eq 'mongodb')  {
	my $client;
        my $dbh;
	my $url;
	if (defined $user and defined $pass) {
	    $url = "mongodb://$user:$pass@" . $host . ":$port/$name";
	        
	} else  {
	    $url = "mongodb://" . $host . ":$port/$name";
	}
	
	$client = MongoDB->connect($url);
	$dbh = $client->get_database("$name");
	
	# Returning the database handle
	return $dbh;
    
    }  elsif ($type eq 'sqlite') {
	my $driver = "SQLite"; 
	my $dsn = "DBI:$driver:dbname=$name";
	my $dbh = DBI->connect($dsn, $user, $pass, {RaiseError => 1, AutoCommit => 0 }) 
                         or die $DBI::errstr;
	
	# Returning the database handle
	return $dbh;
    } else  {
	my $driver = "mysql";
	my $dsn = "DBI:$driver:database=$name;host=$host;port=$port";
	
	my $dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1, AutoCommit => 0, async => 1 }) 
	    or die $DBI::errstr;
	
	# Returning the database handle
	return $dbh;
    }
}

#################################### Creating or deleting tables ##############################################
sub ProcessTableOptions
{
    my ($delete, $create ,$name , $database, $host,
	    $port, $user, $pass, @table_names) = @_;
    
    if (defined $delete) {
        delete_tables($name , $database, $host, $port, $user, $pass, @table_names);
    } elsif  (defined ($create))  {
        create_tables($name , $database, $host, $port, $user, $pass, @table_names);
    }
}

############################# Method to delete tables in a specific SQL database ####################################
sub delete_tables
{
    my ($name , $database, $host, $port, $user, $pass, @table_names) = @_;
    my $dbh = openDatabase($name, $database, $host, $port, $user, $pass);
    $dbh->{PrintError} = 0;
    $dbh->{RaiseError} = 0;
    my ($delete) = SQLStatements('delete');
    my @errors;
    foreach my $table ( @table_names ) {	
	my $statement = $delete . "$table;";
	my $check = $dbh->do($statement) or push @errors, $DBI::errstr;
	$dbh->commit();  
    }
    $dbh->disconnect;
    if (@errors) {
	print @errors;
	exit 1;
    }
    exit 0;
}

############################# Method to create tables in a specific SQL database ####################################
sub create_tables
{

    # Required private variable for the subroutine
    my ($name , $database, $host, $port, $user, $pass, @table_names) = @_;
    my $dbh = openDatabase($name, $database, $host, $port, $user, $pass);
    my $counter = 0;
    my $create;
    my $check;
    my $primaryKey = "BIGSERIAL PRIMARY KEY";

    if ($database eq 'mariadb' || $database eq 'mysql')  {
	$primaryKey = "INT PRIMARY KEY AUTO_INCREMENT";
    }
    
    if ($database eq 'sqlite')  {
	$primaryKey = "integer PRIMARY KEY AUTOINCREMENT";
    }

    my %tables = SQLStatements('create');
    
    foreach my $table (@table_names) {
	
	my $create = $tables{$table};
	if ($table eq 'assess') {
	    $create = join($primaryKey, split(/\?/, $tables{$table}, 2));
	}
	
	$check = $dbh->do($create);
	# Checking whether the table is successfully created
	if ($check < 0)  {
	   print "Table \'$table\' not created\n$DBI::errstr\n";
	}
	$dbh->commit();  
    }
    $dbh->disconnect;
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
