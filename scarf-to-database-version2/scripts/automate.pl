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
require 'scarf-to-database.pl';

#################################################### Main ########################################################
sub main
{
    my %options = parseCmdArgs();
    open (my $filehandler, '>>', "failedPackages.txt") or die "Could not open file failedPackages.txt $!";
    if (defined($options{packages}))  {
	packages($options{dir});
	open (my $fh, '<', "packages.txt") or die "Could not open file packages.txt $!";
	while (my $packageName = <$fh>) {
	    chomp $packageName;
	    my $ret = mainSave($options{name}, $options{database}, $options{create}, $options{table}, $packageName);
	    if ( $ret != 1 )  {
		print $filehandler "$packageName\n";
	    } elsif ( $ret == 1)  {
		$options{create} = 0;
	    }
	    sleep(2);
	}
	close $fh;
    } else  {
	my $ret = mainSave($options{name}, $options{database}, $options{create}, $options{table}, $options{dir});
	if ( $ret != 1 )  {
	    print $filehandler $options{dir};
	}
    }
    close $filehandler;
    unlink "failedPackages.txt";
    unlink "packages.txt";
}

############################ Sub routine to get the name of packages in the directory  ############################
sub packages
{
    my %toolNames;
    opendir(my $dir, "$_[0]") or die "unable to open the directory $_[0]: $!\n";
    my @contents = readdir($dir);
    open(my $fh, '>', "packages-names.txt") or die "Could not open file packages-names.txt $!";
    foreach my $dirName(@contents){
        if ($dirName =~ /^.*?parse$/)  {
            my @tool = split(/---/, $dirName);
            print $fh "$dirName\n";
            $toolNames{$tool[2]} = $tool[2];
        }
    }
    closedir($dir);
    close $fh;

    open(my $filehandler, '>', "packages.txt") or die "Could not open file packages.txt $!";
    foreach my $key (sort keys %toolNames) {
        open( $fh, '<', "packages-names.txt" ) or die "Can't open  $!";
        while ( my $packageName = <$fh> ) {
            my @tool = split(/---/, $packageName);
            if ($key eq $tool[2])  {
                print $filehandler "$packageName";
            }
        }
        close $fh;
   }
   close $fh;
   system("rm -rf packages-names.txt");
}


########## sub-routine to parse the command line options and to find the type of bug file ##################
sub parseCmdArgs
{
    my %options = (
        help            => 0,
	version         => 0,
	create          => 0,
	table           => 0,
	dir             => undef,
	name            => undef,
	database        => undef,
	packages        => undef
    );
    
    my @options = (
        "help|h!",
        "version|v!",
        "create|c!",
        "table|t!",
        "dir|d|i=s",
        "name|n|o=s",
        "database|D|j=s",
	"packages|p!"
        );

    Getopt::Long::Configure(qw/require_order no_ignore_case no_auto_abbrev/);
    my $ok = GetOptions(\%options, @options);
  
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
    defined $options{dir} or die 'No directory name provided';
    defined $options{name} or die 'No database name provided';
    defined $options{database} or die 'No database type provided';

    #removing the end forward slash from dir name
    $options{dir} =~ /^(.*?)\/$/;
    if (defined($1))  {
        $options{dir} = $1;
    }

    return %options;
}

########################################## Subroutine to print help ##########################################
sub printHelp
{

    my $progname = $0;
    print STDERR <<EOF;

    Usage: $progname [options] <dir>...
    Find scarf file in the given directory name. Parse scarf file and save parsed results in a database.

    options:
    --help                      		-h print this message
    --version                   		-v print version
    --create                    		-c create database
    --table                     		-t create tables in the given database
    --dir=<dir-name>            		-d directory name
    --name=<database-name-to insert-data>       -n database name to insert data
    --database=<name of the database server>    -D Eg. postgres, mongodb, mysql etc.
EOF
}


#################################### Print version of the program #################################
sub printVersion
{
    my $version = '1.0.0 (June 7, 2016)';
    my $progname = $0;
    print "$progname version $version\n";
}

main();
