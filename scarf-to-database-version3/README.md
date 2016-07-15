This document describes the steps involved in uploading SCARF results into MongoDB.

1. Install MongoDB
2. Install Perl MongoDB drivers
3. Running the perl scripts to upload SCARF results into a MongoDB database

#### 1. Installing MongoDB
Follow the installation guide at [https://docs.mongodb.com/manual/installation/](https://docs.mongodb.com/manual/installation/) to install MongoDB.

##### Installing MongoDB on RHEL platforms
For installation specific to RHEL platforms please see [https://docs.mongodb.com/manual/tutorial/install-mongodb-on-red-hat/](https://docs.mongodb.com/manual/tutorial/install-mongodb-on-red-hat/)

> NOTE: On `rhel-6.4-64` platform, running `sudo yum install -y mongodb` will install an old version (2.4) of MongoDB. To install the latest version (3.2.8 or above) of MongoDB, please follow the steps in the section **Configure the package management system (yum)** in the tutorial.

To summarize the steps involved to install a latest version of MongoDB on `rhel-6.4-64`:

Add the following content to the file `/etc/yum.repos.d/mongodb-org-3.2.repo`.

```conf
[mongodb-org-3.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/3.2/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-3.2.asc
```
> NOTE: If the file `/etc/yum.repos.d/mongodb-org-3.2.repo` does not already exist please create it.

Run the following command to install MongoDB:
```sh
% sudo yum update -y # This is optional if your system is updated, and this may take a while
% sudo yum install -y mongodb-org
```

##### Check if the MongoDB server is running
If the installation is successful, please run the following command to check if the MongoDB server is running:
```sh
% mongo
```

If the above command fails with a message **exception: connect failed** then mongodb is not running.

Execute the following command to run mongodb:
```sh
% sudo /etc/init.d/mongod start
```

#### Authentication
TODO: To be done

#### 2. Installing Perl drivers to access MongoDB

Install the following Perl drivers on the machine that you would want to access MongoDB from
1. DBI
2. DBD::Pg
3. MongoDB

On `rhel-6.4-64` platform, execute the following commands to install the drivers using CPAN
```sh
sudo cpan DBI DBD::Pg MongoDB
```
> NOTE: On `rhel-6.4-64` machines, user may also have to install `YAML` package from CPAN. To install the `YAML` package, execute the shell command `sudo cpan YAML`

> NOTE: The above command may ask for user confirmation to install packages and its dependencies too many times. To avoid typing `yes` too many time, please run the following commands:

```sh
% sudo perl -MCPAN -e shell  # Opens up a CPAN shell
	cpan[1]> o conf prerequisites_policy follow
	cpan[2]> o conf build_requires_install_policy yes
	cpan[3]> o conf commit
```

For more information on avoid the `yes` confirmation dialog please see [https://major.io/2009/01/01/cpan-automatically-install-dependencies-without-confirmation/](https://major.io/2009/01/01/cpan-automatically-install-dependencies-without-confirmation/).

#### 3. Saving the SCARF results into MongoDB

To save the results into MongoDB (Assuming successful installation of MongoDB and MongoDB perl drivers)

1. By default, MongoDB server listens on `localhost:27017` network interface. To access MongoDB from outside the machine that MongoDB server is installed on, please [setup SSH tunnel](https://chamibuddhika.wordpress.com/2012/03/21/ssh-tunnelling-explained/) to the machine running MongoDB server. Example:
```sh
ssh -nNT -L 27017:127.0.0.1:27017 \
-o IdentityFile="$HOME/.ssh/id_rsa_mongodb" \
-o User=vamshi \
-tt VB-mongodb-rh64.vm.swamp.cs.wisc.edu
```

> NOTE: In case, if you want to change IP address and default port number for MongoDB, please see the instruction at [https://docs.mongodb.com/manual/reference/configuration-options/](https://docs.mongodb.com/manual/reference/configuration-options/). Also, make sure that your local Firewall settings allow connections to the MongoDB port.

2. Set the environment variable `PERL5LIB` to include `scarf-to-database-x.x.x/scripts` directory. Example:
```sh
export PERL5LIB="$HOME/scarf-to-database-0.8.0/scripts:$PERL5LIB"
```

3. To save the scarf results into MongoDB, run the script `scarf-to-database-x.x.x/automate.pl`.

The `scarf-to-database-x.x.x/automate.pl` has the following options:

| Option | Description |
|:---:|:---|
| `--help` | Prints out the help menu on the console and exits |
| `--version` |  Prints out the version of the program and exits |
| `--database <database-type>`* |   It is the name of the database client. Must be `mongodb`. It also supports: postgres, mysql, mariadb |
| `--name <name-of-the-database>`*  | It is the name of the database in which you want to save data. For eg: test, scarf, swamp |
| `--packages` |   If you are using directory as '.' which holds multiple sub directories for saving to the database use this command line argument with it |
| `--create` | If you are using SQL based databases and haven't created the database with the name `<name-of-the-database>` |
| `--tables` | If you are using SQL based databases and haven't created the tables, this flag tells the program to create the tables |

Example:
```sh
perl $HOME/scarf-to-database-0.8.0/automate.pl \
	--database=mongodb \
	--name=scarf \
	--create \
	--table \
	--dir=$HOME/scarf-results/webgoat-5.4_1---rhel-6.4-64---findbugs-3.0.1---parse
```


Example:
```sh
# To upload results from multiple assessments
perl $HOME/scarf-to-database-0.8.0/automate.pl \
	--database=mongodb \
	--name=scarf \
	--create \
	--table \
	--dir=$HOME/scarf-results/
```

#### Example document
* **BugInstance**

```sh
{  
	"_id" : <Unique Id generated by mongodb for each document>,  
	"bugCwe" : null,  
	"Methods" : [ ],  
	"bugSeverity" : "NULL",  
	"pkgVersion" : "1.4.33",  
	"bugRank" : "NULL",  
	"toolVersion" : "4.4.7 20120313 (Red Hat 4.4.7-16) (GCC)",  
	"plat" : "rhel-6.7-32",  
	"BugGroup" : "warning",  
	"bugId" : NumberLong(20),  
	"toolType" : "gcc-warn",  
	"assessId" : <This is an unique ID generated by program and is same for a particular pkg and tool>,
	"classname" : "NULL",  
	"bugResolutionMsg" : "NULL",  
	"assessUuid" : "8f74881a-cf90-429e-9e35-bb2484bd2529",  
	"BugMessage" : "function declaration isnât a prototype ",  
	"pkgShortName" : "lighttpd",  
	"bugCode" : "-Wstrict-prototypes",  
	"Location" : [  
		{  
			"StartLine" : NumberLong(65),  
			"primary" : true,  
			"SourceFile" : "lighttpd-1.4.33/src/lemon.c",  
			"EndLine" : NumberLong(65),  
			"LocationId" : NumberLong(1)  
		}  
	]  
}
```

* **Metric**  

```
{  
	"_id" : <Unique Id generated by MongoDB for each document>,  
	"SourceFile" : "src/json-c/json_object.c",  
	"Type" : "language",  
	"pkgVersion" : "0.2.0",  
	"assessUuid" : "6a3ee5c9-7818-4249-a22b-dd3a8e0e2004",  
	"toolType" : "cloc",  
	"toolVersion" : "1.64",  
	"Value" : "C",  
	"assessId" : <This is an unique ID generated by program and is same for a particular pkg and tool>,  
	"plat" : "rhel-6.7-32",  
	"pkgShortName" : "statsd-c",  
	"MetricId" : NumberLong(17),  
	"Method" : null,  
	"Class" : "NULL"  
}  
```

* **If the package doesn't contain any BugInstance or Metric**

```
{  
	"_id" : <Unique Id generated by MongoDB for each document>,  
	"pkgVersion" : "0.2.0",  
	"assessUuid" : "6a3ee5c9-7818-4249-a22b-dd3a8e0e2004",  
	"toolType" : "cloc",  
	"toolVersion" : "1.64",  
	"assessId" : <This is an unique ID generated by program and is same for a particular pkg and tool>,  
	"plat" : "rhel-6.7-32",  
	"pkgShortName" : "statsd-c",  
}```
