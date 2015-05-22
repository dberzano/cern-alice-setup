ALICE HLT Cloud management
==========================

This repository contains instructions and utilities to control the Cloud running
on top of the [ALICE](http://alice.cern.ch/) HLT Cluster.

## Adding and removing nodes to the Cloud

The HLT Cloud is meant for opportunistic computing. HLT operators might, at any
time, add and remove nodes to the Cloud.

Such operations are facilitated by the control script `openstack-hlt-manage`.

To use the script, one must log in to the OpenStack head node, and enter the
administrative environment first:

```bash
openstack-enter admin
```

> The administrative environment contains environment variables needed to run
> the OpenStack commands. An `[OpenStack]` banner is prepended to the prompt,
> and the current user and tenant are displayed. This is a normal shell: you can
> exit it by typing `exit`.

Syntax:

```
openstack-hlt-manage  [--for-real] [--no-colors] [--line-output] [--parallel] [--ssh-config <file>] [--nvms] [enable|disable|status] [node1 [node2...]]
```

**Note:** if using the `--parallel` option, nodes list can also be specified in
the format supported by the `-w` option of `pdsh` (see
the [manpage](http://linux.die.net/man/1/pdsh)).

### Querying the status

```
openstack-hlt-manage [--nvms] status
```

The optional `--nvms` parameter also queries the number of VMs present on each
hypervisor. It is disabled by default as it slows down a bit the operations.

Sample output:

```
+----------------------+-----------+--------+------+
| Hypervisor           | Runs VMs? | Alive? | #VMs |
+----------------------+-----------+--------+------+
| cn43.internal        |    yes    | alive  |    1 |
| cn44.internal        |    yes    | alive  |    2 |
| cn45.internal        |    yes    | alive  |    2 |
| cn46.internal        |    yes    | alive  |    2 |
| cn47.internal        |    yes    | alive  |    1 |
+----------------------+-----------+--------+------+
```

For each hypervisor you will see:

* if it is **enabled** to run virtual machines,
* if the OpenStack daemons running on it are **responding**, and
* *(optionally)* the **number** of deployed virtual machines

A *disabled* hypervisor should report:

* **Runs VMs? no**, meaning that OpenStack will not try to schedule VMs on it
* **Alive? dead**, meaning that no OpenStack daemon is running on it


### Adding a node to the Cloud

Adding a node to the HLT Cloud means allowing it to run virtual machines.
Virtual machines are then usually deployed automatically using
[elastiq](https://github.com/dberzano/elastiq).

Syntax:

```
openstack-hlt-manage [--for-real] [--parallel] enable [node1 [node2 [node3...]]]
```

Each node in the list is enabled to run virtual machines. This means that:

* OpenStack services are explicitly started on each node in the list, and
* the OpenStack central service is told to use those nodes.

Node names must be specified in the full form, *i.e.* with the domain name
appended. It is the same domain name displayed by the
[status command](#querying-the-status).

Errors enabling a single node are non-fatal: the program will continue with the
other nodes, and report errors accordingly.

It is convenient to pass `--parallel` to enable hosts in parallel: this is way
faster when running on many hosts at the same time.

**Note:** the command runs in **dry-run** mode by default, meaning that it only
simulates what would do. Prepend `--for-real` to effectively execute it.

Sample output:

```console
$> openstack-hlt-manage --for-real enable cn43.internal cn44.internal
[ OK ] Enabling hypervisor cn43.internal
[ OK ] Starting OpenStack daemons on cn43.internal
[ OK ] Enabling hypervisor cn44.internal
[ OK ] Starting OpenStack daemons on cn44.internal

All commands executed successfully.
```

### Removing a node from the Cloud

Removing a node from the HLT Cloud means:

* disabling the node from the central OpenStack manager,
* deleting (abruptly) virtual machines currently running on the same nodes,
* shutting down all OpenStack services on the node.

This means that when a node is disabled, no OpenStack service runs on it.

Those two operations normally involve a series of OpenStack commands, but they
are simplified by the control script:

```
openstack-hlt-manage [--for-real] disable [node1 [node2 [node3...]]]
```

As for the `enable` command, errors removing one node are non-fatal and the
program will continue to disable the other nodes.

It is convenient to pass `--parallel` to disable hosts in parallel: this is way
faster when running on many hosts at the same time, expecially if you consider
that the command waits for virtual machines to disappear after issuing the kill
command.

**Note:** the command runs in **dry-run** mode by default, meaning that it only
simulates what would do. Prepend `--for-real` to effectively execute it.

Sample output:

```console
$> openstack-hlt-manage --no-colors disable cn47.internal
[ OK ] Disabling hypervisor cn47.internal
[ OK ] Starting OpenStack daemons on cn47.internal
[ OK ] Deleting VM d9d0c131-fd60-4ecb-97cf-c0e46901edf1 on hypervisor cn47.internal
[ OK ] Deleting VM 380a44d5-71cd-4254-a3ae-4f9e716ec523 on hypervisor cn47.internal
Waiting max 3600 s for VMs to be deleted on cn47.internal...2 running (3600 s left)...all gone in 1s!
[ OK ] Shutting down OpenStack daemons on cn47.internal

All commands executed successfully.
```

From the output, you can see that OpenStack daemons are *started* before
deleting virtual machines, and subsequently *stopped*. This is counterintuitive:
we must make sure services are running before issuing delete commands, otherwise
deletion will fail. In any case, since we have *disabled* the host in the first
place, no VM will be scheduled there even if we temporarily start the daemons.

Please note that OpenStack takes care of some cleanup (disk- and network-wise)
after issuing the delete command: this takes some time (usually less than one
minute), therefore issuing:

```bash
openstack-hlt-manage --nvms status
```

right after running `disable` may show a number of virtual machines greater than
zero for the disabled hosts for a short while. If you reissue the command after
some time, the number will correctly display zero.

### Common parameters

Switches must come before any command. The following switches can be used with
any command.

* `--no-colors`: suppresses any color from the output. Useful if running inside
  a `watch` or from a terminal that does not support special escape sequences.
* `--line-output`: all messages are line-buffered, *i.e.* they end with a new
  line. This is used automatically by the `--parallel` option for its subworkers
  to avoid mangled output.
* `--parallel`: use `pdsh` (with the *exec* RCMD module) under the hood to
  execute enable and disable operations for the given hosts in parallel. This
  mechanism makes enabling and disabling many nodes at the same time very fast.
* `--ssh-config <file>`: for enabling and disabling OpenStack daemons, ssh is
  executed towards target nodes. In order to configure SSH connection options
  (for instance, the private key to use) a SSH configuration file must be
  provided. Omit this option on the production nodes: the correct configuration
  will be picked automatically. If you specify a configuration file manually you
  must use an absolute path.
