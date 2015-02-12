CERN ALICE Software Installation, Setup and Utilities
=====================================================

This repository contains various small things for the
[ALICE Experiment](http://alice.cern.ch/) at [CERN](http://cern.ch).


## Automatic Installation and Environment scripts

Please [consult the guide](https://dberzano.github.io/alice/install-aliroot/).


## AutoDoc

Python script for steering the automatic documentation generation with
[Doxygen](http://www.doxygen.org/).

This script has two main usage modes.


### Generating doc for a specific Git branch

```bash
autodoc.py \
  --branch=<GitBranch> \
  --build-path=<LocalDocCache> \
  --git-clone=<PathToLocalGitClone> \
  --output-path=<PrefixForDocGeneration>
```

The Git branch will be updated from the configured remote, and documentation
will be stored under:

    <PrefixForDocGeneration>/<GitBranch>

Returns 0 on success, nonzero on failure.


### Generating doc for all new tags

```bash
autodoc.py \
  --new-tags \
  --git-clone=<PathToLocalGitClone> \
  --output-path=<PrefixForDocGeneration>
```

All new tags since the last update will have their documentation generated. No
cache directory is used, but temporary directories are created per tag, and they
are removed once the generation is done.

Output path:

    <PrefixForDocGeneration>/<Tagname>

Returns 0 on success, nonzero on failure.


### Common options

By default the command outputs a restricted number of messages on both stderr
and syslog.

Temporary build directory is deleted on success, and retained by default on
error.

* `--debug`: enables debug messages, and enables output from the external
  commands
* `--syslog-only`: only log on syslog, be completely quiet on stderr (useful for
  cron jobs)
* `--always-purge`: delete temporary directory also in case of error *(this
  never applies to `--build-path` which is always retained)*
