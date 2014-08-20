AliRoot repository split
========================

This directory contains utilities used to perform the splitting of the
AliRoot Git repository into:

 * a **core** repository
 * a **PWG** repository

The PWG repository retains the full history of the sole files under
PWG directories, and it is therefore much lighter.


fix-tags.sh
-----------

Run it under the AliRoot repository to fix "broken" tags. Broken tags
are either tags with unreadable info:

```console
$> git cat-file tag TRDdev.2.0
fatal: git cat-file TRDdev.2.0: bad file
```

or tags with no author (leftovers from CVS to SVN import):

```console
$> git cat-file tag ver0
...
```

Tags are fixed by deleting and recreating the existing ones, and an
author will automatically be assigned. Tags are also deleted from the
remote repository, and recreated (so **beware**).

Syntax:

```sh
fix-tags.sh [--fix]
```

Use `--fix` to explicitly make changes. Without it, "bad" tags will be
only listed and not amended.
