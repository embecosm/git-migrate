# Git Tree Migration Tool

This tool was prompted by the migration of binutils and GDB, to a single
unified git repository. Prior to this, development had been in CVS, but many
users had relied on separate git mirrors of those repositories.

The challenge is to take developments on the two separate repositories and
replay them onto the new repository, preserving the history as far as is
possible.

## Scenario

The assumption is that the user has carried out private development on one or
more branches forked from branches of the upstream repository. For example a
user might have forked the upstream **binutils** branch *binutils-2_21-branch*
for their own processor specific development as the branch
*myproc_binutils-2_21*.

We now want to take that fork of the old **binutils** repository, and recreate
as a fork of the *binutils-2_21-branch* of the new **binutils-gdb**
repository.

To do this we must fork from the equivalent commit in the new **binutils-gdb**
repository, then reply the commits of the old *myproc_binutils-2_21* branch
onto this fork.

We find that equivalent commit by looking at the author date stamp, since
being a separate repo the SHA1 commit IDs will be different.

### Caveats and workarounds ###

This approach only works with a fairly simple development history. If there
have been sub-branches and merges during development, working out the correct
sequence to reply the commits and merges is very complex, so we don't try.

Instead if a cherry-pick causes conflicts, we checkout the known good version
of any conflicting file and then commit this as a resolution. At the top
level the history will show the correct relationship between upstream and
local branches. But any detailed history of sub-branches will be lost.

## Usage

    ./git-migrate.sh [--working-dir <dirname>]
                     [--script <filename>]
                     [--old-upstream <url>] [--new-upstream <url>]
                     [--old-local <url>] [--new-local <url>]
                     [--fetch | --no-fetch]
                     --upstream-branch <name> --local-branch <name>
                     [-h|--help]

The assumption is that there is an old upstream repository (for example the
SourceForge binutils git mirror) and an old local repository with branches
forked from the upstream repository.

The objective is to move to a new upstream repository (for example the
SourceForge binutils-gdb git repository) and a new local repository with
branches recreated as forks from the upstream repository.

The script can either create a new working directory with all the
repositories as remotes, or can use an existing working directory. In the
latter case the repos must have the names "old-upstream", "new-upstream",
"old-local" and "new-local".

* `--working-dir` _dirname_

    The working directory for the repositories, relative to the parent
    directory of the repository containing this _git-migrate.sh_ script. If it
    does not exist it will be created. If not specified a directory will be
    created and reported.

* `--script` _filename_

    Name of the script file to be generated. It will be created relative to
    the working directory. If not specified, the name `doit.sh` will be used.

* `--old-upstream` _url_

    Optional URL of the old upstream repo, which will be used for the remote
    `old-upstream`. Need not be specified if the remote already exists in
    the working directory.

* `--new-upstream` _url_

    Optional URL of the new upstream repo, which will be used for the remote
    `new-upstream`. Need not be specified if the remote already exists in
    the working directory.

* `--old-local` _url_

    Optional URL of the old local repo, which will be used for the remote
    `old-local`. Need not be specified if the remote already exists in
    the working directory.

* `--new-local` _url_

    Optional URL of the new local repo, which will be used for the remote
    `new-local`. Need not be specified if the remote already exists in
    the working directory.

* `--fetch`
* `--no-fetch`

    Turn on or off whether to fetch the repositories. Default `--fetch`

* `--upstream-branch` _name_

    The upstream branch on which we are based.

* `--local-branch` _name_

    The local branch we are recreating.

* `--help`
* `-h`

    Report on usage.

## Example

    ./git-migrate.sh --working-dir gm-wd-gdb \
                     --old-upstream git://sourceware.org/git/gdb.git \
                     --new-upstream git://sourceware.org/git/binutils-gdb.git \
                     --old-local git@github.com:openrisc/or1k-src.git \
                     --new-local git@github.com:openrisc/or1k-binutils-gdb.git \
                     --upstream-branch master \
                     --local-branch upstream-rebase-20130930

The script to transfer the branches generated will be called `doit.sh` in the
gm-wd-gdb. It takes an optional argument, the name of a log file (default
/tmp/log).

## Transferring tags

Once all the branches are transferred, it is necessary to transfer tags. A
separate script is provided for this, `git-copy-tags.sh`:

    ./git-copy-tags.sh [--working-dir <dirname>]
                       [--script <filename>]
                       [--suffix <suffix>]
                       [-h|--help]

This will copy all the tags that exist only in the `old-local` repository to the
equivalent location in the `new-local` repository.

* `--working-dir` _dirname_

    The working directory for the repositories, relative to the parent
    directory of the repository containing this _git-migrate.sh_ script. If it
    does not exist it will be created. If not specified a directory will be
    created and reported.

* `--script` _filename_

    Name of the script file to be generated. It will be created relative to
    the working directory. If not specified, the name `doit-tags.sh` will be
    used.

* `--suffix` _suffix_

    It may be necessary to rename tags, to avoid clashes (for example
    combining binutils and gdb into binutils-gdb may lead to duplicate
    tags. This argument is used to add a suffix to the new tab name.

* `--help`
* `-h`

    Report on usage.

Running the script `doit-tags.sh` will then transfer all the tags. It takes an
optional single argument, the name of a logfile (default `/tmp.log-tags`).

When bringing together two repositories into one (for example gdb and binutils
into binutils-gdb) it is possible that there may be tags which cause a
clash. To get round this, the `--suffix` argument allows a suffix to be
appended to the tag name.

So if the branches from binutils had been migrated in a directory `gm-wd-binutils`
and the branches from GDB in a directory `gm-wd-gdb`, we might use the following
two commands to transfer all the tags:

    ./git-copy-tags.sh --working-dir gm-wd-binutils
    ./git-copy-tags.sh --working-dir gm-wd-gdb --suffix "-gdb"
