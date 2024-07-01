# Command-Line Interface

## Overview

This module contains the code for the bulk of the BV-BRC command-line interface scripts.  This includes a
variety of scripts for manipulating tab-delimited files as well as for querying and processing data in
the BV-BRC genome repository.

A complete description of the command-line interface (also known as the _CLI_, can be found [here](https://www.bv-brc.org/docs/cli_tutorial/index.html).
The installation procedure for the CLI can be found [here](https://github.com/BV-BRC/BV-BRC-CLI/releases).

Most of these scripts have a name of the form **p3-*script-name*** where *script-name* is a hyphenated description
of what the script does.


## About this module

This module is a component of the BV-BRC build system. It is designed to fit into the
`dev_container` infrastructure which manages development and production deployment of
the components of the BV-BRC. More documentation is available [here](https://github.com/BV-BRC/dev_container/tree/master/README.md).

These scripts make heavy use of the core BV-BRC interface code [here](https://github.com/BV-BRC/p3_core).  In particular, the [P3Utils.pm](https://github.com/BV-BRC/p3_core/blob/master/lib/P3Utils.pm)
module contains the definitions of derived fields and relationships in the BV-BRC database.
