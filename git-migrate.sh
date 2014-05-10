#!/bin/sh

# Copyright (C) 2014 Embecosm Limited

# Contributor Jeremy Bennett <jeremy.bennett@embecosm.com>

# This file is a script for migrating git histories between repositories.

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

#			SCRIPT TO MIGRATE GIT HISTORY
#			=============================

# Usage:

#     ./git-migrate.sh [--working-dir <dirname>]
#                      [--script <filename>]
#                      [--old-upstream <url>] [--new-upstream <url>]
#                      [--old-local <url>] [--new-local <url>]
#                      [--fetch | --no-fetch]
#                      --upstream-branch <name> --local-branch <name>
#                      [-h|--help]

# Development to date has been on a branch of the local repository, forked
# from a branch of the upstream repository. From time to time the local
# repository has been synced by merging from the branch on the upstream
# repository.

# The upstream repository has now been replaced. We wish to replay the history
# from the old local branch against this new upstream repository. This is done
# by reproducing the original fork, and subsequent sync merges with upstream,
# interspersing these with the local commits cherry picked from the old local
# branch.

# This script was prompted by the migration of binutils and GDB to a new
# unified binutils-gdb repository.

# The script can either create a new working directory with all the
# repositories as remotes, or can use an existing working directory. In the
# latter case the repos must have the names "old-upstream", "new-upstream",
# "old-local" and "new-local".

# --working-dir <dirname>

#     The working directory for the repositories, relative to the parent
#     directory of the repository containing this git-migrate.sh script. If it
#     does not exist it will be created. If not specified a directory will be
#     created and reported.

# --script <filename>

#     Name of the sript file to be generated. It will be created relative to
#     the working directory. If not specified, the name "doit.sh" will be used.

# --old-upstream <url>

#     Optional URL of the old upstream repo, which will be used for the remote
#     "old-upstream". Need not be specified if the remote already exists in
#     the working directory.

# --new-upstream <url>

#     Optional URL of the new upstream repo, which will be used for the remote
#     "new-upstream". Need not be specified if the remote already exists in
#     the working directory.

# --old-local <url>

#     Optional URL of the old local repo, which will be used for the remote
#     "old-local". Need not be specified if the remote already exists in
#     the working directory.

# --new-local <url>

#     Optional URL of the new local repo, which will be used for the remote
#     "new-local". Need not be specified if the remote already exists in
#     the working directory.

# --fetch
# --no-fetch

#     Turn on or off whether to fetch the repositories. Default --fetch

# --upstream-branch <name>

#     The upstream branch on which we are based.

# --local-branch <name>

#     The local branch we are recreating.

# --help
# -h


#------------------------------------------------------------------------------
#
#			       Useful functions
#
#------------------------------------------------------------------------------

# Add a remote repository

# If the remote already exists, update its URL. If it doesn't exist create
# it.  In the latter case the URL must exist

# @param $1  Name of the remote
# @param $2  URL of the repo
add_repo () {
    remote=$1
    url=$2
    echo -n "  ${remote}..."

    if git remote | grep -q "${remote}"
    then
	# Already exists
	if [ "x${url}" != "x" ]
	then
	    if git remote set-url ${remote} ${url}
	    then
		echo " already exists: URL updated"
	    else
		echo
		echo "ERROR: Failed to set URL ${url} for existing remote."
		exit 1
	    fi
	else
	    echo " already exists"
	fi
    else
	if [ "x${url}" = "x" ]
	then
	    echo
	    echo "ERROR: No URL specified for remote repository."
	    exit 1
	elif git remote add ${remote} ${url}
	then
	    echo " added"
	else
	    echo
	    echo "ERROR: Failed to add remote repository."
	    exit 1
	fi
    fi
}


# Fetch a repository

# @param $1  The repo to fetch
fetch_repo () {
    repo=$1
    echo -n "  ${repo}..."
    if git fetch -p -q ${repo}
    then
	echo " fetched"
    else
	echo
	echo "ERROR: Failed to fetch old upstream git repository"
	exit 1
    fi
}


# Check a branch is in a remote repository

# @param $1  Remote to check
# @param $2  Branch name
check_in_repo () {
    remote=$1
    branch=$2

    echo -n "  ${branch} in ${remote} repository..."
    if git log -1 ${remote}/${branch} > /dev/null 2>&1
    then
	echo " found"
    else
	echo
	echo "ERROR: Branch ${branch} not in ${remote} repository."
	exit 1
    fi
}


# Check a branch is not in a remote repository

# @param $1  Remote to check
# @param $2  Branch name
check_not_in_repo () {
    remote=$1
    branch=$2

    echo -n "  ${branch} not in ${remote} repository..."
    if ! git log -1 ${remote}/${branch} > /dev/null 2>&1
    then
	echo " not found"
    else
	echo
	echo "ERROR: Branch ${branch} already in ${remote} repository."
	exit 1
    fi
}


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
	      -e 's/^\([^:]*[012][0-9]:[0-5][0-9]\):[0-5][0-9]\(.*$\)/\1:00\2/'`
    git log --date=iso --reverse --since "${ds}" ${new_repo} \
	| sed -n -e 's/^commit //p' | head -1
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


# Force a cherry pick

# For any conflicts we just take the one we want from the cherry-pick.

# @param $1 The commit ID to use
force_cherry_pick () {
    cid=$1

    author=`git log -1 ${cid} | sed -n -e 's/^Author: //p'`
    adate=`git log -1 ${cid} | sed -n -e 's/^Date: //p'`
    sf_do    ""
    sf_do    "# Cherry pick ${cid}"
    sf_logit "" "git cherry-pick ${cid}"
    sf_dolog "if ! git cherry-pick ${cid}"
    sf_do    "then"
    sf_do    "    # Fix up both added/modified"
    sf_do    "    for f in \`git status \\"
    sf_do    "        | sed -n -e 's/^#.*both [adfimo]*ed:[[:space:]]*//p'\`"
    sf_do    "    do"
    sf_logit "        " "git checkout ${cid} \${f}"
    sf_dolog "        git checkout ${cid} \${f}"
    sf_logit "        " "git add \${f}"
    sf_dolog "        git add \${f}"
    sf_do    "    done"
    sf_do    "    # Fix up added by us (what about added by them?)"
    sf_do    "    for f in \`git status \\"
    sf_do    "        | sed -n -e 's/^#.*added by us:[[:space:]]*//p'\`"
    sf_do    "    do"
    sf_logit "        " "  git checkout ${cid} \${f}"
    sf_dolog "        git checkout ${cid} \${f}"
    sf_logit "        " "  git add \${f}"
    sf_dolog "        git add \${f}"
    sf_do    "    done"
    sf_do    "    # Fix up deleted by us (what about deleted by them?)"
    sf_do    "    for f in \`git status \\"
    sf_do    "        | sed -n -e 's/^#.*deleted by us:[[:space:]]*//p'\`"
    sf_do    "    do"
    sf_logit "        " "  git rm \${f}"
    sf_dolog "        git rm \${f}"
    sf_do    "    done"
    sf_do    "fi"
    sf_do    "# Commit with fixups"
    sf_logit "" "Commit: author \\\"${author}\\\", date \\\"${adate}\\\""
    sf_do    "if ! git commit --allow-empty --allow-empty-message --no-edit \\"
    sf_dolog "                --author \"${author}\" --date \"${adate}\""
    sf_do    "then"
    sf_logit "" "    Commit of fixed up cherry-pick failed: aborting"
    sf_do    "    exit 1"
    sf_do    "fi"
}

#------------------------------------------------------------------------------
#
#			      Argument handling
#
#------------------------------------------------------------------------------

# Initial values of arguments
wdir=gm-wd-$$
sf=doit.sh
old_upstream=
new_upstream=
old_local=
new_local=
fetchit=--fetch
upstream_branch=
local_branch=

# Parse options
getopt_string=`getopt -n git-migrate.sh -o h -lworking-dir: -lscript: \
                      -lold-upstream: -lnew-upstream: -lold-local: \
                      -lnew-local: -lfetch -lno-fetch -lupstream-branch: \
                      -llocal-branch: -lhelp -s sh -- "$@"`
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

	--old-upstream)
	    shift
	    old_upstream=$1
	    ;;

	--new-upstream)
	    shift
	    new_upstream=$1
	    ;;

	--old-local)
	    shift
	    old_local=$1
	    ;;

	--new-local)
	    shift
	    new_local=$1
	    ;;
	--fetch|--no-fetch)
	    fetchit=$1
	    ;;

	--upstream-branch)
	    shift
	    upstream_branch=$1
	    ;;

	--local-branch)
	    shift
	    local_branch=$1
	    ;;

	-h|--help)
	    echo "Usage: ./git-migrate.sh [--working-dir <dirname>]"
	    echo "                        [--script <filename>]"
	    echo "                        [--old-upstream <url>]"
	    echo "                        [--new-upstream <url>]"
            echo "                        [--old-local <url>]"
	    echo "                        [--new-local <url>]"
	    echo "                        [--fetch | --no-fetch]"
	    echo "                        --upstream-branch <name>"
	    echo "                        --local-branch <name>"
	    echo "                        [-h | --help]"
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


#------------------------------------------------------------------------------
#
#		  Set up working directory and repositories
#
#------------------------------------------------------------------------------

# Create a working directory if necessary. First get out of the current repo.
while git status > /dev/null 2>&1
do
    cd ..
done

if ! mkdir -p ${wdir}
then
    echo "ERROR: Could not create working directory ${wdir}"
    exit 1
fi

cd ${wdir}

# This does nothing if we are already initialized
if ! git init -q
then
    echo "ERROR: Failed to initialize working directory"
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

chmod ugo+x doit.sh
echo "Script file is ${sf}"

# Initialize the script file
cat > ${sf} <<EOF
#!/bin/sh

# Copyright (C) 2014 Embecosm Limited

# Contributor Jeremy Bennett <jeremy.bennett@embecosm.com>

# This file is a generated script for migrating a git branch with its history
# between repositories.

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
logfile=\${1-/tmp/log}
echo "Logging to ${logfile}"

# Function to echo its argument to both console and logfile

# @param $* The message

logit () {
    echo \$*
    echo \$* >> \${logfile}
}

EOF

# Add remotes
echo "Adding git remote repositories..."

add_repo "old-upstream" "${old_upstream}"
add_repo "new-upstream" "${new_upstream}"
add_repo "old-local" "${old_local}"
add_repo "new-local" "${new_local}"

# Optionally Fetch remotes

if [ "x${fetchit}" = "x--fetch" ]
then
    echo "Fetching git repositories..."

    fetch_repo old-upstream
    fetch_repo new-upstream
    fetch_repo old-local
    fetch_repo new-local
fi

# Sanity check of branches

echo "Sanity checking branches..."

check_in_repo old-upstream ${upstream_branch}
check_in_repo new-upstream ${upstream_branch}
check_in_repo old-local ${local_branch}
check_not_in_repo new-local ${local_branch}


#------------------------------------------------------------------------------
#
#				Create script
#
#------------------------------------------------------------------------------

# Find the starting point where we first forked the old repo. This will be the
# commit before the first commit in the local branch that is not also in the
# upstream branch.
cfork_old=`git log old-local/${local_branch} ^old-upstream/${upstream_branch} \
            | sed -n -e '/^commit /s/^commit //p' | tail -1`
cfork_old=`git log --topo-order -1 ${cfork_old}~1 \
               | sed -n -e '/^commit /s/^commit //p'`
cfork_new=`map_commit ${cfork_old} new-upstream/${upstream_branch}`
echo "Initial fork of ${local_branch} from ${cfork_new}"
sf_do    "# Fork the initial branch"
sf_logit "" "Forking ${local_branch} at ${cfork_new}"
sf_dolog "git checkout -b ${local_branch} ${cfork_new}"

# Find all the merges from the upstream into the local branch. We find all the
# merges that are only in the local branch, and then select those where the
# source is in the upstream repo. The merges have a line of the form:

#     Merge: <commit1> <commit2>

# <commit1> is the merge point in the current branch. We look for all the
# merges where <commit2> is in the upstream repo. Before we replay that merge
# we'll need to cherry-pick all the non-merge commits since the previous
# upstream merge up to <commit1>.

# This whole exercise needs to be done in reverse order.

prev_merge_old=${cfork_old}

for l in `git log --topo-order --reverse --merges old-local/${local_branch} \
                           ^old-upstream/${upstream_branch} \
              | grep 'Merge: [0-9a-f]* [0-9a-f]*' \
              | sed -e 's/Merge: //' -e 's/ /-/g'`
do
    c1=`echo $l | sed -e 's/-[0-9a-f]*$//'`
    c2=`echo $l | sed -e 's/^[0-9a-f]*-//'`
    if git log old-upstream/${upstream_branch} | grep -q "commit ${c2}"
    then
	sf_logit "" ""
	sf_logit "" "Cherry picking ${prev_merge_old}..${c1}"
	# Find all the cherry picks to do. When the branching is complex, we
	# have no guarantee that these are in the correct order (although it
	# is quite possible they are). So we will need to patch things by
	# brute force when the go wrong.
	echo -n "Cherry picking commits..."
	count=0
	for cid in `git log --reverse --no-merges \
                            ${prev_merge_old}..${c1} \
	                | sed -n -e '/^commit/s/^commit//p'`
	do
	    force_cherry_pick ${cid}
	    count=$(( count + 1 ))
	done
	echo " ${count} picked"

	# Now do the merge
	prev_merge_old=`git log --merges \
                                old-local/${local_branch} \
                            | sed -n -e "0,/Merge: ${c1} ${c2}/p" \
                            | sed -n -e 's/^commit //p' | tail -1`
	author="`git log -1 ${prev_merge_old} | sed -n -e 's/^Author: //p'`"
	adate="`git log -1 ${prev_merge_old} | sed -n -e 's/^Date: //p'`"

	# The merge will almost certainly have picked up conflicts
	echo "Merge from ${c2}"
	sf_do    ""
	sf_do    "# Merge from upstream"
	sf_logit "" ""
	sf_logit "" "git merge --no-commit ${c2}"
	sf_do    "for f in \`git merge --no-commit ${c2} \\"
	sf_do    "    | sed -n -e '/^CONFLICT/s/^CONFLICT .* in //p'\`"
	sf_do    "do"
	sf_logit "    " "  git checkout ${prev_merge_old} \${f}"
	sf_dolog "    git checkout ${prev_merge_old} \${f}"
	sf_logit "    " "  git add \${f}"
	sf_dolog "    git add \${f}"
	sf_do    "done"
	sf_logit "" "Commit: author \\\"${author}\\\", date \\\"${adate}\\\""
	sf_do    "git commit --allow-empty --allow-empty-message --no-edit \\"
	sf_dolog "           --author \"${author}\" --date \"${adate}\""
    fi
done

# Do all the commits since the final merge
sf_do    ""
sf_do    "# Cherry pick all the commits since the final merge (or initial"
sf_do    "# fork if no merges)"
sf_logit "" ""
sf_logit "" "Cherry picking ${prev_merge_old}..old-local/${local_branch}"

# As before may need brute force here.
echo -n "Cherry picking commits..."
count=0
for cid in `git log --reverse --no-merges \
                    ${prev_merge_old}..old-local/${local_branch} \
	        | sed -n -e '/^commit/s/^commit//p'`
do
    force_cherry_pick ${cid}
    count=$(( count + 1 ))
done
echo " ${count} picked"

# Finally tidy up any outstanding mess
echo "Final tidy up..."
sf_do    ""
sf_do    "# Final tidy up"
sf_logit "" ""
sf_logit "" "git diff --name-only --diff-filter=M old-local/${local_branch}"
sf_do    "for f in \`git diff --name-only --diff-filter=M \\"
sf_do    "    old-local/${local_branch}\`"
sf_do    "do"
sf_dolog "    git checkout old-local/${local_branch} \${f}"
sf_do    "done"
sf_dolog "git commit \\"
sf_dolog "    -m \"Final tidy up of files from transfer to new repository\""

# Now propose the push
sf_logit "" ""
sf_logit "" "Now run:"
sf_logit "" "  git push -u new-local ${local_branch}"

# Finally tell people how to clear up.
echo "If it all goes horribly wrong, clean up the repo with the following:"
echo "  git reset --hard"
echo "  git checkout HEAD^"
echo "  git branch -D ${local_branch}"

