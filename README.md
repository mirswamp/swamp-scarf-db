<title><h3><center><strong>scarf-to-db USER GUIDE</strong></h3></center></title>
  	
This document's the program `scarf-to-db` that can be used to upload SCARF results into a NOSQL database (MongoDB) or SQL databases (PostgreSQL, MySQL, MariaDB or SQLite3). Uploading SCARF results into any DBMS involves the following steps: 

1. Installing the DBMS (see Appendix A)
2. Installing Perl drivers (see Appendix B)
3. Edit Configuration Files
4. Create or Delete db tables (SQL databases) 
5. Using the script `scarf-to-db` to save SCARF results
6. Extras (example documents, schema for SQL tables, etc.)

#### **Edit Configuration Files**

To operate, scarf-to-db requires configuration.  The configuration can be set using the command line, or via configuration files.  Scarf-to-db supports two configuration files:  _scarf-to-db.conf_ for database configuration, and _scarf-to-db-auth.conf_ for database credential data (the permissions of this file should be restricted as it contains sensitive information).  The use of the configuration files is optional, but recommended.

The value for an option is determined by first one of these that sets the value: 1) command line options, 2) the scarf-to-db-auth.conf configuration file, 3) the scarf-to-db.conf file, and finally 4) defaults built-in to scarf-to-db.

The location of configuration files can be set from an option before it is read.  If the configuration file location is explicitly set, it will result in an error if the file does not exist, but if the value is the default value, the configuration file is skipped if not present.

The remainder of these sections describes each option and is grouped by the most appropriate place to set the option starting with the scarf-to-db.conf options, then scarf-to-db-auth.conf options, and finally options most appropriately passed as command line options. 

##### **scarf-to-db.conf**

The following key value pairs can be added into this configuration file. 

| Option | Description |  
|:---|:---|  
| `db-type=<type>`  | Database type - It can be any of the databases supported, default: mongodb |  
| `db-host=<host>`  | Hostname of the DBMS server, default: localhost |  
| `db-port=<port>`  | Port on which the DBMS server listens on. default: 27017 (MongoDB), 5432 (PostgreSQL) or 3306 (MySQL, MariaDB)  |  
| `db-name=<name>`*  | Name of the database in which you want to save scarf results to. For eg: test, scarf, swamp. MongoDB and SQLite creates the database if it does not already exists |  
| `db-commits=<max>` | Specifies the number of records or documents to be inserted, default: 1500 (MongoDB) or INF (infinity) (SQL databases) |  
| `pkg-name=<name>` | Name of the package that was assessed (default: NULL) |  
| `pkg-version=<version>` | Version of the package that was assessed default: NULL) |  
| `platform=<name>` | Name of the platform on which the assessment was run default: NULL) |
| `authenticate=<path>` | Path to scarf-to-db-auth.conf file described in the next step (default location: current directory) |

> **Note:** In the above table, options with \* are mandatory  
> **Note:** For MongoDB the amount of memory used depends on the value of _db_commits_ option. If you notice high memory usage, try reducing the value of _db_commits_. 

##### **scarf-to-db-auth.conf**

The following key value pairs can be added into this configuration file.

| Option | Description |  
|:---|:---|  
| `db-username=<username>`*| Username for DBMS |  
| `db-password=<password>`* | Password for DBMS |

> **Note:** In the above table, options with \* are mandatory 

##### **command line options**
scarf-to-db can take following command line options.
| Option | Description |
|:---|:---|
| `scarf=<path>`*  | Path to the SCARF results XML (parsed\_results.xml) file or parsed\_results.conf file| 
| `--db_params=<path>` | Path to Config file containing database parameters (default location: current directory) |
| `help` | Prints out the help menu on the console and exits |  
| `version` |  Prints out the version of the program and exits |  
| `create-tables` | Creates tables for SQL databases and **saves the data**|
| `delete-tables` | Deletes tables for SQL databases and exits |
| `just-print` | Prints out the commands used for database execution and exits | 

> **Note:** In the above table, options with \* are mandatory

#### **Create or Delete db tables (SQL databases)**

To create or delete SQL tables specify the corresponding command line options as mentioned in the previous step. Here are the command line options again for reference.
| Option | Description |  
|:---|:---|  
| `create-tables` | Creates tables for SQL databases and **saves the data** |
| `delete-tables` | Deletes tables for SQL databases and **exits the script** |

> For more information regarding the schema of the tables refer to **Extras** section.

#### **Saving the SCARF results into a database**

To save the SCARF results into a database (Assuming you have that DBMS and appropriate perl drivers installed), use the script `scarf-to-db`.

To run the `scarf-to-db` script, the following information is required:

1. path to scarf-to-db.conf config file (shown in previous step)
2. path to authentication config file (shown in previous step) 

`scarf-to-db` script has the following command line options:


> **Note:** In the above table, options with \* are mandatory

#### **Extras**

##### **Examples:**
 
**scarf-to-db-auth.conf (default location: current directory)**
```
db-username = user
db-password = password
```

**scarf-to-db.conf (default location: current directory)**
```
db-host = VB-mongodb-rh64.vm.swamp.cs.wisc.edu
db-name = scarf
pkg-name = lighttpd
pkg-version = 1.4.33
platform = rhel-6.7-32
authenticate = scarf-to-db-auth.conf
```

**Execution command **
```sh
bin/scarf-to-db \
	scarf=./lighttpd-1.4.33----rhel-6.7-32---gcc-warn/parsed_results.conf \
```

> **Note:** If the above command executes successfully, user will not see any output and the data will be saved to the DBMS.  
> **Note (For MongoDB):**  If you notice any authentication related error messages. Please check if the `authenticationDatabase` used for the user is same as the database that you are trying to access

##### **Example document (MongoDB)**
* **BugInstance**

```
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
	"BugMessage" : "function declaration isn't a prototype ",
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

* **If the package does not contain any BugInstance or Metric**

```
{  
	"_id" : <Unique Id generated by MongoDB for each document>,
	"pkgVersion" : "0.2.0",  
	"assessUuid" : "6a3ee5c9-7818-4249-a22b-dd3a8e0e2004",  
	"toolType" : "cloc",  
	"toolVersion" : "1.64",  
	"assessId" : <This is an unique ID generated by program and is same for a particular pkg and tool>,  
	"plat" : "rhel-6.7-32",  
	"pkgShortName" : "statsd-c"  
}
```

##### **Schema (SQL databases)**
* **BugInstance**

```
assess table:
    assessId           integer PRIMARY KEY AUTOINCREMENT,
    assessUuid         text                    			NOT NULL,
    pkgShortName       text                    			NOT NULL,
    pkgVersion         text,
    toolType           text                    			NOT NULL,
    toolVersion        text,
    plat               text                    			NOT NULL,
	
methods table:
    assessId	    integer			NOT NULL,
    bugId		    integer			NOT NULL,
    methodId		integer,
    isPrimary       boolean,
    methodName      text,
    PRIMARY KEY (assessId, bugId, methodId)	

weaknesses table:
    assessId           integer                 NOT NULL,
    bugId              integer                 NOT NULL,
    bugCode            text,
    bugGroup           text,
    bugRank            text,
    bugSeverity        text,
    bugMessage         text,
    bugResolutionMsg   text,
    classname          text,
    bugCwe             text,
    PRIMARY KEY (assessId, bugId)


locations table:
    assessId		integer			NOT NULL,
    bugId		    integer			NOT NULL,
    locId		    integer			NOT NULL,
    isPrimary		boolean			NOT NULL,
    sourceFile		text			NOT NULL,
    startLine		integer,
    endLine		    integer,
    startCol		integer,
    endCol		    integer,
    explanation		text,
    PRIMARY KEY (assessId, bugId, locId)	
```

* **Metric**

```
assess table:
    assessId           integer PRIMARY KEY AUTOINCREMENT,
    assessUuid         text                    			NOT NULL,
    pkgShortName       text                    			NOT NULL,
    pkgVersion         text,
    toolType           text                    			NOT NULL,
    toolVersion        text,
    plat               text                    			NOT NULL,
    startTs            real,
    endTs              real

metrics table:
    assessId		integer			NOT NULL,
    metricId		integer,
    sourceFile		text,
    class		    text,
    method		    text,
    type		    text,
    strVal		    text,
    numVal		    real,
    PRIMARY KEY (assessId, metricId)	

functions table: 
    assessId		integer			NOT NULL,
    sourceFile		text,
    class		    text,
    method		    text,
    startLine		integer,
    endLine		    integer
```

* **If the package does not contain any BugInstance or Metric**
```
assess table:
    assessId           integer PRIMARY KEY AUTOINCREMENT,
    assessUuid         text                    			NOT NULL,
    pkgShortName       text                    			NOT NULL,
    pkgVersion         text,
    toolType           text                    			NOT NULL,
    toolVersion        text,
    plat               text                    			NOT NULL,
    startTs            real,
    endTs              real
```

#### **Appendix A**
#### 1. Installing MongoDB
If you do not have MongoDB installed already, please follow the installation guide at [https://docs.mongodb.com/manual/installation/](https://docs.mongodb.com/manual/installation/)

##### Installing MongoDB on RHEL based platforms
For installation specific to RHEL based platforms please see [https://docs.mongodb.com/manual/tutorial/install-mongodb-on-red-hat/](https://docs.mongodb.com/manual/tutorial/install-mongodb-on-red-hat/)

> NOTE: On `rhel-6.4-64` platform, executing `sudo yum install -y mongodb` will install an old version (2.4) of MongoDB. To install the latest version (3.2.8 or above) of MongoDB, please follow the steps in the section **Configure the package management system (yum)** in the tutorial [https://docs.mongodb.com/manual/tutorial/install-mongodb-on-red-hat/](https://docs.mongodb.com/manual/tutorial/install-mongodb-on-red-hat/)

Example: To install `3.2.x` version of MongoDB on `rhel-6.4-64`:

Create a file named `/etc/yum.repos.d/mongodb-org-3.2.repo` and add the following content to the file 

```conf
[mongodb-org-3.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/3.2/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-3.2.asc
```

Execute the following shell command to install MongoDB:
```sh
% sudo yum install -y mongodb-org
```

##### Check if the MongoDB server is running
If the installation is successful, please execute the following command to check if the MongoDB server is running.
```sh
# Invokes Mongo Shell
% mongo
```

If the above command fails with a message **exception: connect failed** then, MongoDB may not be running.

Execute the following command to run MongoDB:
```sh
% sudo /etc/init.d/mongod start
```

By default, MongoDB server listens on `localhost:27017` network interface. To access MongoDB from outside the MongoDB server machine, please [setup SSH tunnel](https://chamibuddhika.wordpress.com/2012/03/21/ssh-tunnelling-explained/) to the machine running MongoDB server. Example:
```sh
ssh -nNT -L 27017:127.0.0.1:27017 <user-name>@<mongodb-host-name>
```

In case, if you want to change the network interface and default port number that MongoDB server must listen on, please see the instruction at [https://docs.mongodb.com/manual/reference/configuration-options/](https://docs.mongodb.com/manual/reference/configuration-options/). Also, make sure that your local firewall settings allow connections to the MongoDB port.


##### Authentication
By default, MongoDB does not require *root password or user accounts* to create databases and insert documents. If you like to authenticate and authorize users please see [https://docs.mongodb.com/manual/tutorial/enable-authentication/](https://docs.mongodb.com/manual/tutorial/enable-authentication/).

#### 2. Installing PostgreSQL
If you don't have PostgreSQL installed already, please follow the installation guide at [https://www.postgresql.org/download/linux/redhat/](https://www.postgresql.org/download/linux/redhat/)

#### 3. Installing MySQL
If you don't have MySQL installed already, please follow the installation guide at [https://dev.mysql.com/doc/mysql-repo-excerpt/5.6/en/linux-installation-yum-repo.html](https://dev.mysql.com/doc/mysql-repo-excerpt/5.6/en/linux-installation-yum-repo.html)

#### 2. Installing MariaDB
If you don't have MariaDB installed already, please follow the installation guide at [https://mariadb.com/kb/en/mariadb/yum/](https://mariadb.com/kb/en/mariadb/yum/)

#### **Appendix B**
#### 2. Installing Perl drivers

`scarf-to-database` program uses Perl drivers. Install the following Perl drivers on the machine that you would want to call scarf-to-database script from
1. DBI
2. DBD::pg
3. MongoDB

On `rhel-6.4-64` platform, execute the following commands to install the drivers using CPAN
```sh
sudo cpan DBI DBD::Pg MongoDB
```
> NOTE: On some `rhel-6.4-64` machines, users may also have to install `YAML and Config::AutoConf` packages from CPAN. To install the `YAML and Config::AutoConf` package, execute the following shell command:

```sh
% sudo cpan YAML Config::AutoConf
```

> NOTE: The above command may ask for user confirmation to install packages and its dependencies too many times. To avoid typing `yes` on the CPAN console too many time, please run the following commands:

```sh
% sudo perl -MCPAN -e shell  # Opens up a CPAN shell
	cpan[1]> o conf prerequisites_policy follow
	cpan[2]> o conf build_requires_install_policy yes
	cpan[3]> o conf commit
```

For more information on how to avoid the `yes` confirmation dialog please see [https://major.io/2009/01/01/cpan-automatically-install-dependencies-without-confirmation/](https://major.io/2009/01/01/cpan-automatically-install-dependencies-without-confirmation/).  
