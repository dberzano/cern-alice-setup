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
openstack-hlt-manage  [--for-real] [--no-colors] [--nvms] [enable|disable|status] [node1 [node2...]]
```

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
openstack-hlt-manage [--for-real] enable [node1 [node2 [node3...]]]
```

Each node in the list is enabled to run virtual machines. This means that:

* OpenStack services are explicitly started on each node in the list, and
* the OpenStack central service is told to use those nodes.

Node names must be specified in the full form, *i.e.* with the domain name
appended. It is the same domain name displayed by the
[status command](#querying-the-status).

Errors enabling a single node are non-fatal: the program will continue with the
other nodes, and report errors accordingly.

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

**Note:** the command runs in **dry-run** mode by default, meaning that it only
simulates what would do. Prepend `--for-real` to effectively execute it.

Sample output:

```console
$> openstack-hlt-manage --no-colors disable cn43.internal cn44.internal
[ OK ] Disabling hypervisor cn43.internal
[ OK ] Deleting VM e8cbe323-7c50-446a-841a-4460080f911f on hypervisor cn43.internal
[ OK ] Shutting down OpenStack daemons on cn43.internal
[ OK ] Disabling hypervisor cn44.internal
[ OK ] Deleting VM 36eba1b0-c060-4046-8118-7a44bfca332c on hypervisor cn44.internal
[ OK ] Deleting VM db0ea693-150f-455b-af76-df88408c8aaa on hypervisor cn44.internal
[ OK ] Shutting down OpenStack daemons on cn44.internal

All commands executed successfully.
```

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
