#!/usr/bin/env python3

#
# Syntax:
#   dnsaddalias [-l libdir][-f configfile][-d] <fqdn-alias> <fqdn-host> <viewname>
#

import sys
import os.path
import argparse


def doit (nm, fqdnh, fqdna, view):
    fqdnh = args.host
    fqdna = args.alias
    view = args.view

    # view is the same for host and alias
    (namea, domaina, iddoma, idviewa, a) = nm.get_alias (fqdna, view)

    #
    # Test if alias already exists
    #

    if a is None:
        #
        # Alias does not exist: fetch the host id
        #

        (nameh, domainh, iddomh, idviewh, h) = nm.get_host (fqdnh, view)

        #
        # Found host id. Use a POST request to create the alias
        #

        idhost = h ['idhost']
        data = {
                    'name': namea,
                    'iddom': iddoma,
                    'idview': idviewa,
                    'idhost': idhost,
                    'ttl': -1,
                }
        r = nm.api ('post', '/aliases', json=data)

    else:
        #
        # Alias already exists
        #
        nm.grmbl ("Alias '{}' already exists".format (fqdna, view))


def main ():
    parser = argparse.ArgumentParser (description='Netmagis add host')
    parser.add_argument ('-f', '--config-file', action='store',
                help='Config file location (default=~/.config/netmagisrc)')
    parser.add_argument ('-d', '--debug', action='store_true',
                help='Debug/trace requests')
    # warning: do not execute this script with "--help" while %...% are
    # not subtitued
    parser.add_argument ('-l', '--libdir', action='store',
                help='Library directory (default=%NMLIBDIR%)')
    parser.add_argument ('alias', help='Host FQDN')
    parser.add_argument ('host', help='Alias FQDN')
    parser.add_argument ('view', help='View name')

    args = parser.parse_args ()

    libdir = os.path.abspath (args.libdir or '%NMLIBDIR%')
    sys.path.append (libdir)
    from pynm.core import netmagis
    from pynm.decorator import catchdecorator

    nm = netmagis (args.config_file, trace=args.debug)

    fdoit = catchdecorator (args.debug) (doit)
    fdoit (nm, fqdnh, fqdna, view)
    sys.exit (0)


if __name__ == '__main__':
    main ()