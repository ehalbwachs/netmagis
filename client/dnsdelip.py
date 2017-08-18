#!/usr/bin/env python3

#
# Syntax:
#   dnsdelip [-l libdir][-f configfile][-d] <ip> <viewname>
#

import sys
import os.path
import argparse
import ipaddress


def doit (nm, ip, view):
    try:
        addr = ipaddress.ip_address (ip)
    except:
        nm.grmbl ('{} is not a valid IP address'.format (ip))

    idview = nm.get_idview (view)
    if not idview:
        nm.grmbl ('Unknown view {}'.format (view))

    #
    # Test if IP address exists
    #

    query = {'addr': ip, 'view': view}
    r = nm.api ('get', '/hosts', params=query)

    j = r.json ()
    nr = len (j)
    if nr == 0:
        #
        # Address does not exist
        #
        msg = "Address '{}' does not exist in view {}"
        nm.grmbl (msg.format (ip, view))

    elif nr == 1:
        #
        # Adress exists. Fetch the full host record
        #

        idhost = j [0]['idhost']
        uri = '/hosts/' + str (idhost)

        r = nm.api ('get', uri)
        j = r.json ()

        #
        # Look for our specific address in the address list
        #

        j ['addr'] = [a for a in j ['addr'] if ipaddress.ip_address (a) != addr]

        if len (j ['addr']) == 0:
            #
            # Delete host
            #
            r = nm.api ('delete', uri)

        else:
            #
            # Modify host to delete just one of its addresses
            #
            r = nm.api ('put', uri, json=j)

    else:
        # this case should never happen
        msg = "Server error: address '{}' found more than once in view {}"
        nm.grmbl (msg.format (ip, view))


def main ():
    parser = argparse.ArgumentParser (description='Netmagis delete host')
    parser.add_argument ('-f', '--config-file', action='store',
                help='Config file location (default=~/.config/netmagisrc)')
    parser.add_argument ('-d', '--debug', action='store_true',
                help='Debug/trace requests')
    # warning: do not execute this script with "--help" while %...% are
    # not subtitued
    parser.add_argument ('-l', '--libdir', action='store',
                help='Library directory (default=%NMLIBDIR%)')
    parser.add_argument ('ip', help='IP (v4 or v6) address to delete')
    parser.add_argument ('view', help='View name')

    args = parser.parse_args ()

    libdir = os.path.abspath (args.libdir or '%NMLIBDIR%')
    sys.path.append (libdir)
    from pynm.core import netmagis
    from pynm.decorator import catchdecorator

    nm = netmagis (args.config_file, trace=args.debug)

    ip = args.ip
    view = args.view

    fdoit = catchdecorator (args.debug) (doit)
    fdoit (nm, ip, view)
    sys.exit (0)


if __name__ == '__main__':
    main ()