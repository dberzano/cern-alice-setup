Generating AAF PARfiles for CernVM-FS
=====================================

**Rationale:** creating PARfiles for enabling AliRoot on ALICE
Analysis Facilities and export them on CernVM-FS, so that they are
automatically available everywhere.


ALICE CernVM-FS admins
----------------------

#### Once-for-all: setup the CernVM-FS server

Git clone the repository:

    cd ~
    git clone https://github.com/dberzano/cern-alice-setup.git

The script will be available in:

    ~/cern-alice-setup/aaf_packages

We will assume that the global AAF packages directory will be:

    /cvmfs/alice.cern.ch/etc/aaf_packages


### At each AliRoot release: update the list of packages

When a new AliRoot version has been released:

    cd ~/cern-alice-setup/aaf_packages
    ./gen_proof_packages.sh --proof-packages-dir /cvmfs/alice.cern.ch/etc/aaf_packages

Packages for pre-existing AliRoot versions will not be created: only
packages for new AliRoot versions are generated.

The destination directory is assumed to be exported via CernVM-FS.


AAF admins
----------

### PROOF setup for all nodes

The local list of AliRoot versions will be automatically updated, as
it will be available from CernVM-FS.

You still need to do some modification in your PROOF configuration,
*i.e.* the `prf-main.cf` file, notably:

    xpd.putrc Proof.GlobalPackageDirs /cvmfs/alice.cern.ch/etc/aaf_packages
    xpd.exportpath /cvmfs/alice.cern.ch/etc/aaf_packages

In the very same file, you have to set a variable that packages will
use for determining the AliRoot path:

    xpd.putenv AF_ALIROOT_DIR_TEMPLATE=/cvmfs/alice.cern.ch/x86_64-2.6-gnu-4.1.2/Packages/AliRoot/<VERSION>

**Leave the** `<VERSION>` **as-is**: it will be substituted with the
AliRoot version once you load the package.


AAF users
---------

### Listing the available versions

    gProof->ShowPackages();


### Enabling a certain AliRoot version

    gProof->EnablePackage( "VO_ALICE@AliRoot::vAN-20140331" );

**Note:** don't forget the `VO_ALICE@AliRoot::` prefix.
