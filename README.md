# General scripts used by the Open MPI infrastructure.

A place for all the various cross-project scripts that used to live in
the main ompi/ tree or, worse, in every source tree, each with its own
bugs.  Initially, this is mainly nightly build scripts.

## nightly-tarball/

Scripts for building the nightly tarballs for ompi, pmix, and hwloc.
The scripts are designed to push to S3 (fronted by the CloudFront
download.open-mpi.org URL), but can also scp to the web tree for
www.open-mpi.org until the web bits are updated.

## migration/

Scripts for migrating bits of Open MPI's infrastructure from IU or
HostGator to AWS.
