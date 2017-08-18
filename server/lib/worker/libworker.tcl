# package require Pgtcl
# package require nmjson
# package require rr

#
# Check that body is a JSON value, parse-it as a NMJson value,
# check this value against the spec (see nmjson::check-spec)
# and return the new NMJson value (with optional items substitued
# with default values)
#

proc get-body-json {parm} {
    set body [::scgi::get-body $parm "application/json"]
    try {
	set nmj [::nmjson::str2nmj $body]
    } on error msg {
	::scgi::serror 404 "Invalid JSON value"
    }
    return $nmj
}

proc check-body-json {parm spec} {
    set nmj [get-body-json $parm]
    lassign [::nmjson::check-spec $nmj $spec] res cdr
    if {! $res} then {
	# cdr is the error message
	::scgi::serror 404 "Invalid JSON value ($cdr)"
    }
    # cdr is the new (with default substitued) nmj
    return $cdr
}

#
# Checks if the selected views are authorized for this user
#
# Input:
#   - parameters:
#	- views : list of view ids given by the user
# Output:
#   - return value: empty string or error message
#
# History
#   2012/10/30 : pda/jean : design
#   2012/10/31 : pda/jean : use nmuser class
#

proc check-views {views} {
    set msg ""

    if {[llength $views] == 0} then {
	set msg [mc "No view selected"]

    } else {
	#
	# Check authorized views
	#

	set bad {}
	foreach id $views {
	    if {! [::n isallowedview $id]} then {
		set name [::n viewname $id]
		if {$name eq ""} then {
		    set name $id
		}
		lappend bad $name
	    }
	}

	if {[llength $bad]> 0} then {
	    set bad [join $bad ", "]
	    set msg [mc "You don't have access to these views: %s" $bad]
	}
    }

    return $msg
}

#
# Check host name syntax (first part of a FQDN) according to RFC 1035
#
# Input:
#   - parameters:
#	- name : name to test
# Output:
#   - return value: empty string or error message
#
# History
#   2002/04/11 : pda/jean : design
#   2010/11/29 : pda      : i18n
#

proc check-name-syntax {name} {
    # general case: a letter-or-digit at the beginning, a letter-or-digit
    # at the end (minus forbidden at the end) and letter-or-digit-or-minus
    # between.
    set re1 {[a-zA-Z0-9][-a-zA-Z0-9]*[a-zA-Z0-9]}
    # particular case: only one letter
    set re2 {[a-zA-Z0-9]}

    if {[regexp "^$re1$" $name] || [regexp "^$re2$" $name]} then {
	set msg ""
    } else {
	set msg [mc "Invalid name '%s'" $name]
    }

    return $msg
}

#
# Check (IPv4, IPv6, CIDR, MAC) address syntax
#
# Input:
#   - parameters:
#	- dbfd : database handle
#	- addr : address to test
#	- type : "inet", "cidr", "loosecidr", "macaddr", "inet4", "cidr4"
# Output:
#   - return value: empty string or error message
#
# Note :
#   - type "cidr" is strict, "host" bits must be 0 (i.e.: "1.1.1.0/24"
#	is valid, but not "1.1.1.1/24")
#   - type "loosecidr" accepts "host" bits set to 1
#
# History
#   2002/04/11 : pda/jean : design
#   2002/05/06 : pda/jean : add type cidr
#   2002/05/23 : pda/jean : accept simplified cidr (a.b/x)
#   2004/01/09 : pda/jean : add IPv6 et radical simplification
#   2004/10/08 : pda/jean : add inet4
#   2004/10/20 : jean     : forbid / for anything else than cidr type
#   2008/07/22 : pda      : add type loosecidr (accepts /)
#   2010/10/07 : pda      : add type cidr4
#

proc check-addr-syntax {dbfd addr type} {

    switch $type {
	inet4 {
	    set cast "inet"
	    set fam  4
	}
	cidr4 {
	    set cast "cidr"
	    set type "cidr"
	    set fam  4
	}
	loosecidr {
	    set cast "inet"
	    set fam ""
	}
	default {
	    set cast $type
	    set fam ""
	    set msg "?"
	}
    }
    set qaddr [pg_quote $addr]
    set sql "SELECT $cast\($qaddr\) ;"
    set r ""
    if {[$dbfd exec $sql msg]} then {
	if {$fam ne ""} then {
	    $dbfd exec "SELECT family ($qaddr) AS fam" tab {
		if {$tab(fam) != $fam} then {
		    set r [mc {'%1$s' is not a valid IPv%2$s address} $addr $fam]
		}
	    }
	}
	if {! ($type eq "cidr" || $type eq "loosecidr")} then {
	    if {[regexp {/}  $addr ]} then {
		set r [mc "The '/' character is not valid in the address '%s'" $addr]
	    }
	}
    } else {
	if {$type eq "macaddr"} then {
	    set r [mc "Invalid syntax for MAC address '%s'" $addr]
	} else {
	    set r [mc "Invalid syntax for IP address '%s'" $addr]
	}
    }
    return $r
}

#
# Check possible values for a TTL (see RFC 2181) and check against permissions
#
# Input:
#   - parameters:
#	- ttl : new TTL value supplied
#	- ottl : old value for this object as registered in database
#   - global variable:
#	::n : user context
# Output:
#   - return value: new TTL value
#   - this function may raise an error
#
# Notes:
#   - ttl may contain:
#	- (empty string): TTL provided as a null JSON value
#	- -1: default value (use default zone TTL)
#	- 0..2^31-1: valid values
#   - each group has a flag indicating its right to modify TTL
#
#	group right        | ttl supplied | error          | new TTL value
#	------------------ | ------------ | -------------- | -----------------
#	TTL authorized     | -1, 0..max   | -              | unchanged
#			   | empty string | -              | $ottl
#	TTL not authorized | -1, 0..max   | if ttl != ottl | N.A. or unchanged
#			   | empty string | -              | $ottl
#
#
# History
#   2010/11/02 : pda/jean : design, from jean's code
#   2010/11/29 : pda      : i18n
#   2017/02/01 : pda/jean : new interface
#

proc check-ttl {ttl ottl} {
    if {$ttl ne ""} then {
	# 2^31-1
	set max [expr 0x7fffffff]
	if {! ([regexp {^-?\d+$} $ttl] && $ttl >= -1 && $ttl <= $max)} then {
	    ::scgi::serror 400 [mc "Invalid TTL: must be -1 or less or equal than %s" $max]
	}
    }

    if {$ttl eq ""} then {
	set ttl $ottl
    } else {
	if {! ("ttl" in [::n capabilities])} then {
	    if {$ttl != $ottl} then {
		::scgi::serror 400 [mc "You are not allowed to change TTL values"]
	    }
	}
    }

    return $ttl
}

#
# Check possible values for a MX priority (see RFC 1035)
#
# Input:
#   - parameters:
#	- prio : value to check
# Output:
#   - return value: empty string or error message
#
# History
#   2017/02/01 : pda/jean : design
#

proc check-prio {prio} {
    set r ""
    # 2^16-1
    set max [expr 0xffff]
    if {! [regexp {^\d+$} $prio]} then {
	set r [mc "Invalid priority: must be a positive integer"]
    } else {
	if {$prio > $max} then {
	    set r [mc "Invalid priority: must be less or equal than %s" $max]
	}
    }
    return $r
}

#
# Search for a domain name in the database
#
# Input:
#   - parameters:
#       - dbfd : database handle
#	- domain : domain to search (not terminated by a ".")
# Output:
#   - return value: id of domain if found, -1 if not found
#
# History
#   2002/04/11 : pda/jean : design
#   2010/11/29 : pda      : i18n
#

proc read-domain {dbfd domain} {
    set domain [pg_quote $domain]
    set iddom -1
    $dbfd exec "SELECT iddom FROM dns.domain WHERE name = $domain" tab {
	set iddom $tab(iddom)
    }
    return $iddom
}

#
# FIXME this function is obsolete. Prefer [::n isalloweddom $iddom $role]
#
# Checks if the domain is authorized for this user
#
# Input:
#   - parameters:
#       - dbfd : database handle
#	- idcor : user id
#	- _iddom : domain id or -1 to read from domain
#	- _domain : domain, or "" to read from iddom
#	- roles : roles to test (column names in p_dom)
# Output:
#   - return value: empty string or error message
#   - parameters _iddom and _domain : fetched values
#
# History
#   2002/04/11 : pda/jean : design
#   2002/05/06 : pda/jean : use groups
#   2004/02/06 : pda/jean : add roles
#   2010/11/29 : pda      : i18n
#

proc check-domain {dbfd idcor _iddom _domain roles} {
    upvar $_iddom iddom
    upvar $_domain domain

    set msg ""

    #
    # Read domain if needed
    #
    if {$iddom == -1} then {
	set iddom [read-domain $dbfd $domain]
	if {$iddom == -1} then {
	    set msg [mc "Domain '%s' not found" $domain]
	}
    } elseif {$domain eq ""} then {
	set sql "SELECT name FROM dns.domain WHERE iddom = $iddom"
	$dbfd exec $sql tab {
	    set domain $tab(name)
	}
	if {$domain eq ""} then {
	    set msg [mc "Domain-id '%s' not found" $iddom]
	}
    }

    #
    # Check if we have rights on this domain
    #
    if {$msg eq ""} then {
	set where ""
	foreach r $roles {
	    append where "AND p_dom.$r > 0 "
	}

	set found 0
	set sql "SELECT p_dom.iddom FROM dns.p_dom, global.nmuser
			    WHERE nmuser.idcor = $idcor
				    AND nmuser.idgrp = p_dom.idgrp
				    AND p_dom.iddom = $iddom
				    $where
				    "
	$dbfd exec $sql tab {
	    set found 1
	}
	if {! $found} then {
	    set msg [mc "You don't have rights on domain '%s'" $domain]
	}
    }

    return $msg
}

#
# Check if the IP address is authorized for this user
#
# Input:
#   - parameters:
#       - dbfd : database handle
#	- idcor : user id
#	- addr : IP address to test
# Output:
#   - return value: 1 if ok, 0 if error
#
# History
#   2002/04/11 : pda/jean : design
#   2002/05/06 : pda/jean : use groups
#   2004/01/14 : pda/jean : add IPv6
#   2010/11/29 : pda      : i18n
#

proc check-authorized-ip {dbfd idcor addr} {
    set r 0
    set sql "SELECT dns.check_ip_cor ('$addr', $idcor) AS ok"
    $dbfd exec $sql tab {
	set r [string equal $tab(ok) "t"]
    }
    return $r
}

#
# Check if the user has adequate rights to a machine, by checking
# that he owns all IP addresses
#
# Input:
#   - parameters:
#       - dbfd : database handle
#	- idcor : user id
#	- rr : see ::rr::read-by-name (may be not found)
# Output:
#   - return value: error message or empty string
#

proc check-name-by-addresses {dbfd idcor rr} {
    if {! [::rr::found $rr]} then {
	return ""
    }

    set idview [::rr::get-idview $rr]
    if {! [::n isallowedview $idview]} then {
	return [mc {Invalid view %s} [::n viewname $idview]]
    }

    #
    # Check all addresses and views
    #

    foreach ip [::rr::get-addr $rr] {
	if {! [check-authorized-ip $dbfd $idcor $ip]} then {
	    return [mc {Unauthorized IP address '%s'} $ip]
	}
    }

    return ""
}

#
# Check if the user as the right to add/modify/delete a given name
# according to a given context.
#
# Input:
#   - parameters:
#       - dbfd : database handle
#	- idcor : user id
#	- name : name to test (first component of FQDN)
#	- domain : domain to test (the n-1 last components of FQDN)
#	- idview : view id in which this FQDN must be tested
#	- rr : in return, information on the host (see ::rr::read-by-id)
#	- context : the context to check
# Output:
#   - return value: empty string or error message
#   - parameter rr : if RR exists, contains informations on the RR found
#	(use ::rr::found to check if RR exists)
#
# Detail of tests:
#    According to context:
#	"host"
#	    check-domain (domain, idcor, "") and views
#	    if name.domain is ALIAS then error
#	    if name.domain is MX then error
#	    if name.domain is ADDRMAIL
#		then check-all-IP-addresses (mail host, idcor)
#		      check-domain (domain, idcor, "")
#	    if name.domain has IP addresses
#		then check-all-IP-addresses (machine, idcor)
#	    if no test is false, then OK
#	"existing-host"
#	    identical to "host", but the name must have at least one IP address
#	"del-name"
#	    check-domain (domain, idcor, "") and views
#	    if name.domain is ALIAS
#		then check-all-IP-addresses (pointed host, idcor)
#	    if name.domain is MX then error
#	    if name.domain has IP addresses
#		then check-all-IP-addresses (machine, idcor)
#	    if name.domain is ADDRMAIL
#		then check-all-IP-addresses (mail host, idcor)
#		      check-domain (domain, idcor, "")
#	    if no test is false, then OK
#	"alias"
#	    check-domain (domain, idcor, "") and views
#	    if name.domain is ALIAS then error
#	    if name.domain is MX then error
#	    if name.domain is target of a MX then error
#	    if name.domain is ADDRMAIL then error
#	    if name.domain has IP addresses then error
#	    if no test is false, then OK
#	"add-mx"
#	    check-domain (domain, idcor, "") and views
#	    if name.domain is ALIAS then error
#	    if name.domain is MX then error
#	    if name.domain is ADDRMAIL then error
#	    if no test is false, then OK
#	"del-mx"
#	    check-domain (domain, idcor, "") and views
#	    if name.domain is ALIAS then error
#	    if name.domain is MX
#		then check-all-IP-addresses (mail exchangers, idcor)
#	    if name.domain is ADDRMAIL then error
#	    if no test is false, then OK
#	"add-mailaddr"
#	    check-domain (domain, idcor, "mailrole") and views
#	    if name.domain is ALIAS then error
#	    if name.domain is MX then error
#	    if name.domain is ADDRMAIL then error
#	    if name.domain is MBOXHOST then error
#	    if name.domain has IP addresses
#		check-all-IP-addresses (name.domain, idcor)
#	    if no test is false, then OK
#	"del-mailaddr"
#	    check-domain (domain, idcor, "mailrole") and views
#	    if name.domain is ALIAS then error
#	    if name.domain is MX then error
#	    if name.domain is target of a MX then error
#	    if name.domain is NOT ADDRMAIL then error
#	    if name.domain is ADDRMAIL
#		check-all-IP-addresses (mail host, idcor)
#		check-domain (domain, idcor, "")
#	    if name.domain has IP addresses
#		check-all-IP-addresses (name.domain, idcor)
#	    if no test is false, then OK
#
#    check-IP-addresses (host, idcor)
#	if there is no address
#	    then error
#	    else check that all IP addresses are mine (with an AND)
#	end if
#

proc check-authorized-host {dbfd idcor name domain idview _rr context} {
    upvar $_rr rr

    array set testrights {
	host	{
		    {domain	all}
		    {alias	REJECT}
		    {mx		REJECT}
		    {ip		CHECK}
		    {mailaddr	CHECK}
		}
	existing-host	{
		    {domain	all}
		    {alias	REJECT}
		    {mx		REJECT}
		    {ip		CHECK}
		    {ip		EXISTS}
		    {mailaddr	CHECK}
		}
	alias	{
		    {domain	all}
		    {alias	REJECT}
		    {mx		REJECT}
		    {ip		REJECT}
		    {mailaddr	REJECT}
		}
	del-name	{
		    {domain	all}
		    {alias	CHECK}
		    {mx		REJECT}
		    {ip		CHECK}
		    {mailaddr	CHECK}
		}
	add-mx	{
		    {domain	all}
		    {alias	REJECT}
		    {mx		REJECT}
		    {ip		CHECK}
		    {mailaddr	REJECT}
		}
	del-mx	{
		    {domain	all}
		    {alias	REJECT}
		    {mx		CHECK}
		    {ip		CHECK}
		    {mailaddr	REJECT}
		}
	add-mailaddr	{
		    {domain	mailrole}
		    {alias	REJECT}
		    {mx		REJECT}
		    {mailaddr	REJECT}
		    {mboxhost	REJECT}
		    {ip		CHECK}
		}
	del-mailaddr	{
		    {domain	mailrole}
		    {alias	REJECT}
		    {mx		REJECT}
		    {mailaddr	CHECK}
		    {mailaddr	EXISTS}
		    {ip		CHECK}
		}
    }

    #
    # Get the list of actions associated with the context
    #

    if {! [info exists testrights($context)]} then {
	return [mc "Internal error: invalid context '%s'" $context]
    }

    #
    # For each view, process tests in the given order, and break as
    # soon as a test fails
    #

    set fqdn "$name.$domain"
    set iddom [::n domainid $domain]
    if {$iddom == -1} then {
	return [mc "Domain '%s' not found" $domain]
    }

    foreach a $testrights($context) {
	set parm [lindex $a 1]
	switch [lindex $a 0] {
	    domain {
		set msg [check-views [list $idview]]
		if {$msg ne ""} then {
		    return $msg
		}
		set viewname [::n viewname $idview]

		if {! [::n isalloweddom $iddom $parm]} then {
		    return [mc "You don't have rights on domain '%s'" $domain]
		}

		set rr [::rr::read-by-name $dbfd $name $iddom $idview]
	    }
	    alias {
		set idcname -1
		if {[::rr::found $rr]} then {
		    set idcname [::rr::get-cname $rr]
		}

		if {$idcname != -1} then {
		    set r2 [::rr::read-by-idhost $dbfd $idcname]
		    if {! [::rr::found $r2]} then {
			return [mc "Internal error: alias references non-existant host id '%s'" $idcname]
		    }
		    set fqdnref [::rr::get-fqdn $r2]
		    switch $parm {
			REJECT {
			    return [mc {%1$s is an alias of host %2$s in view %3$s} $fqdn $fqdnref $viewname]
			}
			CHECK {
			    set msg [check-name-by-addresses $dbfd $idcor $r2]
			    if {$msg ne ""} then {
				return [mc {You don't have rights '%1$s' referenced by alias '%2$s' (%3$s)} $fqdnref $fqdn $msg]
			    }
			}
			default {
			    return [mc {Internal error: invalid parameter '%1$s' for '%2$s'} $parm "$context/$a"]
			}
		    }
		}
	    }
	    mx {
		set lmx {}
		if {[::rr::found $rr]} then {
		    set lmx [::rr::get-mxhosts $rr]
		}

		if {$parm eq "CHECK"} then {
		    if {[llength $lmx] == 0} then {
			return [mc "%s is not a MX" $fqdn]
		    }
		}

		foreach mx $lmx {
		    lassign $mx prio idhost ttl
		    switch $parm {
			REJECT {
			    return [mc "'%s' is a MX" $fqdn]
			}
			CHECK {
			    set rmx [::rr::read-by-idhost $dbfd $idhost]
			    if {! [::rr::found $rmx]} then {
				return [mc "Internal error: MX references non-existant host id '%s'" $idhost]
			    }
			    set msg [check-name-by-addresses $dbfd $idcor $rmx]
			    if {$msg ne ""} then {
				set fqdnmx [::rr::get-fqdn $rmx]
				return [mc {You don't have rights on '%1$s' referenced by MX '%2$s' (%3$s)} $fqdnmx $fqdn $msg]
			    }
			}
			default {
			    return [mc {Internal error: invalid parameter '%1$s' for '%2$s'} $parm "$context/$a"]
			}
		    }
		}
	    }
	    mailaddr {
		# get mailbox host for this address
		set idmboxhost -1
		if {[::rr::found $rr]} then {
		    set idmboxhost [::rr::get-mboxhost $rr]
		}

		if {$idmboxhost != -1} then {
		    # get mbox host
		    set rrm [::rr::read-by-idhost $dbfd $idmboxhost]
		    if {! [::rr::found $rrm]} then {
			return [mc "Internal error: id '%s' doesn't exists for a mail host" $idmboxhost]
		    }
		    set idviewmbx [::rr::get-idview $rrm]
		    set fqdnm [::rr::get-fqdn $rrm]
		    switch $parm {
			REJECT {
			    # This name is already a mail address
			    # (it already has a mailbox host)
			    return [mc {%1$s in view %2$s is a mail address hosted by %3$s in view %4$s} $fqdn $viewname $fqdnm [::n viewname $idviewmbx]]
			}
			CHECK {
			    # Check mboxhost IP addresses
			    set msg [check-name-by-addresses $dbfd $idcor $rrm]
			    if {$msg ne ""} then {
				return [mc {You don't have rights on host '%1$s' holding mail for '%2$s' (%3$s)} $fqdnm $fqdn $msg]
			    }

			    # Check mboxhost domain
			    set mbiddom [::rr::get-iddom $rrm]
			    if {! [::n isalloweddom $mbiddom "all"]} then {
				return [mc {You don't have rights on domain of host '%1$s' holding mail for '%2$s'} $fqdnm $fqdn]
			    }
			}
			EXISTS {
			    # nothing
			}
			default {
			    return [mc {Internal error: invalid parameter '%1$s' for '%2$s'} $parm "$context/$a"]
			}
		    }
		} else {
		    # this address has no mailbox host, so it is
		    # not a mail role
		    switch $parm {
			REJECT -
			CHECK {
			    # nothing
			}
			EXISTS {
			    return [mc {'%1$s' is not a mail role in view '%2$s'} $fqdn $viewname]
			}
			default {
			    return [mc {Internal error: invalid parameter '%1$s' for '%2$s'} $parm "$context/$a"]
			}
		    }
		}
	    }
	    mboxhost {
		set lma {}
		if {[::rr::found $rr]} then {
		    set lma [::rr::get-mailaddr $rr]
		}

		switch $parm {
		    REJECT {
			# check if the new mail-address is a mboxhost
			# for other mail addresses (except for its own
			# mail address)
			# => check if there are mail addresses for this
			# mboxhost (other than the fqdn of the mboxhost
			# itself)
			set l {}
			foreach idma $lma {
			    set rrma [::rr::read-by-idname $dbfd $idma]
			    if {! [::rr::found $rrma]} then {
				return [mc "Internal error: id '%s' doesn't exists for a mail address" $idma]
			    }
			    set fqdnma [::rr::get-fqdn $rrma]
			    if {$fqdnma ne $fqdn} then {
				lappend l $fqdnma
			    }
			}
			if {[llength $l] > 0} then {
			    return [mc {'%1$s' is a mail host for mail domains: %2$s} $fqdn $l]
			}
		    }
		    default {
			return [mc {Internal error: invalid parameter '%1$s' for '%2$s'} $parm "$context/$a"]
		    }
		}
	    }
	    ip {
		set lip {}
		if {[::rr::found $rr]} then {
		    set lip [::rr::get-addr $rr]
		}

		switch $parm {
		    REJECT {
			if {[llength $lip] > 0} then {
			    return [mc {'%1$s' has IP addresses in view '%2$s'} $fqdn $viewname]
			}
		    }
		    EXISTS {
			if {[llength $lip] == 0} then {
			    return [mc {Name '%1$s' is not a host in view '%2$s'} $fqdn $viewname]
			}
		    }
		    CHECK {
			set msg [check-name-by-addresses $dbfd $idcor $rr]
			if {$msg ne ""} then {
			    return [mc {You don't have rights on '%1$s' (%2$s)} $fqdn $msg]
			}
		    }
		    default {
			return [mc {Internal error: invalid parameter '%1$s' for '%2$s'} $parm "$context/$a"]
		    }
		}
	    }
	}
    }

    return ""
}

proc check-authorized-rr {dbfd idcor rr context} {
    set name   [::rr::get-name $rr]
    set domain [::rr::get-domain $rr]
    set idview [::rr::get-idview $rr]

    return [check-authorized-host $dbfd $idcor $name $domain $idview nrr $context]
}

#
# Check if host exists and is authorized and exits if this is not the case
#

proc check-idhost {dbfd idhost} {
    set rr [::rr::read-by-idhost $dbfd $idhost]
    if {! [::rr::found $rr]} then {
	::scgi::serror 404 [mc "Host %d not found" $idhost]
    }

    set msg [check-authorized-rr $dbfd [::n idcor] $rr "existing-host"]
    if {$msg ne ""} then {
	::scgi::serror 400 $msg
    }

    return $rr
}


#
# Check needed operations on the MX list
# idview: idview to check with all new MX targets
# nmx: new MX list, list of NMJson objects:
#			{object 
#				{prio	{number ...}
#				{ttl	{number ...}
#				{idhost	{number ...}
#			}
# omx: list of MX records (result of ::rr::get-mxhost for the old values)
#	{{prio idhost ttl} ...}
# returns list {ldel lmod lnew}
#	where each ldel, lmod, lnew is a list:
#		{{prio ttl idhost rr} ...}

proc check-mx-list {idview nmx omx} {
    # process old MX list
    foreach m $omx {
	lassign $m oprio oidhost ottl
	set orr [check-idhost ::dbdns $oidhost]
	set old($oidhost) [list $oprio $ottl $orr]
    }

    set lmod {}
    set lnew {}

    # process new MX list
    foreach e $nmx {
	::nmjson::import-object $e 1

	if {[info exists alreadyseen($idhost)]} then {
	    ::scgi::serror 400 [mc {Duplicate MX host %d} $idhost]
	}
	set alreadyseen($idhost) 1

	set msg [check-prio $prio]
	if {$msg ne ""} then {
	    ::scgi::serror 400 $msg
	}

	set ottl -1
	if {[info exists old($idhost)]} then {
	    set ottl [lindex $old($idhost) 1]
	}
	set ttl [check-ttl $ttl $ottl]

	if {[info exists old($idhost)]} then {
	    lassign $old($idhost) oprio ottl orr
	    if {$oprio != $prio || $ottl != $ttl} then {
		lappend lmod [list $prio $ttl $idhost $orr]
	    }
	    unset old($idhost)
	} else {
	    set rr [check-idhost ::dbdns $idhost]
	    set idv [::rr::get-idview $rr]
	    if {$idv != $idview} then {
		::scgi::serror 400 [mc {Invalid view '%1$s' for host '%2$s'} [::n viewname $idv] [::rr::get-fqdn $rr]]

	    }
	    lappend lnew [list $prio $ttl $idhost $rr]
	}
    }

    if {[llength [array names alreadyseen]] == 0} then {
	::scgi::serror 400 [mc {Empty MX host list}]
    }

    set ldel {}
    foreach oidhost [array names old] {
	lassign $old($oidhost) oprio ottl orr
	lappend ldel [list $oprio $ottl $oidhost $orr]
    }

    return [list $ldel $lmod $lnew]
}
