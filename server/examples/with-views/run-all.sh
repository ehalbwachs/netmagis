#!/bin/sh

#
# This example script shows how to create a Netmagis database and
# import data.
# This example makes use of DNS views.
#

PATH=%BINDIR%:$PATH
export PATH

# Reverse zones are used only for their prologue (and not PTR RR).
# Thus, the same file can be loaded for internal and external views.
# Example.org and reverse IPv6 zone do not need to be in internal
# view, since name resolution will use public NS.

netmagis-dbcreate && \
    netmagis-dbimport -d group group.txt && \
    netmagis-dbimport -d domain domain.txt && \
    netmagis-dbimport -d view view.txt && \
    netmagis-dbimport -d network network.txt && \
    netmagis-dbimport -d zone internal example.com-int \
			zones/example.com-int example.com && \
    netmagis-dbimport -d zone internal 16.172.in-addr.arpa-int \
			zones/16.172.in-addr.arpa 172.16/16 && \
    netmagis-dbimport -d zone internal 100.51.198.in-addr.arpa-int \
			zones/100.51.198.in-addr.arpa 198.51.100/24 && \
    netmagis-dbimport -d zone external example.com-ext \
			zones/example.com-ext example.com && \
    netmagis-dbimport -d zone external example.org-ext \
			zones/example.org example.org && \
    netmagis-dbimport -d zone external 100.51.198.in-addr.arpa-ext \
			zones/100.51.198.in-addr.arpa 198.51.100/24 && \
    netmagis-dbimport -d zone external 4.3.2.1.8.b.d.0.1.0.0.2.ip6.arpa-ext \
			zones/4.3.2.1.8.b.d.0.1.0.0.2.ip6.arpa 2001:db8:1234::/48 && \
    netmagis-dbimport -d mailrelay external mailrelay.txt && \
    netmagis-dbimport -d mailrole external mailrole.txt && \
    echo "Succeeded"

exit 0
