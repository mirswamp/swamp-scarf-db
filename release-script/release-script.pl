#! /usr/bin/perl -w
use strict;
use 5.010;
use Getopt::Long;

sub ProcessOptions
{
    my %optionDefaults = (
        release_file	=> undef,
	output	=> undef,
    );

    my @options = (
	"release_file|release-file|r=s",
	"output|o=s",
    );

    Getopt::Long::Configure(qw/require_order no_ignore_case no_auto_abbrev/);
    my %getoptOptions;
    my $ok = GetOptions(\%getoptOptions, @options);

    my %options = %optionDefaults;
    while (my ($k, $v) = each %getoptOptions)  {
	$options{$k} = $v;
    }

    my @errs;
    defined $options{release_file} or push @errs, "Provide release file\n";
    defined $options{output} or push @errs, "Provide output directory\n";

    if (@errs) {
	print @errs;
	exit 1;
    }

    return %options
}

sub main
{
    my %options = ProcessOptions();
    open (my $fh, '<', $options{release_file}) or die "Could not open $options{release_file} $!";
    
    # Creating output directory
    system("mkdir $options{output}");
    system("mkdir $options{output}/bin");
    system("mkdir $options{output}/Readme");

    my %hash;
    
    # Getting the repository and the file name
    while (my $file = <$fh>) {
	if ($file =~ /^(git.*),(.*file.*)/) {
	    my $git = $1;
	    my $fileName =  $2;
	    $git =~ s/^\s+|\s+$//g;
	    $fileName =~ s/^\s+|\s+$//g;
	    my @fileNames;
	    if ($git =~ /^(.*)=(.*)$/) {
		$1 =~ s/^\s+|\s+$//g;
		$2 =~ s/^\s+|\s+$//g;
		$hash{$1} = $2;
	    }
	    if ($fileName =~ /^(.*)=(.*)$/) {
		my $k = $1;
		my $v = $2;
		$k =~ s/^\s+|\s+$//g;
		$v =~ s/^\s+|\s+$//g;
		if ($v =~ /^.*,.*/) {
		    @fileNames = split(/,/, $v);
		}
		$hash{$k} = \@fileNames;
	    }
	}
	my $output = `git clone $hash{git}`;
	if ($output =~ /.*\'(.*)\'.*/) {
	    my $gitDirName = $1;
	    foreach $file (@{$hash{files}}) {
		$file =~ s/^\s+|\s+$//g;
		if ($file =~ /^README.*$/ || $file =~ /^Readme.*$/) {
		    system("cp $gitDirName/$file $options{output}/Readme");
		    my $output1 = `/p/swamp/bin/asciidoctor -b pdf $options{output}/Readme/$file 2>/dev/null`;
		    my $output2 = `/p/swamp/bin/asciidoctor -b html $options{output}/Readme/$file 2>/dev/null`;
		} else {
		    system("cp $gitDirName/$file $options{output}/bin");
		}
	    }
	    system("rm -rf $gitDirName");
	}	    
    }
    
    my $tarOutput = `tar -cvzf $options{output}.tar.gz $options{output}`;
    system("rm -rf $options{output}");
}

main()
    
