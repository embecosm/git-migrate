#!/bin/sh

# Copyright (C) 2014 Embecosm Limited

# Contributor Jeremy Bennett <jeremy.bennett@embecosm.com>

# This file is a script for copying tags between repositories.

# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3 of the License, or (at your option)
# any later version.

# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.

# You should have received a copy of the GNU General Public License along
# with this program.  If not, see <http://www.gnu.org/licenses/>.

#			   SCRIPT TO COPY GIT TAGS
#			   =======================

# Usage:

#     ./git-copy-tags.sh --working-dir <dirname>
#                        [--script <filename>]
#                        [--suffix <suffix>]
#                        [-h|--help]

# This is a helper script for git-migrate.sh. See the comments their for the
# rationale.  It is provided as a separate script, since it may from time to
# time be useful to run on its own.  As such the arguments the working
# directory *must* be specified.

# The idea is to find all the tags in the remote repository old-local and
# redirect the tags to the equivalent place in the remote repository new-local.

# This script was prompted by the migration of binutils and GDB to a new
# unified binutils-gdb repository.

# The script can either create a new working directory with all the
# repositories as remotes, or can use an existing working directory. In the
# latter case the repos must have the names "old-upstream", "new-upstream",
# "old-local" and "new-local".

# --working-dir <dirname>

#     The working directory for the repositories. It is relative to the first
#     parent of the directory from which this script is run which is not part
#     of a git repository. If it does not exist it will be created. If not
#     specified a directory will be created and reported.

# --script <filename>

#     Name of the script file to be generated. It will be created relative to
#     the working directory. If not specified, the name "doit-tags.sh" will be
#     used.

# --suffix <suffix>

#     It may be necessary to rename the tags, to avoid clashes (for example
#     combining binutils and gdb into binutils-gdb may lead to duplicate
#     tags. This argument is used to add a suffix to the new tab name.

# --help
# -h


#------------------------------------------------------------------------------
#
#			       Useful functions
#
#------------------------------------------------------------------------------

# Map a commit ID in one repository and branch to the same commit ID in a
# different repository and branch.

# We do this by matching date and time (excluding seconds)

# @param $1  commit ID in old repository
# @param $2  new repository & branch

# @return  The commit ID in the new repository
map_commit () {
    old_cid=$1
    new_repo=$2

    ds=`git log -1 --date=iso ${old_cid} | grep Date: \
	| sed -e 's/Date:[[:space:]]*//' \
	      -e 's/^\([^:]*[012][0-9]:[0-5][0-9]\):.*$/\1/'`
    prev_cid=`git log --date=iso --reverse ${new_repo} \
	          | sed -n -e "/Date: *${ds}/,\\\$p" \
                  | sed -n -e 's/^commit //p' | head -1`

    # Deal with the yucky case where this is the latest commit, so there is no
    # later one to look at!
    if [ "x${prev_cid}" = "x" ]
    then
	git log -1 ${new_repo} | sed -n -e 's/^commit //p'
    else
	git log -1 ${prev_cid}~1 | sed -n -e 's/^commit //p'
    fi
}


# Create a line in the script file to write to the script log file

# @param $1  Indent
# @param $*  The line to log
sf_logit () {
    echo -n "$1" >> ${sf}
    shift
    echo "logit \"$*\"" >> ${sf}
}


# Create a line in the script file to execute an action

# @param $* The line to execute
sf_do () {
    echo "$*" >> ${sf}
}


# Create a line in the script file to execute an action with output to log

# @param $* The line to execute
sf_dolog () {
    echo "$* >> \${logfile} 2>&1" >> ${sf}
}


# Create a line in the script file to execute an action with output to /dev/null

# @param $* The line to execute
sf_donull () {
    echo "$* >> /dev/null 2>&1" >> ${sf}
}


#------------------------------------------------------------------------------
#
#			      Argument handling
#
#------------------------------------------------------------------------------

# Save starting dir and basedir of the command for now. Allows us to reset
# directories to a known position later.
startdir=`pwd`
basedir=`dirname "$0"`

# Initial values of arguments
wdir=
sf=doit-tags.sh
suffix=

# Parse options
getopt_string=`getopt -n git-migrate.sh -o h -lworking-dir: -lscript: \
                      -lsuffix: -lhelp -s sh -- "$@"`
eval set -- "$getopt_string"

while true
do
    case $1 in

	--working-dir)
	    shift
	    wdir=$1
	    ;;

	--script)
	    shift
	    sf=$1
	    ;;

	--suffix)
	    shift
	    suffix=$1
	    ;;

	-h|--help)
	    echo "Usage: ./git-copy-tags.sh --working-dir <dirname>"
	    echo "                          [--suffix <suffix>]"
	    echo "                          [--script <filename>]"
	    echo "                          [-h | --help]"
	    exit 0
	    ;;

	--)
	    shift
	    break
	    ;;

	*)
	    echo "Internal error!"
	    echo $1
	    exit 1
	    ;;
    esac
    shift
done

if [ "x${wdir}" = "x" ]
then
    echo "ERROR: Must specify --working-dir"
    exit 1
fi


#------------------------------------------------------------------------------
#
#		  Set up working directory and repositories
#
#------------------------------------------------------------------------------

# Find the starting point for the working directory. Get out of the current
# repo.
while git status > /dev/null 2>&1
do
    cd ..
done

if ! cd ${wdir}
then
    echo "ERROR: Could not change to working directory ${wdir}"
    exit 1
fi

echo "Working directory is `pwd`"

# Check the script file is valid
rm -f ${sf}
if ! touch ${sf} > /dev/null 2>&1
then
    echo "ERROR: Could not write script file ${sf}"
    exit 1
fi

chmod ugo+x ${sf}
echo "Script file is ${sf}"

# Initialize the script file
cat > ${sf} <<EOF
#!/bin/sh

# Copyright (C) 2014 Embecosm Limited

# Contributor Jeremy Bennett <jeremy.bennett@embecosm.com>

# This file is a generated script for copying tags of a git branch from one
# repository to another.

# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3 of the License, or (at your option)
# any later version.

# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.

# You should have received a copy of the GNU General Public License along
# with this program.  If not, see <http://www.gnu.org/licenses/>.

# Sort out logfile
logfile=\${1-/tmp/log-tags}
echo "Logging to \${logfile}"

# Function to echo its argument to both console and logfile

# @param $* The message

logit () {
    echo \$*
    echo \$* >> \${logfile}
}

EOF


#------------------------------------------------------------------------------
#
#			Create script for copying tags
#
#------------------------------------------------------------------------------

# Find all the tags of interest.  The tools for tags manipulation are somewhat
# limited, so we need to list all the tags, then for each find its commit ID,
# then see if that commit ID is not in any upstream branch.

# Get all the tags
sf_do ""
sf_do "# Redo all the tags"
for t in `git tag -l`
do
    # Find its commit ID
    cid=`git log -1 ${t} | sed -n -e 's/^commit //p'`

    # Is it only in local branch(es)
    in_branches=

    if ! git branch -r --contains ${cid} | grep -q '\-upstream/'
    then
	b=`git branch -r --contains ${cid} \
               | sed -n -e 's#^ *old-local/##p' | head -1`
	new_cid=`map_commit ${cid} new-local/${b}`

	echo "Tag ${t} in branch $b"
	echo "  old commit ID ${cid}"
	echo "  new commit ID ${new_cid}"

	if [ "x${suffix}" = "x" ]
	then
	    sf_logit "" "Retagging ${t}"
	else
	    sf_logit "" "Retagging ${t} as ${t}${suffix}"
	fi
	sf_dolog "git tag -f ${t}${suffix} ${new_cid}"
	sf_dolog "git push new-local ${t}${suffix}"
    fi
done
