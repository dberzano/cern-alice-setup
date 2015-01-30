Generating AAF PARfiles for CernVM-FS
=====================================

**Rationale:** creating PARfiles for enabling AliRoot on ALICE Analysis
Facilities and export them on CernVM-FS, so that they are automatically
available everywhere.

There are separate instructions for

* [ALICE CernVM-FS administrators](#alice-cernvm-fs-admins)
* [AAF admins](#aaf-admins)
* [AAF users](#aaf-users)
* [VAF](#vaf)


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
`/cvmfs/alice.cern.ch/x86_64-2.6-gnu-4.1.2/Packages/AAF/PAR`.


### At each AliRoot Core and AliPhysics release: update the list of packages

When a new AliRoot Core or AliPhysics version is released:

```bash
~/cern-alice-setup/aaf_packages/gen_proof_packages.sh --proof-packages-dir /cvmfs/alice.cern.ch/x86_64-2.6-gnu-4.1.2/Packages/AAF/PAR
```

**Note:** the above command works from any working directory.

Packages for pre-existing AliRoot Core and AliPhysics versions will not be
recreated: only packages for new AliRoot versions are generated.

By default the above command shows only the newly created packages. To output
the list of skipped packages, add the `--show-skipped` switch.

In a standard configuration, the destination directory is exported via CVMFS.

**Note:** this procedure can be done automatically.


AAF admins
----------

### Once for all: PROOF setup for all nodes

The local list of AliRoot versions will be automatically updated, as it will be
available from CernVM-FS.

You still need to do some modification in your PROOF configuration, *i.e.* the
`prf-main.cf` file, notably:

```
xpd.putrc Proof.GlobalPackageDirs /cvmfs/alice.cern.ch/x86_64-2.6-gnu-4.1.2/Packages/AAF/PAR
xpd.exportpath /cvmfs/alice.cern.ch/x86_64-2.6-gnu-4.1.2/Packages/AAF/PAR
```


AAF users
---------

### Listing the available versions

```c++
gProof->ShowPackages();
```


### Enabling a certain AliRoot Core or AliPhysics version

For AliRoot Core:

```c++
gProof->EnablePackage( "VO_ALICE@AliRoot::v5-06-02" );
```

For AliPhysics:

```c++
gProof->EnablePackage( "VO_ALICE@AliPhysics::vAN-20150129" );
```

**Note:** don't forget the `VO_ALICE@AliRoot::` or `VO_ALICE@AliPhysics::`
prefix, this is a common mistake.


VAF
---

Only one special PARfile is needed to enable AliRoot Core or AliPhysics on the
Virtual Analysis Facilities.

Loading this PARfile will enable either AliRoot Core or AliPhysics, depending
on the user's choice while entering the VAF environment. If AliPhysics is
available in the VAF environment, then it will also be enabled by this package.
If it is not available, only AliRoot Core will be enabled.

Generated PARs are compatible both with AAFs and VAFs.

To generate the single PARfile for VAFs:

```bash
~/cern-alice-setup/aaf_packages/gen_single_par.sh
```

A PARfile named `AliceVaf.par` will be generated. It can be copied in the user's
current working directory, then it must be **first uploaded** then enabled on
PROOF:

```c++
gProof->UploadPackage( "AliceVaf" );
gProof->EnablePackage( "AliceVaf" );
```

**Note:** on VAF the package name does not actually matter.


### Generate a single PARfile with a custom name

Instead of the default `AliRoot.par` you can run:

```bash
cd ~/cern-alice-setup/aaf_packages
./gen_single_par.sh MyParFileSpecialName
```

A PARfile named `MyParFileSpecialName.par` will be created in the current
directory.
