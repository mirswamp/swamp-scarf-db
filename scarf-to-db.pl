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
   
    # printing out the execution commands
    if (defined $options{just_print})  {
	defined $options{create_tables} and justPrint('create', $options{db_type});
	defined $options{delete_tables} and justPrint('delete', $options{db_type});
	defined $options{scarf} and justPrint('insert', $options{db_type});
	exit 0;
    }
   
    my @tableNames = ("assess", "weaknesses", "locations", "methods", "metrics", "functions");
    
    # Processing the table options depending on the command line arguments
    if (($database eq 'postgres' || $database eq 'mariadb' || $database eq 'mysql'
	   || $database eq 'sqlite') && ($options{create_tables} 
	   || $options{delete_tables}))  {
	ProcessTableOptions($options{delete_tables}, $options{create_tables}, $name, 
			    $database, $options{db_host}, $options{db_port}, 
			    $options{db_username}, $options{db_password}, @tableNames);
	exit 0;
    }

    # Testing the authentication information
    if (defined($options{test_auth})) {
	TestConnection($name, $database, $options{db_host}, $options{db_port},
			$options{db_username}, $options{db_password});
	exit 0;
    }

    # Saving SCARF results
    if ($options{scarf} =~ /^.*.conf$/) {
	my ($retVal, %names) = findScarf($options{scarf});
	if ($retVal == 1) {   	    
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
	auth_conf   	=> 'scarf-to-db-auth.conf',
	conf		=> 'scarf-to-db.conf',
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
	test_auth	=> undef,
	);

    # for options that contain a '-', make the first value be the
    # same string with '-' changed to '_', so quoting is not required
    # to access the key in the hash $option{input_file} instead of
    # $option{'input-file'}
    
    my @options = (
	"help|h!",
	"version|v!",
	"auth_conf|auth-conf=s",
	"conf=s",
	"db_type|db-type=s",
	"db_host|db-host=s",
	"create_tables|create-tables!",
	"delete_tables|delete-tables!",
	"db_port|db-port=s",
	"db_commits|db-commits=s",
	"db_name|db-name=s",
	"scarf|S=s",
	"pkg_name|pkg-name=s",
	"pkg_version|pkg-version=s",
	"platform=s",
	"just_print|just-print|n!",
	"db_username|db-username=s",
	"db_password|db-password=s",
	"test_auth|test-auth!",
    );

    
    Getopt::Long::Configure(qw/require_order no_ignore_case no_auto_abbrev/);
    my %getoptOptions;
    my $ok = GetOptions(\%getoptOptions, @options);

    # Checking whether appropriate command line options were given
    my @confFileOptions = qw/ auth_conf conf /;
    
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

    # Setting the defaults 
    defaults(\%options);
    
    # Checking whether appropriate options were present in the configuration files
    my @errors;
    $options{db_type} = lc($options{db_type});
    my %types = (
	'postgres'	=> {
				auth	=> 1,
				tables	=> 1,
	}, 
	'mongodb'	=> {
				auth	=> 0,
				tables	=> 0,
	}, 
	'mariadb'	=> {
				auth 	=> 1,
				tables	=> 1,
	}, 
	'sqlite'	=> {
				auth	=> 0,
				tables	=> 1,
	},
	'mysql'		=> {
				auth	=> 1,
				tables	=> 1,
	},
    );
    
    my $count = 0;

    # Checking whether appropriate command line options are provided
    defined $options{just_print} and $count++;
    defined $options{just_print} and defined $options{scarf} and $count++;
    defined $options{just_print} and defined $options{create_tables} and $count++;
    defined $options{just_print} and defined $options{delete_tables} and $count++;
    
    # Checking that one other option is provided with just-print option
    if ($count == 1) {
	print "Please provide one of the following options: scarf, " 
		. "create_tables or delete_tables with --just-print or -n option.\n";
	exit(1);
    }
    
    if ($count > 2) {
	print "Please provide 'only' one of the following options: scarf, " 
		. "create_tables or delete_tables with --just-print or -n option.\n";
	exit(1);
    }
    
    # Checking for other options
    if (exists($types{$options{db_type}})) {
        if ($types{$options{db_type}}{auth} && $count == 0 && 
	    !defined $options{auth_conf}) {
	    push @errors, "No scarf-to-db-auth.conf file provided\n";	
        }
    } else {
	push @errors, "Database type \'$options{db_type}\' is incorrect\n";
    }
    
    if (!defined $options{delete_tables} && !defined $options{create_tables} 
		&& !defined $options{test_auth}) {
	if (!defined $options{db_name} && $count == 0)  {
	    push @errors, "No database name provided\n";
	}
    
	if (!defined $options{scarf} && $count == 0)  {
	    push @errors, "No scarf file or results conf file provided\n";
	}
    } elsif (defined $options{test_auth}) {
	# Ignore this option	
    } elsif (!$types{$options{db_type}}{tables}) {
	    print "Schema of tables is only available for SQL tables and NOT MongoDB\n";
	    exit 1;
    }
    
    # Checking the errors array for any errors
    if (@errors)  {
	print @errors;
	exit(1);
    }

    return %options;
}

################################# Subroutine to set default values #########################################
sub defaults
{

    my ($options) = @_;
    
    defined $options->{pkg_name} or $options->{pkg_name} = undef;
    defined $options->{pkg_version} or $options->{pkg_version} = undef;    
    defined $options->{platform} or $options->{platform} = undef;
    
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

    Usage: $progname [options] [value] 
    Parse the given XML SCARF file and save the results in any of the
    following databases: MongoDB, PostgreSQL, MariaDB, MySQL or SQLite

Options:
    -h [ --help ]               print this message
    -v [ --version ]            print version
    --auth-conf			path to the conf file containing the username
				and password for database
    --conf	  		path to the conf file containing the database 
				parameters
    --db-type		   	this can be any of the databases supported, 
				default: mongodb
    --db-host			hostname of the DBMS server, default: localhost
    --create-tables		creates tables for SQL databases
    --delete-tables		deletes tables for SQL databases
    --db-port			port on which the DBMS server listens on, 
				default: 27017 (MongoDB), 5432 (PostgreSQL) 
				or 3306 (MySQL, MariaDB),
    --db-commits		max number of weaknesses to commit at once
				default: INF(infinity) for SQL databases,
				1500 for MongoDB
    --db-name			name of the db in which you want to save the 
				scarf results. For eg: test, scarf, swamp etc. 
				MongoDB and SQLite creates the db if it does not 
				already exist
    -S [ --scarf ]              path to the SCARF results XML 
				(parsed_results.xml) or parsed_results.conf file
    --pkg-name			name of the package that was assessed
    --pkg-version		version of the package that was assessed
    --platform			platform the assessment was run on
    -n [ --just-print ]		prints out create, insert or delete statements 
				depending the other argument passed with this 
				option

Authentication Options:
    --db-username 		Username for DBMS
    --db-password		Password for DBMS
    --test-auth			Verifies authentication credentials for the 
				database type

EOF
}


#################################### Print version of the program #################################
sub printVersion
{
    my $version = '0.9.0 (August 2, 2016)';
    my $progname = $0;
    print "$progname version $version\n";
}

#################################### Printing the database commands #################################
sub justPrint
{
    my ($operation, $type, $stmtType, @values) = @_;
    my $retValue = 0;
    
    if (defined ($stmtType) && @values) {
	my %statements = SQLStatements('insert', $type);
	my @insertValues = @values;
	if ($statements{$stmtType} =~ /^(.*?)\(\?/s) { 
	
	    if ($stmtType eq 'assess') {
		foreach my $value (@insertValues) {
		    if (!defined $value) {
			$value = '';
		    } 	
		}
		my $insert = join("\', \'", @insertValues);
		$insert = "$1 \(\'$insert\'\);";
		$retValue = $insert;
	    } 
	
	    foreach my $value (@values) {
		if (!defined $value) {
		    $value = 'null';
		} else {
		    $value = "\'$value\'";
		}
	    }
	    my $insert = join(", ", @values);
	    $insert = "$1 \($insert\);";
	    print "$insert\n";
	}
    } else {
	print "\n";
	if ($operation ne 'delete') {
	    my %statements = SQLStatements($operation, $type);
	    $operation = uc($operation);
	    while (my ($k, $v) = each %statements) {
		print "$v\n";
	    }
	} else {
	    my ($deleteStatement, @tableNames) = SQLStatements($operation, $type);
	    $operation = uc($operation);
	    foreach my $table (@tableNames) {
		print "$deleteStatement $table;\n";
	    }
	}
	print "\n";
    }
    return $retValue;
}


#################################### SQL database commands #################################
sub SQLStatements
{
	my ($operation, $db_type) = @_; 
	my %insertStatements = (
	    assess	=>  "INSERT INTO assess (assessuuid, pkgshortname, pkgversion, tooltype, " .
			    "toolversion, plat) VALUES (?, ?, ?, ?, ?, ?);", 
	    weaknesses	=> "INSERT INTO weaknesses VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
	    locations	=> "INSERT INTO locations VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", 
	    methods	=> "INSERT INTO methods VALUES (?, ?, ?, ?, ?);",
	    metrics	=> "INSERT INTO metrics VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
	    functions	=> "INSERT INTO functions VALUES (?, ?, ?, ?, ?, ?);",
	);

	my $primaryKey = "BIGSERIAL PRIMARY KEY";

	if ($db_type eq 'mariadb' || $db_type eq 'mysql')  {
	    $primaryKey = "INT PRIMARY KEY AUTO_INCREMENT";
	}
    
	if ($db_type eq 'sqlite')  {
	    $primaryKey = "integer PRIMARY KEY AUTOINCREMENT";
	}

	my %createStatements = (
	    assess	=> qq(CREATE TABLE assess ( 
			    assessId		$primaryKey,
			    assessUuid		text			NOT NULL,
			    pkgShortName	text,
			    pkgVersion		text,
			    toolType		text			NOT NULL,
			    toolVersion		text,
			    plat		text
			    );),
	    
	    weaknesses	=> qq(CREATE TABLE weaknesses (
			    assessId		integer			NOT NULL,
			    bugId		integer			NOT NULL,
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
			    assessId		integer			NOT NULL,
			    bugId		integer			NOT NULL,
			    locId		integer			NOT NULL,
			    isPrimary		boolean			NOT NULL,
			    sourceFile		text			NOT NULL,
			    startLine		integer,
			    endLine		integer,
			    startCol		integer,
			    endCol		integer,
			    explanation		text,
			    PRIMARY KEY (assessId, bugId, locId)	
			    );),
	
	    methods	=> qq(CREATE TABLE methods (
			    assessId		integer			NOT NULL,
			    bugId		integer			NOT NULL,
			    methodId		integer,
			    isPrimary        	boolean,
			    methodName       	text,
			    PRIMARY KEY (assessId, bugId, methodId)	
			    );),

	    metrics	=> qq(CREATE TABLE metrics (
			    assessId		integer			NOT NULL,
			    metricId		integer			NOT NULL,
			    sourceFile		text,
			    class		text,
			    method		text,
			    type		text,
			    strVal		text,
			    numVal		real,
			    PRIMARY KEY (assessId, metricId)	
			    );),

	    functions	=> qq(CREATE TABLE functions ( 
			    assessId		integer			NOT NULL,
			    sourceFile		text,
			    class		text,
			    method		text,
			    startLine		integer,
			    endLine		integer
			    );),
	);

	my @tableNames = ("assess", "weaknesses", "locations", "methods", "metrics", "functions");
	
	if ($operation eq 'create')  {
	    return (%createStatements);
	} elsif ($operation eq 'insert')  {
	    return (%insertStatements);
	} elsif ($operation eq 'delete') {
	    return ("DROP TABLE ", @tableNames);
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
	my %insertStatements = SQLStatements('insert', $database);
	
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
    
    my $insert = justPrint(0, $data->{name}, 'assess', $details->{uuid}, $data->{pkgName}, 
                    $data->{pkgVer}, $details->{tool_name}, $details->{tool_version}, 
		    $data->{plat});
    if ($insert) {
	my $check = $data->{db}->do($insert);
	if ($check < 0)  {
	    die "Unable to insert\n";
	}
    
	$data->{assessId} = $data->{db}->last_insert_id("", "", "assess", "");
	$data->{toolName} = $details->{tool_name};
    	$data->{SQL} = 'SQL';
    }
    return 0;
}

sub metric
{
    my ($metric, $data) = @_;
    my ($strVal, $startLine, $endLine) = (undef, undef, undef);

    my $classname = undef;
    if (exists $metric->{Class})  {
	$classname = $metric->{Class};
    }
    
    my $method_name = undef;
    if (exists $metric->{Method})  {
	$method_name = $metric->{Method};
    }

    if ($metric->{Value} =~ /^[0-9]+$/)  {
	my $check = $data->{metrics}->execute($data->{assessId}, $metric->{MetricId},
		     $metric->{SourceFile}, $classname, $method_name, $metric->{Type},
		     $strVal, $metric->{Value});
	
	justPrint(0, $data->{name}, 'metrics', $data->{assessId}, $metric->{MetricId},
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
	
	justPrint(0, $data->{name}, 'metrics', $data->{assessId}, $metric->{MetricId},
			$metric->{SourceFile}, $classname, $method_name, $metric->{Type},
			$metric->{Value}, $strVal);
	
	if ($check < 0)  {
	    die "Unable to insert\n";
	}
    }

    my $check = $data->{functions}->execute($data->{assessId}, $metric->{SourceFile},
		 $classname, $method_name, $startLine, $endLine);
	
    justPrint(0, $data->{name}, 'functions', $data->{assessId}, $metric->{SourceFile},
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
	    
	    justPrint(0, $data->{name}, 'methods', $data->{assessId}, $bug->{BugId},
			    $method->{MethodId}, $method->{primary}, $method->{name});
	    
	    if ($check < 0)  {
		die "Unable to insert\n";
	    }	
	}

    } else  {
	my ($methodId, $primary, $name) = (-1, undef, undef);
	my $check = $data->{methods}->execute($data->{assessId}, $bug->{BugId},
		    $methodId, $primary, $name);
	    
	justPrint(0, $data->{name}, 'methods', $data->{assessId}, $bug->{BugId},
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
		    , $loc_end_line) = (undef, undef, undef, undef, undef); 
	    
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
	    
	    justPrint(0, $data->{name}, 'locations', $data->{assessId}, $bug->{BugId},
	                    $location->{LocationId}, $location->{primary}, $location->{SourceFile},
			    $loc_start_line, $loc_end_line, $loc_start_col, $loc_end_col, $loc_expla);	    
	    
	    if ($check < 0)  {
		die "Unable to insert\n";
	    }
	}
    }
    
    my $bug_code = undef;
    if (exists $bug->{BugCode})  {
	$bug_code = $bug->{BugCode};
    }

    my $bug_group = undef;
    if (exists $bug->{BugGroup})  {
	$bug_group = $bug->{BugGroup};
    }
    
    my $bug_rank = undef;
    if (exists $bug->{BugRank})  {
	$bug_rank = $bug->{BugRank};
    }
    
    my $bug_sev = undef;
    if (exists $bug->{BugSeverity})  {
	$bug_sev = $bug->{BugSeverity};
    }
    
    my $res_sug = undef;
    if (exists $bug->{ResolutionSuggestion})  {
	$res_sug = $bug->{ResolutionSuggestion};
    }
    
    my $classname = undef;
    if (exists $bug->{ClassName})  {
	$classname = $bug->{ClassName};
    }
    
    if (exists $bug->{CweIds})  {	
	foreach my $cweid ( $bug->{CweIds} )  {  
	    my $check = $data->{weaknesses}->execute($data->{assessId}, $bug->{BugId},
			    $bug_code, $bug_group, $bug_rank, $bug_sev, $bug->{BugMessage},
			    $res_sug, $classname, $cweid);
	    
	    justPrint(0, $data->{name}, 'weaknesses', $data->{assessId}, $bug->{BugId},
	                    $bug_code, $bug_group, $bug_rank, $bug_sev, $bug->{BugMessage},
			    $res_sug, $classname, $cweid);	    
	    
	    if ($check < 0)  {
		die "Unable to insert\n";
	    }
	}
    } else  {
	    my $cweid = undef;
	    my $check = $data->{weaknesses}->execute($data->{assessId}, $bug->{BugId},
			    $bug_code, $bug_group, $bug_rank, $bug_sev, $bug->{BugMessage},
			    $res_sug, $classname, $cweid);
	    
	    justPrint(0, $data->{name}, 'weaknesses', $data->{assessId}, $bug->{BugId},
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
    
    $data->{bug} = 1;
    my $classname = undef;
    if (exists $metric->{Class})  {
        $classname = $metric->{Class};
    }

    my $method_name = undef;
    if (exists $metric->{Method})  {
        $method_name = $metric->{Method};
    }

    my %metricInstance = (  assessUuid   	=> $data->{assessUuid},
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
    
    $data->{bug} = 1;
    my $bug_code = undef;
    if (exists $bug->{BugCode})  {
        $bug_code = $bug->{BugCode};
    }

    my $bug_group = undef;
    if (exists $bug->{BugGroup})  {
        $bug_group = $bug->{BugGroup};
    }

    my $bug_rank = undef;
    if (exists $bug->{BugRank})  {
	$bug_rank = $bug->{BugRank};
    }

    my $bug_sev = undef;
    if (exists $bug->{BugSeverity})  {
	$bug_sev = $bug->{BugSeverity};
    }
    
    my $res_sug = undef;
    if (exists $bug->{ResolutionSuggestion})  {
	$res_sug = $bug->{ResolutionSuggestion};
    }

    my $classname = undef;
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

    my %bugInstance = ( assessUuid   	=> $data->{assessUuid},
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
	    $data->{assess}->insert({      'assessUuid'    => $data->{assessUuid},
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

###################################### Testing the authetication data #######################################
sub TestConnection
{
    my ($name, $type, $host, $port, $user, $pass) = @_;
    my $dbh = openDatabase($name, $type, $host, $port, $user, $pass);
    
    # mongodb only authenticates when you try to access the database
    if ($type eq 'mongodb') {
	$dbh->collection_names;
    }
    print "Connection successful\n";
}

########################################## Opening the database #############################################
sub openDatabase
{
    
    my ($name, $type, $host, $port, $user, $pass) = @_;
    if ($type eq 'postgres')  {
	my $driver = "Pg";
        my $dsn = "DBI:$driver:dbname=$name;host=$host;port=$port";
        my $dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1, AutoCommit => 0, 
				    async => 1, fsync => 0 }) or die $DBI::errstr;
	
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
	justPrint('delete', $database);
    } elsif  (defined ($create))  {
        create_tables($name , $database, $host, $port, $user, $pass, @table_names);
	justPrint('create', $database);
    }
}

############################# Method to delete tables in a specific SQL database ####################################
sub delete_tables
{
    my ($name , $database, $host, $port, $user, $pass, @table_names) = @_;
    my $dbh = openDatabase($name, $database, $host, $port, $user, $pass);
    $dbh->{PrintError} = 0;
    $dbh->{RaiseError} = 0;
    my ($delete) = SQLStatements('delete', $database);
    my @errors;
    foreach my $table ( @table_names ) {	
	my $statement = $delete . "$table;";
	my $check = $dbh->do($statement) or push @errors, $DBI::errstr;
	$dbh->commit();  
    }
    $dbh->disconnect;
    if (@errors) {
	local $" = "\n";
	print "@errors\n";
	exit 1;
    }
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
    my %tables = SQLStatements('create', $database);
    
    foreach my $tableName (@table_names) {
	
	my $create = $tables{$tableName};
	$check = $dbh->do($create);
	# Checking whether the table is successfully created
	if ($check < 0)  {
	   print "Table \'$tableName\' not created\n$DBI::errstr\n";
	}
	$dbh->commit();  
    }
    $dbh->disconnect;
}
    
###################################### reading the conf file #####################################################

# HasValue - return true if string is defined and non-empty
sub HasValue
{
    my ($s) = @_;
    return defined $s && $s ne '';
}

sub ReadConfFile
{
    my ($filename, $required, $mapping) = @_;

    my $lineNum = 0;
    my $colNum = 0;
    my $linesToRead = 0;
    my $charsToRead = 0;
    my %h;
    $h{'#filenameofconffile'} = $filename;

    my %mapping;
    if (defined $mapping)  {
	if (ref($mapping) eq 'HASH')  {
	    %mapping = %$mapping;
	}  elsif (ref($mapping) eq 'ARRAY')  {
	    foreach my $a (@$mapping)  {
		$a =~ s/[:=!].*$//;
		my @names = split /\|/, $a;
		my $toName = shift @names;
		foreach my $name (@names)  {
		    $mapping{$name} = $toName;
		}
	    }
	}  else  {
	    die "ReadConfFile: ERROR mapping has unknown ref type: " . ref($mapping);
	}
    }

    open my $confFile, "<$filename" or die "Open configuration file '$filename' failed: $!";
    my ($line, $k, $origK, $kLine, $err);
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
		$origK = $1;
		$k = (exists $mapping{$origK}) ? $mapping{$origK} : $origK;
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
