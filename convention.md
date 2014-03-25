Supported programs
------------------

* ROOT
* Geant 3
* AliRoot
* FastJet


Directory structure
-------------------

Assumptions:

* the program has a Git repository
* the program can build out of source

Directory structure follows:

    \-+- program
      |
      |--- git
      |
      |-+- version_1
      | |--- src
      | \-+- build
      |   |--- arch_1
      |   \--- arch_2
      |
      \-+- version_2
        |--- src
        \-+- build
          |--- arch_1
          \--- arch_2

* The `program/git` directory is the main Git clone.

* Each `program/version/src` directory is a clone of the main Git
  clone made with `git-new-workdir`.

* Each `program/version/build/arch` is the build directory for a
  certain architecture and version.

The advantage of maintaining such a structure is that a single
directory tree can be maintained for building the software for
several operating systems and architectures. In particular, a single
source directory is sufficient for several platforms.


Architecture directory naming convention
----------------------------------------

The architecture directory name contains the following information:

* operating system's name: *darwin, linux...*
* architecture: *x86_64, i386...*
* compiler name: *gcc, clang...*
* compiler short version (only major and minor, without dots):
  *42, 34...*

Example of a valid string on OSX:

    darwin-x86_64-clang34

On Linux:

    linux-x86_64-gcc47
