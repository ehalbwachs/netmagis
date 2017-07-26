------------------------------------------------------------------------------
-- Netmagis SQL functions
------------------------------------------------------------------------------


------------------------------------------------------------------------------
-- Check a DHCP range against group permissions
-- 
-- Input:
--   - $1 : idgrp
--   - $2 : dhcp min
--   - $3 : dhcp max
-- Output:
--   - true (all addresses in DHCP range are allowed) or false
--
-- History
--    200?/??/?? : pda : design
--


------------------------------------------------------------------------------
-- Classifies each IPv4 address in a network
--
-- Input:
--   - net: network address
--   - lim: limit on the number of addresses classified
--   - grp: group id
-- Output:
--    - table with columns:
--		addr  INET
--		avail INTEGER (see below)
--		fqdn  TEXT
--
-- Note: addresses are classified according to:
--     0 : unavailable (broadcast addr, no right on addr, etc.)
--     1 : not declared and not in a dhcp range
--     2 : declared and not in a dhcp range
--     3 : not declared and in a dhcp range
--     4 : declared and in a dhcp range
--   This function creates a temporary table (allip) which only exists
--   during the postgresql session lifetime. This table is internal to
--   the session (other sessions cannot see it).
--   Since this function performs a sequential traversal of IP range,
--   a limit value must be given to not overload the PostgreSQL engine.
--
-- History
--    200?/??/?? : pda : design
--

CREATE OR REPLACE FUNCTION dns.mark_cidr (net CIDR, lim INTEGER, grp INTEGER)
    RETURNS void AS $$
    DECLARE
	min INET ;
	max INET ;
	a INET ;
    BEGIN
	min := INET (HOST (net)) ;
	max := INET (HOST (BROADCAST (net))) ;

	IF max - min - 2 > lim THEN
	    RAISE EXCEPTION 'Too many addresses' ;
	END IF ;

	-- All this exception machinery is here since we can't use :
	--    DROP TABLE IF EXISTS allip ;
	-- It raises a notice exception, which prevents
	-- script "ajout" to function
	BEGIN
	    DROP TABLE allip ;
	EXCEPTION
	    WHEN OTHERS THEN -- nothing
	END ;

	CREATE TEMPORARY TABLE allip (
	    addr INET,
	    avail INTEGER,
		-- 0 : unavailable (broadcast addr, no right on addr, etc.)
		-- 1 : not declared and not in a dhcp range
		-- 2 : declared and not in a dhcp range
		-- 3 : not declared and in a dhcp range
		-- 4 : declared and in a dhcp range
	    fqdn TEXT		-- if 2 or 4, then fqdn else NULL
	) ;

	a := min ; 
	WHILE a <= max LOOP
	    INSERT INTO allip VALUES (a, 1) ;
	    a := a + 1 ;
	END LOOP ;

	UPDATE allip
	    SET fqdn = rr.name || '.' || domain.name,
		avail = 2
	    FROM dns.rr_ip, dns.rr, dns.domain
	    WHERE allip.addr = rr_ip.addr
		AND rr_ip.idrr = rr.idrr
		AND rr.iddom = domain.iddom
		;

	UPDATE allip
	    SET avail = CASE
			    WHEN avail = 1 THEN 3
			    WHEN avail = 2 THEN 4
			END
	    FROM dns.dhcprange
	    WHERE (avail = 1 OR avail = 2)
		AND addr >= dhcprange.min
		AND addr <= dhcprange.max
	    ;

	UPDATE allip SET avail = 0
	    WHERE addr = min OR addr = max OR NOT dns.check_ip_grp (addr, grp) ;

	RETURN ;

    END ;
    $$ LANGUAGE plpgsql ;

------------------------------------------------------------------------------
-- Search IPv4 address range for available blocks
--
-- Input:
--   - net: network address
--   - lim: limit on the number of addresses classified
--   - grp: group id
-- Output:
--    - table with columns:
--		a	INET		-- starting address
--		n	INTEGER		-- number of addresses in block
--
-- Note: this is the PostgreSQL 8.3 version (the 8.4 version would have
--   been more elegant)
--
-- History
--    200?/??/?? : pda : design
--

DROP TYPE IF EXISTS iprange_t CASCADE ;
CREATE TYPE iprange_t AS (a INET, n INTEGER) ;

CREATE OR REPLACE FUNCTION dns.ipranges (net CIDR, lim INTEGER, grp INTEGER)
    RETURNS SETOF iprange_t AS $$
    DECLARE
	inarange BOOLEAN ;
	r RECORD ;
	q iprange_t%ROWTYPE ;
    BEGIN
	PERFORM dns.mark_cidr (net, lim, grp) ;
	inarange := FALSE ;
	FOR r IN (SELECT addr, avail FROM allip ORDER BY addr)
	LOOP
	    IF inarange THEN
		-- (q.a, q.n) is already a valid range
		IF r.avail = 1 THEN
		    q.n := q.n + 1 ;
		ELSE
		    RETURN NEXT q ;
		    inarange := FALSE ;
		END IF ;
	    ELSE
		-- not inside a range
		IF r.avail = 1 THEN
		    -- start a new range (q.a, q.n)
		    q.a := r.addr ;
		    q.n := 1 ;
		    inarange := TRUE ;
		END IF ;
	    END IF ;
	END LOOP ;
	IF inarange THEN
	    RETURN NEXT q ;
	END IF ;
	DROP TABLE allip ;
	RETURN ;
    END ;
    $$ LANGUAGE plpgsql ;

------------------------------------------------------------------------------
-- Set the generation flag for one or more zones. These functions
-- are called from the corresponding trigger functions and set the
-- generation flag for all modified zones.
--
-- Input:
--   - $1: IPv4/v6 address or domain id or RR id
--   - $2: view id
-- Output:
--   - an unused integer value, just to be able to call sum() on result
--
-- History
--    2002/??/?? : pda/jean : design
--

-- called when an IPv4 address is modified ($1=addr, $2=idhost)
CREATE OR REPLACE FUNCTION dns.gen_rev4 (INET, INTEGER)
    RETURNS INTEGER AS $$
    BEGIN
	UPDATE dns.zone_reverse4 AS z
	    SET gen = 1, counter = NEXTVAL ('dns.seq_zcounter')
	    FROM dns.host h, dns.name n
	    WHERE $1 <<= z.selection
		AND h.idhost = $2
		AND h.idname = n.idname
		AND z.idview = n.idview ;
	RETURN 1 ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

-- called when an IPv6 address is modified ($1=addr, $2=idhost)
CREATE OR REPLACE FUNCTION dns.gen_rev6 (INET, INTEGER)
    RETURNS INTEGER AS $$
    BEGIN
	UPDATE dns.zone_reverse6 AS z
	    SET gen = 1, counter = NEXTVAL ('dns.seq_zcounter')
	    FROM dns.host h, dns.name n
	    WHERE $1 <<= selection
		AND h.idhost = $2
		AND h.idname = n.idname
		AND z.idview = n.idview ;
	RETURN 1 ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

-- ID of host ($1=idhost)
CREATE OR REPLACE FUNCTION dns.gen_norm_idhost (INTEGER)
    RETURNS INTEGER AS $$
    BEGIN
	UPDATE dns.zone_forward
	    SET gen = 1, counter = NEXTVAL ('dns.seq_zcounter')
	    WHERE (selection, idview) = 
		    (
			SELECT d.name, n.idview
			    FROM dns.host h
				NATURAL INNER JOIN dns.name n
				NATURAL INNER JOIN dns.domain d
			    WHERE h.idhost = $1
		    ) ;
	RETURN 1 ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

-- ID of name ($1=idname)
CREATE OR REPLACE FUNCTION dns.gen_norm_idname (INTEGER)
    RETURNS INTEGER AS $$
    BEGIN
	UPDATE dns.zone_forward
	    SET gen = 1, counter = NEXTVAL ('dns.seq_zcounter')
	    WHERE (selection, idview) = 
		    (
			SELECT d.name, n.idview
			    FROM dns.name n
				NATURAL INNER JOIN dns.domain d
			    WHERE n.idname = $1
		    ) ;
	RETURN 1 ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

-- ID of RR ($1=iddom, $2=idview)
CREATE OR REPLACE FUNCTION dns.gen_norm_iddom (INTEGER, INTEGER)
    RETURNS INTEGER AS $$
    BEGIN
	UPDATE dns.zone_forward
	    SET gen = 1, counter = NEXTVAL ('dns.seq_zcounter')
	    WHERE idview = $2
		AND selection = (
		    SELECT domain.name
			    FROM dns.domain
			    WHERE domain.iddom = $1
		    ) ;
	RETURN 1 ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

-- utility function for the mod_relay trigger function
-- called when a mail relay is modified ($1=iddom, $2=idhost of mx)
CREATE OR REPLACE FUNCTION dns.gen_relay (INTEGER, INTEGER)
    RETURNS INTEGER AS $$
    BEGIN
	UPDATE dns.zone_forward
	    SET gen = 1, counter = NEXTVAL ('dns.seq_zcounter')
	    WHERE selection = ( SELECT name FROM dns.domain WHERE iddom = $1 )
		AND idview = ( SELECT n.idview
				    FROM dns.host h
					NATURAL INNER JOIN dns.name n
				    WHERE h.idhost = $2 )
	    ;
	RETURN 1 ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Set the DHCP generation flag for one or more views.
--
-- Input:
--   - $1: idhost
-- Output:
--   - an unused integer value, just to be able to call sum() on result
--
-- History
--    201?/??/?? : pda/jean : design
--

CREATE OR REPLACE FUNCTION dns.gen_dhcp (INTEGER)
    RETURNS INTEGER AS $$
    BEGIN
	UPDATE dns.view SET gendhcp = 1
	    FROM dns.host h
		NATURAL INNER JOIN dns.name n
	    WHERE h.idhost = $1
		AND h.mac IS NOT NULL
		AND view.idview = n.idview ;
	RETURN 1 ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Trigger function called when an IP address is modified
--
-- History
--    200?/??/?? : pda/jean : design
--

CREATE OR REPLACE FUNCTION dns.mod_addr ()
    RETURNS trigger AS $$
    BEGIN
	IF TG_OP = 'INSERT'
	THEN
	    PERFORM sum (dns.gen_rev4 (NEW.addr, NEW.idhost)) ;
	    PERFORM sum (dns.gen_rev6 (NEW.addr, NEW.idhost)) ;
	    PERFORM sum (dns.gen_norm_idhost (NEW.idhost)) ;
	    PERFORM sum (dns.gen_dhcp (NEW.idhost)) ;

	END IF ;

	IF TG_OP = 'UPDATE'
	THEN
	    PERFORM sum (dns.gen_rev4 (NEW.addr, NEW.idhost)) ;
	    PERFORM sum (dns.gen_rev4 (OLD.addr, OLD.idhost)) ;
	    PERFORM sum (dns.gen_rev6 (NEW.addr, NEW.idhost)) ;
	    PERFORM sum (dns.gen_rev6 (OLD.addr, OLD.idhost)) ;
	    PERFORM sum (dns.gen_norm_idhost (NEW.idhost)) ;
	    PERFORM sum (dns.gen_norm_idhost (OLD.idhost)) ;
	    PERFORM sum (dns.gen_dhcp (NEW.idhost)) ;
	    PERFORM sum (dns.gen_dhcp (OLD.idhost)) ;
	END IF ;

	IF TG_OP = 'DELETE'
	THEN
	    PERFORM sum (dns.gen_rev4 (OLD.addr, OLD.idhost)) ;
	    PERFORM sum (dns.gen_rev6 (OLD.addr, OLD.idhost)) ;
	    PERFORM sum (dns.gen_norm_idhost (OLD.idhost)) ;
	    PERFORM sum (dns.gen_dhcp (OLD.idhost)) ;
	END IF ;

	RETURN NEW ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Trigger function called when a CNAME or a MX is modified
--
-- History
--    200?/??/?? : pda/jean : design
--

CREATE OR REPLACE FUNCTION dns.mod_mx_alias ()
    RETURNS trigger AS $$
    BEGIN
	IF TG_OP = 'INSERT'
	THEN
	    PERFORM sum (dns.gen_norm_idname (NEW.idname)) ;
	END IF ;

	IF TG_OP = 'UPDATE'
	THEN
	    PERFORM sum (dns.gen_norm_idname (NEW.idname)) ;
	    PERFORM sum (dns.gen_norm_idname (OLD.idname)) ;
	END IF ;

	IF TG_OP = 'DELETE'
	THEN
	    PERFORM sum (dns.gen_norm_idname (OLD.idname)) ;
	END IF ;

	RETURN NEW ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Trigger function called when a name is modified
--
-- History
--    200?/??/?? : pda/jean : design
--

-- modify RR and reverse zones for all IP addresses
CREATE OR REPLACE FUNCTION dns.mod_name ()
    RETURNS trigger AS $$
    BEGIN
	-- IF TG_OP = 'INSERT'
	-- THEN
	    -- no need to regenerate anything since no host/alias/mx/... has
	    -- been linked to this name yet
	-- END IF ;

	IF TG_OP = 'UPDATE'
	THEN
	    PERFORM sum (dns.gen_norm_iddom (NEW.iddom, NEW.idview))
		    ;
	    PERFORM sum (dns.gen_norm_iddom (OLD.iddom, OLD.idview))
		    ;
	    PERFORM sum (dns.gen_rev4 (a.addr, h.idhost))
		    FROM dns.host h NATURAL INNER JOIN dns.addr a
		    WHERE h.idname = NEW.idname
		    ;
	    PERFORM sum (dns.gen_rev6 (a.addr, h.idhost))
		    FROM dns.host h NATURAL INNER JOIN dns.addr a
		    WHERE h.idname = NEW.idname
		    ;
	    PERFORM sum (dns.gen_dhcp (h.idhost))
		    FROM dns.host h
		    WHERE h.idname = NEW.idname
		    ;
	    -- no need to regenerate reverse/dhcp for old name since
	    -- IP addresses did not change
	END IF ;

	-- IF TG_OP = 'DELETE'
	-- THEN
	    -- no need to regenerate anything since all host/alias/mx/... have
	    -- already been removed before
	-- END IF ;

	RETURN NEW ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

CREATE OR REPLACE FUNCTION dns.mod_host ()
    RETURNS trigger AS $$
    BEGIN
	-- IF TG_OP = 'INSERT'
	-- THEN
	    -- no need to regenerate anything since no IP address has
	    -- been linked to this host yet
	-- END IF ;

	IF TG_OP = 'UPDATE'
	THEN
	    PERFORM sum (dns.gen_norm_iddom (n.iddom, n.idview))
		    FROM dns.name n
		    WHERE n.idname = NEW.idname
		    ;
	    PERFORM sum (dns.gen_norm_iddom (n.iddom, n.idview))
		    FROM dns.name n
		    WHERE n.idname = OLD.idname
		    ;
	    PERFORM sum (dns.gen_rev4 (a.addr, NEW.idhost))
		    FROM dns.addr a
		    WHERE a.idhost = NEW.idhost
		    ;
	    PERFORM sum (dns.gen_rev6 (a.addr, NEW.idhost))
		    FROM dns.addr a
		    WHERE a.idhost = NEW.idhost
		    ;
	    PERFORM sum (dns.gen_dhcp (NEW.idhost))
		    ;
	    -- no need to regenerate reverse/dhcp for old host since
	    -- IP addresses did not change
	END IF ;

	-- IF TG_OP = 'DELETE'
	-- THEN
	    -- no need to regenerate anything since all IP addresses have
	    -- already been removed before
	-- END IF ;

	RETURN NEW ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Trigger function called when a mail relay is modified
--
-- History
--    200?/??/?? : pda/jean : design
--

CREATE OR REPLACE FUNCTION dns.mod_relay ()
    RETURNS trigger AS $$
    BEGIN
	IF TG_OP = 'INSERT'
	THEN
	    PERFORM sum (dns.gen_relay (NEW.iddom, NEW.idhost)) ;
	END IF ;

	IF TG_OP = 'UPDATE'
	THEN
	    PERFORM sum (dns.gen_relay (NEW.iddom, NEW.idhost)) ;
	    PERFORM sum (dns.gen_relay (OLD.iddom, OLD.idhost)) ;
	END IF ;

	IF TG_OP = 'DELETE'
	THEN
	    PERFORM sum (dns.gen_relay (OLD.iddom, OLD.idhost)) ;
	END IF ;

	RETURN NEW ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Trigger function called when a zone is modified
--
-- History
--    200?/??/?? : pda/jean : design
--

CREATE OR REPLACE FUNCTION dns.mod_zone ()
    RETURNS TRIGGER AS $$
    BEGIN
	IF NEW.prologue <> OLD.prologue
		OR NEW.rrsup <> OLD.rrsup
		OR NEW.selection <> OLD.selection
	THEN
	    NEW.gen := 1 ;
	    NEW.counter := NEXTVAL ('dns.seq_zcounter') ;
	END IF ;
	RETURN NEW ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Trigger function called when a DHCP parameter (network, range or profile)
-- is modified
--
-- History
--    200?/??/?? : pda/jean : design
--

CREATE OR REPLACE FUNCTION dns.mod_dhcp ()
    RETURNS TRIGGER AS $$
    BEGIN
	UPDATE dns.view SET gendhcp = 1 ;
	RETURN NEW ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Check access rights to an IP address
--
-- Input:
--   - $1: IPv4/v6 address to test
--   - $2: group id or user id
-- Output:
--   - true if access is allowed
--
-- History
--    2002/??/?? : pda/jean : design
--

CREATE OR REPLACE FUNCTION dns.check_ip_cor (INET, INTEGER)
    RETURNS BOOLEAN AS $$
    BEGIN
	RETURN dns.check_ip_grp ($1, idgrp) FROM global.nmuser WHERE idcor = $2 ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

CREATE OR REPLACE FUNCTION dns.check_ip_grp (INET, INTEGER)
    RETURNS BOOLEAN AS $$
    BEGIN
	RETURN ($1 <<= ANY (SELECT addr FROM dns.p_ip
				WHERE allow_deny = 1 AND idgrp = $2)
	    AND NOT $1 <<= ANY (SELECT addr FROM dns.p_ip
				WHERE allow_deny = 0 AND idgrp = $2)
	    ) ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Remove name from dns.name if possible (i.e. no other object references
-- this name), called during a trigger on delete
--
-- Input:
--   - OLD: row
-- Output:
--   - none
--
-- History
--    2016/11/18 : pda/jean : design
--

CREATE OR REPLACE FUNCTION dns.del_name ()
    RETURNS trigger AS $$
    BEGIN
	DELETE FROM dns.name WHERE idname = OLD.idname ;
	RETURN NULL ;
    EXCEPTION
	WHEN foreign_key_violation
	    THEN
		-- do nothing
		RETURN NULL ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Trigger function called when a vlan is modified
--
-- History
--    200?/??/?? : pda/jean : design
--

CREATE OR REPLACE FUNCTION topo.mod_vlan ()
    RETURNS trigger AS $$
    BEGIN
	INSERT INTO topo.modeq (eq) VALUES ('_vlan') ;
	RETURN NEW ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Trigger function called when an equipment is modified
--
-- History
--    200?/??/?? : pda/jean : design
--

CREATE OR REPLACE FUNCTION topo.mod_routerdb ()
    RETURNS trigger AS $$
    BEGIN
	INSERT INTO topo.modeq (eq) VALUES ('_routerdb') ;
	RETURN NEW ;
    END ;
    $$ LANGUAGE 'plpgsql' ;

------------------------------------------------------------------------------
-- Reduce a string to a soundex code in order to find approximate
-- names
-- 
-- Input:
--   - $1: string to reduce
-- Output:
--   - soundex
--
-- History
--    200?/??/?? : pda : design
--

CREATE OR REPLACE FUNCTION pgauth.soundex (TEXT)
    RETURNS TEXT AS '
	array set soundexFrenchCode {
	    a 0 b 1 c 2 d 3 e 0 f 9 g 7 h 0 i 0 j 7 k 2 l 4 m 5
	    n 5 o 0 p 1 q 2 r 6 s 8 t 3 u 0 v 9 w 9 x 8 y 0 z 8
	}
	set accentedFrenchMap {
	    é e  ë e  ê e  è e   É E  Ë E  Ê E  È E
	     ä a  â a  à a        Ä A  Â A  À A
	     ï i  î i             Ï I  Î I
	     ö o  ô o             Ö O  Ô O
	     ü u  û u  ù u        Ü U  Û U  Ù U
	     ç ss                 Ç SS
	}
	set key ""

	# Map accented characters
	set TempIn [string map $accentedFrenchMap $1]

	# Only use alphabetic characters, so strip out all others
	# also, soundex index uses only lower case chars, so force to lower

	regsub -all {[^a-z]} [string tolower $TempIn] {} TempIn
	if {$TempIn eq ""} then {
	    return Z000
	}
	set last [string index $TempIn 0]
	set key  [string toupper $last]
	set last $soundexFrenchCode($last)

	# Scan rest of string, stop at end of string or when the key is full

	set count    1
	set MaxIndex [string length $TempIn]

	for {set index 1} {(($count < 4) && ($index < $MaxIndex))} {incr index } {
	    set chcode $soundexFrenchCode([string index $TempIn $index])
	    # Fold together adjacent letters sharing the same code
	    if {$last ne $chcode} then {
		set last $chcode
		# Ignore code==0 letters except as separators
		if {$last != 0} then {
		    set key $key$last
		    incr count
		}
	    }
	}
	return [string range ${key}0000 0 3]
    ' LANGUAGE 'pltcl' WITH (isStrict) ;

------------------------------------------------------------------------------
-- Trigger function: computes soundex for name and first name
-- each time a name or first name is modified.
--
-- History
--    200?/??/?? : pda : design
--

CREATE OR REPLACE FUNCTION pgauth.add_soundex ()
    RETURNS TRIGGER AS '
    BEGIN
	NEW.phlast  := pgauth.SOUNDEX (NEW.lastname) ;
	NEW.phfirst := pgauth.SOUNDEX (NEW.firstname) ;
	RETURN NEW ;
    END ;
    ' LANGUAGE 'plpgsql' ;
