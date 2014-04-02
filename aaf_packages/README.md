Generating AAF PARfiles for CernVM-FS
=====================================

**Rationale:** creating PARfiles for enabling AliRoot on ALICE
Analysis Facilities and export them on CernVM-FS, so that they are
automatically available everywhere.

There are separate instructions for

* [ALICE CernVM-FS administrators](#alice-cernvm-fs-admins)
* [AAF admins](#aaf-admins)
* [AAF users](#aaf-users)


ALICE CernVM-FS admins
----------------------

### Once for all: setup the CernVM-FS server

Git clone the repository:

```bash
cd ~
git clone https://github.com/dberzano/cern-alice-setup.git
```

The script will be available in `~/cern-alice-setup/aaf_packages`.

We will assume that the global AAF packages directory will be
`/cvmfs/alice.cern.ch/etc/aaf_packages`.


### At each AliRoot release: update the list of packages

When a new AliRoot version has been released:

```bash
cd ~/cern-alice-setup/aaf_packages
./gen_proof_packages.sh --proof-packages-dir /cvmfs/alice.cern.ch/etc/aaf_packages
```

Packages for pre-existing AliRoot versions will not be created: only
packages for new AliRoot versions are generated.

The destination directory is assumed to be exported via CernVM-FS.

**Note:** this procedure can be done automatically.


AAF admins
----------

### Once for all: PROOF setup for all nodes

The local list of AliRoot versions will be automatically updated, as
it will be available from CernVM-FS.

You still need to do some modification in your PROOF configuration,
*i.e.* the `prf-main.cf` file, notably:

```
xpd.putrc Proof.GlobalPackageDirs /cvmfs/alice.cern.ch/etc/aaf_packages
xpd.exportpath /cvmfs/alice.cern.ch/etc/aaf_packages
```


AAF users
---------

### Listing the available versions

```c++
gProof->ShowPackages();
```


### Enabling a certain AliRoot version

```c++
gProof->EnablePackage( "VO_ALICE@AliRoot::vAN-20140331" );
```

**Note:** don't forget the `VO_ALICE@AliRoot::` prefix.
