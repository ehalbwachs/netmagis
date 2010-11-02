#
# Librairie TCL pour l'application de gestion de l'authentification.
#
# Historique
#   2003/05/30 : pda/jean : conception
#   2003/12/11 : pda      : simplification
#   2003/05/13 : pda/jean : conception
#   2003/06/12 : pda/jean : retrait de lsuser
#   2003/06/13 : pda/jean : ajout de genpw, chpw et showuser
#   2003/06/27 : pda      : ajout de edituser
#   2003/07/28 : pda      : s�paration du nom et du pr�nom
#   2005/05/25 : pda/jean : d�but de la ldapisation
#   2005/06/07 : pda/jean/zamboni : changement de la commande de chiffrement
#   2005/08/24 : pda      : ajout du port ldap
#   2006/01/17 : jean     : suite ldapisation
#   2007/10/04 : jean     : on ne modifie plus l'annuaire ldap dans setuser
#   2007/11/29 : pda/jean : fusion ancien package auth.tcl et librairie libauth
#

set libconf(champs)	{login password nom prenom mel tel mobile fax adr}

# pour chiffrer les mots de passe
set libconf(trpw)	"/usr/bin/openssl passwd -1"

# pour g�n�rer un mot de passe al�atoire
set libconf(genpw)	"/usr/local/bin/pwgen --numerals 8"

# caract�ristique exig�e pour les mots de passe fournis par les utilisateurs
set libconf(minpwlen)	6
set libconf(maxpwlen)	16

# Champs : <titre> <type du champ> <nom de var pour le formulaire> <user>
#	avec <user> = 1 pour des informations sur l'utilisateur
set libconf(editfields) {
    {Login 	{string 10} login	1}
    {Nom	{string 40} nom		1}
    {M�thode	{yesno {%1$s Exp. r�guli�re %2$s Phon�tique}} phren 0}
    {Pr�nom	{string 40} prenom	1}
    {M�thode	{yesno {%1$s Exp. r�guli�re %2$s Phon�tique}} phrep 0}
    {Adresse	{text 3 40} adr		1}
    {M�l	{string 40} mel		1}
    {T�l	{string 15} tel		1}
    {Fax	{string 15} fax		1}
    {GSM	{string 15} mobile	1}
}
set libconf(editgroups) {
    {{Groupes Web}	{list multi ...} groupes 1}
}

#
# Tableaux (cf arrgen(n)) utilis�s dans ce package :
#	- choix : liste de choix d'utilisateurs avec login en url pour s�lection
#	- modif : formulaire d'ajout/modification d'un utilisateur
#	- liste : liste d'utilisateurs (pour consultation ou impression)
#

set libconf(tabchoix) {
	global {
	    chars {10 normal}
	    align {left}
	    botbar {yes}
	    columns {11 26 35 28 10}
	    latex {
		linewidth {267}
	    }
	}
	pattern Titre {
	    title {yes}
	    topbar {yes}
	    chars {bold}
	    align {center}
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	}
	pattern Utilisateur {
	    vbar {yes}
	    column {
		format {raw}
	    }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	}
    }

set libconf(tabmodif) {
	global {
	    align {left}
	    botbar {no}
	    columns {25 75}
	}
	pattern {Normal} {
	    vbar {no}
	    column { }
	    vbar {no}
	    column {
		format {raw}
	    }
	    vbar {no}
	}
    }

set libconf(tabliste) {
	global {
	    chars {10 normal}
	    align {left}
	    botbar {yes}
	    columns {8 16 32 10 10 10 14 10}
	    latex {
		linewidth {267}
	    }
	}
	pattern Titre {
	    title {yes}
	    topbar {yes}
	    chars {bold}
	    align {center}
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	}
	pattern Utilisateur {
	    chars {8}
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	    column { }
	    vbar {yes}
	}
    }

##############################################################################
# Acc�s � la base
##############################################################################

#
# Initialiser l'application Web auth
#
# Entr�e :
#   - param�tres :
#	- nologin : nom du fichier test� pour le mode "maintenance"
#	- base : param�tres d'acc�s � la base d'authentification
#	- groupe : groupe n�cessaire (ou vide si pas de groupe exig�)
#	- pagerr : fichier HTML contenant une page d'erreur
#	- form : les param�tres du formulaire
#	- ftabvar : tableau contenant en retour les champs du formulaire
#	- loginvar : login de l'utilisateur, en retour
# Sortie :
#   - valeur de retour : aucune
#   - param�tres :
#	- ftabvar : cf ci-dessus
#	- loginvar : cf ci-dessus
#
# Historique
#   2001/06/18 : pda      : conception
#   2002/12/26 : pda      : actualisation et mise en service
#   2003/05/13 : pda/jean : int�gration dans dns et utilisation de auth
#   2003/05/30 : pda/jean : r�utilisation pour l'application auth
#   2003/06/04 : pda/jean : simplification
#   2007/11/29 : pda/jean : ajout du param�tre groupe
#

proc init-auth {nologin base groupe pagerr form ftabvar loginvar} {
    upvar $ftabvar ftab
    upvar $loginvar login
    global authfd

    #
    # Pour le cas o� on est en mode maintenance
    #

    ::webapp::nologin $nologin %ROOT% $pagerr

    #
    # Acc�s � la base d'authentification
    #

    if {[catch {set authfd [pg_connect -conninfo $base]} msg]} then {
	::webapp::error-exit $pagerr $msg
    }

    #
    # Le login de l'utilisateur (la page est prot�g�e par mot de passe)
    #

    set login [::webapp::user]
    if {[string compare $login ""] == 0} then {
	::webapp::error-exit $pagerr \
		"Pas de login : l'authentification a �chou�."
    }

    #
    # V�rifier le groupe exig� si n�cessaire
    #

    if {! [string equal $groupe ""]} then {
	set qlogin  [::pgsql::quote $login]
	set qgroupe [::pgsql::quote $groupe]
	set sql "SELECT * FROM membres
			WHERE login = '$qlogin' AND groupe = '$qgroupe'"
	set trouve 0
	pg_select $authfd $sql tab {
	    set trouve 1
	}
	if {! $trouve} then {
	    ::webapp::error-exit $pagerr \
		    "Droits insuffisants pour l'op�ration."
	}
    }

    #
    # R�cup�ration des param�tres du formulaire
    #

    if {[string length $form] > 0} then {
	if {[llength [::webapp::get-data ftab $form]] == 0} then {
	    ::webapp::error-exit $pagerr \
		"Formulaire non conforme aux sp�cifications"
	}
    }

    return
}

#
# Terminer l'application Web auth
#
# Entr�e :
#   - param�tres : aucun
# Sortie :
#   - valeur de retour : aucune
#
# Historique
#   2007/11/29 : pda/jean : conception
#

proc end-auth {} {
    global authfd

    pg_disconnect $authfd
    return
}

##############################################################################
# Gestion des transactions
##############################################################################

#
# Effectue une transaction
#
# Entr�e :
#   - param�tres :
#	- kwd : "begin", "commit" ou "abort"
#	- msg : le message d'erreur en sortie
# Sortie :
#   - valeur de retour : 1 si tout est ok, 0 sinon
#   - param�tres :
#	- msg : message d'erreur si valeur de retour = 0
#
# Historique :
#   2003/08/04 : pda      : conception
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-transact {kwd msg} {
    upvar $msg m
    global authfd

    set r 0
    switch -- [string tolower $kwd] {
	begin {
	    set r [::pgsql::lock $authfd {utilisateurs membres} m]
	}
	commit {
	    set r [::pgsql::unlock $authfd "commit" m]
	}
	abort {
	    set r [::pgsql::unlock $authfd "abort" m]
	}
	default {
	    set m "Unknown mode '$kwd'"
	}
    }
    return $r
}

##############################################################################
# Gestion des utilisateurs
##############################################################################

#
# Lit l'entr�e d'un utilisateur
#
# Entr�e :
#   - param�tres :
#	- login : le login de l'utilisateur
#	- tab : tableau pass� en param�tre
# Sortie :
#   - valeur de retour : 1 si trouv�, 0 sinon
#   - param�tre tab : 
#	tab(login)	login
#	tab(nom)	nom
#	tab(prenom)	pr�nom
#	tab(mel)	adresse �lectronique
#	tab(tel)	t�l�phone fixe
#	tab(fax)	fax
#	tab(mobile)	t�l�phone mobile
#	tab(adr)	adresse
#	tab(encryption)	"crypt" si le mot de passe est crypt�
#	tab(password)	mot de passe crypt�
#	tab(groupes)	la liste des groupes auxquels l'utilisateur appartient
#
# Historique :
#   2003/05/13 : pda/jean : conception
#   2003/05/30 : pda/jean : ajout des groupes
#   2005/05/25 : pda/jean : ldapisation
#   2007/12/04 : pda/jean : d�-ldapisation
#

proc auth-getuser {login tab} {
    upvar $tab t
    global authfd libconf

    set trouve 0
    set qlogin [::pgsql::quote $login]
    set sql "SELECT * FROM utilisateurs WHERE login = '$qlogin'"
    pg_select $authfd $sql tabsql {
	foreach c $libconf(champs) {
	    set t($c) $tabsql($c)
	}
	set trouve 1
    }
    set t(groupes) {}
    set sql "SELECT groupe FROM membres WHERE login = '$qlogin'"
    pg_select $authfd $sql tabsql {
	lappend t(groupes) $tabsql(groupe)
    }
    return $trouve
}

#
# Modifie (ou cr�e) l'entr�e d'un utilisateur
#
# Entr�e :
#   - param�tres :
#	- tab : tableau pass� en param�tre, contenant les champs (cf getuser)
#	- transact : "transaction" (par d�faut) ou "pas de transaction"
# Sortie :
#   - valeur de retour : message d'erreur ou cha�ne vide si pas d'erreur
#
# Note : si le champ "mot de passe" est nul, un mot de passe crypt� "*" est
#   mis par d�faut (rendant le compte inaccessible).
#
# Historique :
#   2003/05/13 : pda/jean : conception
#   2003/05/30 : pda/jean : ajout des groupes
#   2003/08/05 : pda      : ajout des transactions
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-setuser {tab {transact transaction}} {
    upvar $tab t
    global authfd libconf

    if {! [regexp -- {^[a-z][-a-z0-9\.]*$} $t(login)]} then {
	return "Syntaxe invalide pour le login (^\[a-z\]\[-a-z0-9\.\]*$)"
    }

    #
    # Pour se simplifier la vie...
    #
    if {[string equal $transact "transaction"]} then {
	set tr 1
    } else {
	set tr 0
    }

    #
    # D�but de la transaction
    #
    if {$tr} then {
	if {![auth-transact "begin" m]} then {
	    return $m
	}
    }

    #
    # D�truit l'utilisateur.
    #
    set m [auth-deluser $t(login) "pas-de-transaction"]
    if {! [string equal $m ""]} then {
	if {$tr} then { auth-transact "abort" msg }
	return $m
    }

    #
    # Pr�caution : si le mot de passe n'existe pas, invalider
    # le login
    #
    if {! [info exists t(password)]} then {
	set t(password) "*"
    }

    #
    # Ins�rer les donn�es existantes de l'utilisateur dans
    # la base.
    #
    set cols {}
    set vals {}
    foreach c $libconf(champs) {
	if {[info exists t($c)]} then {
	    lappend cols $c
	    lappend vals "'[::pgsql::quote $t($c)]'"
	}
    }
    set cols [join $cols ","]
    set vals [join $vals ","]
    set sql "INSERT INTO utilisateurs ($cols) VALUES ($vals)"
    if {![::pgsql::execsql $authfd $sql msg]} then {
	if {$tr} then { auth-transact "abort" msg }
	return "Insertion de '$t(login)' impossible : $msg"
    }

    #
    # Ins�rer l'appartenance aux groupes
    #
    set sql ""
    foreach g $t(groupes) {
	append sql "INSERT INTO membres (login, groupe) VALUES
			('$t(login)', '$g') ;"
    }
    if {![::pgsql::execsql $authfd $sql msg]} then {
	if {$tr} then { auth-transact "abort" msg }
	return "Insertion des groupes de '$t(login)' impossible : $msg"
    }

    #
    # Fin de la transaction
    #
    if {$tr} then {
	if {![auth-transact "commit" m]} then {
	    return $m
	}
    }

    return ""
}

#
# Supprime l'entr�e d'un utilisateur
#
# Entr�e :
#   - param�tres :
#	- login : le login de l'utilisateur
#	- transact : "transaction" (par d�faut) ou "pas de transaction"
# Sortie :
#   - valeur de retour : message d'erreur ou cha�ne vide si pas d'erreur
#
# Historique :
#   2003/05/13 : pda/jean : conception
#   2003/05/30 : pda/jean : ajout des groupes
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-deluser {login {transact transaction}} {
    global authfd

    #
    # Pour se simplifier la vie...
    #
    if {[string equal $transact "transaction"]} then {
	set tr 1
    } else {
	set tr 0
    }

    if {$tr} then {
	if {![auth-transact "begin" m]} then {
	    return $m
	}
    }

    set qlogin [::pgsql::quote $login]
    set sql "DELETE FROM membres WHERE login = '$qlogin'"
    if {! [::pgsql::execsql $authfd $sql msg]} then {
	if {$tr} then { auth-transact "abort" m }
	return "Suppression des groupes de '$login' impossible : $msg"
    }

    set sql "DELETE FROM utilisateurs WHERE login = '$qlogin'"
    if {! [::pgsql::execsql $authfd $sql msg]} then {
	if {$tr} then { auth-transact "abort" m }
	return "Suppression de '$login' impossible : $msg"
    }


    if {$tr} then {
	if {![auth-transact "commit" m]} then {
	    return $m
	}
    }

    return ""
}

#
# Cherche des utilisateurs suivant des crit�res
#
# Entr�e :
#   - param�tres :
#	- tabcrit : tableau contenant les crit�res
#		login, nom, prenom, adr, mel, tel, mobile, fax ou groupe
#		ou phnom, phprenom pour les crit�res phon�tiques
#	- tri (optionnel) : liste de la forme {tri...}
#		o� tri = +/- suivi du nom du crit�re de tri
# Sortie :
#   - valeur de retour : liste des logins des utilisateurs trouv�s
#
# Note : chaque crit�re est exprim� sous forme d'une expression r�guli�re
#   contenant les caract�res g�n�riques "*" et "?" uniquement
#
# Historique :
#   2003/06/06 : pda/jean : conception
#   2003/08/01 : pda/jean : crit�re de s�lection phon�tique
#   2003/08/11 : pda      : recherche "or" sur plusieurs groupes
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-searchuser {tabcrit {tri {+nom +prenom}}} {
    upvar $tabcrit tabcriteres
    global authfd

    #
    # Constituer la clause "where"
    #

    set clauses {}
    set nwheres 0
    set from ""
    foreach c {login phnom phprenom nom prenom adr mel tel mobile
				fax groupe} {
	if {[info exists tabcriteres($c)]} then {
	    set re $tabcriteres($c)
	    if {! [string equal $re ""]} then {
		set re [::pgsql::quote $re]
		# quoter les caract�res sp�ciaux de SQL
		regsub -all -- {%} $re {\\%} re
		regsub -all -- {_} $re {\\_} re
		# transformer *nos* caract�res g�n�riques
		regsub -all -- {\*} $re {%} re
		regsub -all -- {\?} $re {_} re

		if {[string equal $c "groupe"]} then {
		    set from ", membres"
		    set table "membres"
		    lappend clauses "utilisateurs.login = membres.login"
		} else {
		    set table "utilisateurs"
		}

		if {[string equal $c "phnom"] || [string equal $c "phprenom"]} then {
		    lappend clauses "$table.$c = SOUNDEX('$re')"
		} elseif {[string equal $c "groupe"]} then {
		    set or {}
		    foreach g $tabcriteres(groupe) {
			set qg [::pgsql::quote $g]
			lappend or "$table.groupe = '$qg'"
		    }
		    if {[llength $or] > 0} then {
			set sor [join $or " OR "]
			lappend clauses "($sor)"
		    }
		} else {
		    # ILIKE = LIKE sans tenir compte de la casse
		    lappend clauses "$table.$c ILIKE '$re'"
		}
		incr nwheres
	    }
	}
    }
    if {$nwheres > 0} then {
	set where [join $clauses " AND "]
	set where "WHERE $where"
    } else {
	set where ""
    }

    #
    # Constituer le tri
    #

    set sqltri {}
    set sqldistinct {}
    foreach t $tri {
	set sens [string range $t 0 0]
	set colonne [string range $t 1 end]
	switch -- $sens {
	    -		{ set sens "DESC" }
	    +  		-
	    default	{ set sens "ASC" }
	}
	if {[lsearch $colonne {login nom prenom mel tel adr mobile fax}]} then {
	    lappend sqltri "utilisateurs.$colonne $sens"
	    lappend sqldistinct utilisateurs.$colonne
	}
    }
    if {[llength $sqltri] == 0} then {
	set orderby ""
    } else {
	set orderby [join $sqltri ", "]
	set orderby "ORDER BY $orderby"
    }

    if {[llength $sqldistinct] == 0} then {
	set distinct ""
    } else {
	set distinct [join $sqldistinct ", "]
	set distinct "DISTINCT ON ($distinct)"
    }

    #
    # Construire la liste des logins trouv�s
    #

    set lusers {}
    set sql "SELECT $distinct utilisateurs.login
		FROM utilisateurs $from
		$where
		$orderby"
    pg_select $authfd $sql tab {
	lappend lusers $tab(login)
    }

    return $lusers
}

#
# Chiffre un mot de passe
#
# Entr�e :
#   - param�tres :
#	- chaine : la cha�ne � chiffrer
# Sortie :
#   - valeur de retour : la cha�ne chiffr�e
#
# Historique :
#   2003/05/13 : pda/jean : conception de l'interface
#   2005/07/22 : pda/jean : s�curisation des caract�res sp�ciaux
#

proc auth-crypt {chaine} {
    global libconf

    regsub -all {['\\]} $chaine {\\&} chaine
    set c [exec sh -c "$libconf(trpw) '$chaine'"]
    return $c
}

#
# G�n�re un mot de passe semi-al�atoire.
#
# Entr�e :
#   - param�tres : (aucun)
# Sortie :
#   - valeur de retour : le mot de passe g�n�r� en clair
#
# Note : utilise le "port" sysutils/pwgen
#
# Historique :
#   2003/06/13 : pda/jean : conception
#

proc auth-genpw {} {
    global libconf

    set p [exec sh -c $libconf(genpw)]
    return $p
}

#
# Traite les diff�rentes actions de changement de mot de passe
#
# Entr�e :
#   - param�tres :
#	- login : login de l'utilisateur dont il faut changer le mot de passe
#	- action : liste de la forme {action param�tres} o� 
#		action = "block"    (pas de param�tres)
#		action = "generate" (pas de param�tres)
#		action = "change"   (param�tres = deux fois le passwd en clair)
#	- mail : {mail} ou {nomail} suivant qu'il faut envoyer le nouveau
#		mot de passe par mail ou non
#		dans le cas "mail", le param�tre est compl�t� par une
#		liste. Il s'agit alors de :
#			{mail from replyto cc bcc subject body}
#	- newpw : variable pass�e par r�f�rence, devant contenir le nouveau
#		mot de passe en retour
# Sortie :
#   - valeur de retour : message d'erreur, ou cha�ne vide si pas d'erreur
#
# Historique :
#   2003/06/13 : pda/jean : conception
#   2003/12/08 : pda      : param�tre "mail" plus complet
#

proc auth-chpw {login action mail newpwvar} {
    upvar $newpwvar newpw
    global libconf

    if {! [auth-getuser $login tab]} then {
	return "Login '$login' inexistant"
    }

    switch -- [lindex $action 0] {
	block {
	    set newpw "<invalid>"
	    set tab(password) "*"
	}
	generate {
	    set newpw [auth-genpw]
	    set tab(password) [auth-crypt $newpw]
	}
	change {
	    set pw1 [lindex $action 1]
	    set pw2 [lindex $action 2]

	    if {! [string equal $pw1 $pw2]} then {
		return "Les deux mots de passe sont diff�rents"
	    }
	    set newpw $pw1

	    if {[regexp {[\\'"`()]} $newpw]} then {
		return "Utilisation de caract�res interdits"
	    }

	    if {[string length $newpw] < $libconf(minpwlen)} then {
		return "Mot de passe trop court (< $libconf(minpwlen) caract�res)"
	    }
	    set newpw [string range $newpw 0 [expr $libconf(maxpwlen)-1]]

	    set tab(password) [auth-crypt $newpw]
	}
	default {
	    return "Param�tre 'action' non valide ($action)"
	}
    }

    if {[string equal [lindex $mail 0] "mail"]} then {
	set from [lindex $mail 1]
	set repl [lindex $mail 2]
	set cc   [lindex $mail 3]
	set bcc  [lindex $mail 4]
	set subj [lindex $mail 5]
	set body [lindex $mail 6]
	if {[::webapp::valid-email $tab(mel)]} then {
	    if {[::webapp::valid-email $from]} then {
		set body [format $body $login $newpw]
		::webapp::mail $from $repl $tab(mel) $cc $bcc $subj $body
	    }
	} else {
	    return "Mot de passe non modifi�, adresse m�l non valide."
	}
    }

    return [auth-setuser tab]
}

##############################################################################
# Gestion des groupes
##############################################################################

#
# Liste les groupes existants dans la base
#
# Entr�e :
#   - param�tres :
#	- tab : tableau contenant en retour la liste des groupes
#		tab(<groupe>) {<descr> <liste des membres>}
# Sortie :
#   - valeur de retour : 1 (ok) ou 0 (erreur)
#
# Historique :
#   2003/05/30 : pda/jean : conception
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-lsgroup {tab} {
    upvar $tab t
    global authfd

    set sql "SELECT * FROM groupes"
    pg_select $authfd $sql tabsql {
	set groupe $tabsql(groupe)
	set descr $tabsql(descr)
	set membres {}
	set sqlm "SELECT login FROM membres WHERE groupe = '$groupe'"
	pg_select $authfd $sqlm tabm {
	    lappend membres $tabm(login)
	}
	set t($groupe) [list $descr $membres]
    }
    return 1
}

#
# Ajoute un groupe � la base
#
# Entr�e :
#   - param�tres :
#	- groupe : nom du groupe
#	- descr : description du groupe
#	- msgvar : variable contenant en retour le message d'erreur
# Sortie :
#   - valeur de retour : 1 (ok) ou 0 (erreur)
#   - param�tre msgvar : message d'erreur si erreur
#
# Historique :
#   2003/05/30 : pda/jean : conception
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-addgroup {groupe descr msgvar} {
    upvar $msgvar msg
    global authfd

    if {! [regexp -- {^[a-z][-a-z0-9]*$} $groupe]} then {
	set msg "Syntaxe invalide pour le groupe (^\[a-z\]\[-a-z0-9\]*$)"
	return 0
    }

    set qgroupe [::pgsql::quote $groupe]
    set qdescr  [::pgsql::quote $descr]
    set sql "INSERT INTO groupes VALUES ('$qgroupe', '$qdescr')"
    if {! [::pgsql::execsql $authfd $sql m]} then {
	set msg "Insertion du groupe '$groupe' impossible ($m)"
	set r 0
    } else {
	set r 1
    }
    return $r
}

#
# Supprime un groupe � la base
#
# Entr�e :
#   - param�tres :
#	- groupe : nom du groupe � supprimer
#	- msgvar : variable contenant en retour le message d'erreur
# Sortie :
#   - valeur de retour : 1 (ok) ou 0 (erreur)
#   - param�tre msgvar : message d'erreur si erreur
#
# Note : cette fonction ne d�truit pas les groupes ayant des membres
#   (gr�ce � la contrainte d'int�grit� r�f�rentielle).
#
# Historique :
#   2003/05/30 : pda/jean : conception
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-delgroup {groupe msgvar} {
    upvar $msgvar msg
    global authfd

    set qgroupe [::pgsql::quote $groupe]
    set sql "DELETE FROM groupes WHERE groupe = '$qgroupe'"
    if {! [::pgsql::execsql $authfd $sql m]} then {
	set msg "Suppression du groupe '$groupe' impossible ($m)"
	set r 0
    } else {
	set r 1
    }
    return $r
}

#
# Modifie un groupe dans la base
#
# Entr�e :
#   - param�tres :
#	- groupe : nom du groupe � modifier
#	- descr : description du groupe
#	- membres : liste des membres
#	- msgvar : liste des membres
# Sortie :
#   - valeur de retour : 1 (ok) ou 0 (erreur)
#   - param�tre msgvar : message d'erreur si erreur
#
# Historique :
#   2003/06/04 : pda/jean : conception
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-setgroup {groupe descr membres msgvar} {
    upvar $msgvar msg
    global authfd

    set qgroupe [::pgsql::quote $groupe]

    #
    # D�but de la transaction
    #
    if {![auth-transact "begin" msg]} then {
	return 0
    }

    #
    # Si le groupe n'existe pas, le cr�er
    # S'il existe, modifier la description.
    #
    set sql "SELECT groupe FROM groupes WHERE groupe = '$qgroupe'"
    set trouve 0
    pg_select $authfd $sql tab {
	set trouve 1
    }
    if {! $trouve} then {
	if {! [auth-addgroup $groupe $descr msg]} then {
	    set msg "Impossible de cr�er '$groupe' ($msg)"
	    auth-transact "abort" bidon
	    return 0
	}
    } else {
	set qdescr [::pgsql::quote $descr]
	set sql "UPDATE groupes
			SET descr = '$qdescr'
			WHERE groupe = '$qgroupe'"
	if {! [::pgsql::execsql $authfd $sql m]} then {
	    set msg "Mise � jour de '$groupe' impossible ($m)"
	    auth-transact "abort" bidon
	    return 0
	}
    }

    #
    # D�truire la liste des membres du groupe
    #
    set sql "DELETE FROM membres WHERE groupe = '$qgroupe'"
    if {! [::pgsql::execsql $authfd $sql m]} then {
	set msg "Suppression des membres de '$groupe' impossible ($m)"
	auth-transact "abort" bidon
	return 0
    }

    #
    # Actualiser la liste des membres
    #
    foreach login $membres {
	set qlogin [::pgsql::quote $login]
	set sql "INSERT INTO membres (login, groupe)
			VALUES ('$qlogin', '$qgroupe')"
	if {! [::pgsql::execsql $authfd $sql m]} then {
	    set msg "Mise � jour de '$login/$groupe' impossible ($m)"
	    auth-transact "abort" bidon
	    return 0
	}
    }

    #
    # Fin de la transaction
    #
    if {! [auth-transact "commit" m]} then {
	set msg "Transaction pour '$groupe' impossible ($m)"
	auth-transact "abort" bidon
	return 0
    }

    return 1
}

#
# Retourne un menu HTML pour s�lectionner un ou plusieurs groupes
#
# Entr�e :
#   - param�tres :
#	- var : nom de la variable (champ) de formulaire � g�n�rer
#	- multiple : 1 si choix multiple autoris�, 0 si choix simple
#	- groupesel : liste de groupes pr�-s�lectionn�s (ou vide)
# Sortie :
#   - valeur de retour : code HTML
#
# Historique :
#   2003/06/03 : pda/jean : conception
#   2003/06/13 : pda/jean : ajout du param�tre groupesel
#   2003/06/27 : pda      : mise en package
#

proc auth-htmlgrpmenu {var multiple groupesel} {
    #
    # M�moriser les groupes pr�-s�lectionn�s
    #
    foreach g $groupesel {
	set tabsel($g) ""
    }

    #
    # R�cup�rer la liste des groupes dans la base
    #
    if {! [auth-lsgroup tabgrp]} then {
	return ""
    }

    #
    # Constituer la liste de clef/valeurs pour le menu
    #

    set liste {}
    set lsel {}
    set idx 0
    foreach g [lsort [array names tabgrp]] {
	lappend liste [list $g $g]
	if {[info exists tabsel($g)]} then {
	    lappend lsel $idx
	}
	incr idx
    }

    #
    # Autoriser les choix multiples ou non ?
    #

    if {$multiple} then {
	set taille [llength [array names tabgrp]]
    } else {
	set taille 1
    }

    return [::webapp::form-menu $var $taille $multiple $liste $lsel]
}

##############################################################################
# Gestion des param�tres de configuration
##############################################################################

#
# Retourne un param�tre de configuration
#
#
# Entr�e :
#   - param�tres :
#       - clef : clef repr�sentant le param�tre de configuration
# Sortie :
#   - valeur de retour : valeur associ�e � la clef
#
# Historique :
#   2003/12/14 : pda      : conception
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-getconfig {clef} {
    global authfd

    set sql "SELECT * FROM config WHERE clef = '$clef'"
    set valeur {}
    pg_select $authfd $sql tab {
	set valeur $tab(valeur)
    }
    return $valeur
}

#
# Stocke un param�tre de configuration
#
#
# Entr�e :
#   - param�tres :
#       - clef : clef repr�sentant le param�tre de configuration
#       - valeur : valeur � associer � la clef
#       - varmsg : message d'erreur lors de l'�criture, si besoin
# Sortie :
#   - valeur de retour : 1 si ok, ou 0 en cas d'erreur
#   - param�tre varmsg : message d'erreur �ventuel
#
# Historique :
#   2003/12/14 : pda      : d�but de la conception
#   2007/12/04 : pda/jean : sp�cialisation pgsql
#

proc auth-setconfig {clef val varmsg} {
    upvar $varmsg msg
    global authfd

    set r 0
    set sql "DELETE FROM config WHERE clef = '$clef'"
    if {[::pgsql::execsql $authfd $sql msg]} then {
	set v [::pgsql::quote $val]
	set sql "INSERT INTO config VALUES ('$clef', '$v')"
	if {[::pgsql::execsql $authfd $sql msg]} then {
	    set r 1
	}
    }
    return $r
}

##############################################################################
# Gestion HTML des utilisateurs
##############################################################################

#
# El�ment central des scripts CGI des applications pour la gestion
# des utilisateurs
#
# Entr�e :
#   - param�tres :
#	- e : environnement d'ex�cution du script, sous la forme d'un
#		tableau index� :
#		url : url du script appelant cette fonction
#		groupes : liste de groupes auxquels peuvent appartenir les
#			utilisateur de l'application
#			Si groupes = {}, on peut acc�der � tous les groupes
#			Si un seul groupe, on ne pr�sente pas la liste des
#				groupes lors de l'ajout d'un utilisateur
#		maxgroupes : nombre maximum de groupes affich�s dans la listbox
#			ou 0 pour prendre le nb exact de groupes affich�s.
#		page-* : les fonds de page (HTML/Latex) avec les
#			trous, index� par le nom de la page :
#			-menu : page d'accueil des diff�rentes actions
#			-ok : action effectu�e
#			-erreur : erreur d�tect�e
#			-ajoutinit : page d'accueil de l'ajout
#			-choix : choix des utilisateurs si plus d'un trouv�
#			-modif : �dition des param�tres d'un utilisateur
#			-suppr : confirmation de suppression d'un utilisateur
#			-passwd : actions sur le mot de passe d'un utilisateur
#			-liste : liste d'utilisateurs
#			-listetex : liste d'utilisateurs en format latex
#			-sel : s�lection suivant crit�res
#		specif : liste des informations d'utilisateur sp�cifiques �
#			l'application, sous la forme :
#				{{<titre de l'info> <type>} ...}
#			avec :
#			- type : cf ::webapp::form-field
#		script-* : tableau contenant les scripts � ex�cuter pour acc�der
#			et pr�senter les caract�ristiques des utilisateurs sp�cifiques 
#			� l'application, index� par :
#			- getuser : pr�sentation des informations 
#				retourne une liste de la forme {valeur ...} dans le
#				m�me ordre que dans la liste "specif"
#			- deluser : d�truit l'utilisateur de l'application
#			- setuser : ajoute ou modifie l'utilisateur dans l'application
#			- chkuser : v�rifie si modif utilisateur autoris�e
#		mailfrom : champ du mail envoy� en cas de g�n�ration de pw
#		mailreplyto : champ du mail envoy� en cas de g�n�ration de pw
#		mailcc : champ du mail envoy� en cas de g�n�ration de pw
#		mailbcc : champ du mail envoy� en cas de g�n�ration de pw
#		mailsubject : champ du mail envoy� en cas de g�n�ration de pw
#		mailbody : corps du mail envoy� en cas de g�n�ration de pw
# Sortie :
#   - valeur de retour : aucune
#   - sortie standard : une page HTML pr�te � �tre envoy�e
#
# Historique :
#   2003/07/29 : pda      : d�but de la conception
#   2003/07/31 : pda/jean : r�alisation
#   2003/12/14 : pda      : ajout de mail*
#

proc auth-usermanage {evar} {
    upvar $evar e

    set form {
	{action 0 1}
	{etat   0 1}
    }
    auth-get-data ftab $form $e(page-erreur)
    set action [lindex $ftab(action) 0]
    set etat   [lindex $ftab(etat)   0]

    switch -- $action {
	ajout   { set l [auth-um-ajout     e ftab $etat] }
	consult -
	impr    { set l [auth-um-consimpr  e ftab $etat $action] }
	suppr   -
	modif   -
	passwd  { set l [auth-um-supmodpwd e ftab $etat $action] }
	default { set l [auth-um-rien      e ftab $etat] }
    }
    set format [lindex $l 0]
    set page   [lindex $l 1]
    set lsubst [lindex $l 2]

    lappend lsubst [list %ACTION% $action]
    lappend lsubst [list %URL% $e(url)]
    ::webapp::send $format [::webapp::file-subst $page $lsubst]
    exit 0
}

proc auth-get-data {ftabvar form err} {
    upvar $ftabvar ftab

    if {[llength [::webapp::get-data ftab $form]] != [llength $form]} then {
	::webapp::error-exit $err "Formulaire non conforme ($ftab(_error))"
    }
}

proc auth-um-rien {evar ftabvar etat} {
    upvar $evar e
    upvar $ftabvar ftab

    return [list "html" $e(page-menu) {}]
}

proc auth-um-ajout {evar ftabvar etat} {
    upvar $evar e
    upvar $ftabvar ftab

    set lsubst {}
    switch -- $etat {
	nom {
	    #
	    # Le nom de l'utilisateur � ajouter a �t� introduit.
	    # Il faut le chercher dans la base, parmi tous les groupes.
	    #
	    set form {
		    {nom 1 1}
		}
	    auth-get-data ftab $form $e(page-erreur)

	    set nom [lindex $ftab(nom) 0]
	    set tabcrit(phnom) $nom
	    set lut [auth-searchuser tabcrit {+nom +prenom}]
	    set nbut [llength $lut]

	    if {$nbut > 0} then {
		#
		# Des utilisateurs correspondant au nom ont �t� trouv�s.
		# Demander si ce n'est pas un de ceux-l�.
		#
		# Trous � remplir :
		#	%ACTION%
		#	%MESSAGE%
		#	%LISTEUTILISATEURS%
		#	%AUCUN%
		#
		set message "Plusieurs utilisateurs pr�sentent des similitudes"
		append message " avec [::webapp::html-string $nom]. <P>"
		append message " Choisissez celui qui vous convient,"
		append message " ou alors demandez la cr�ation d'un nouvel"
		append message " utilisateur."
		lappend lsubst [list %MESSAGE% $message]

		set url "$e(url)?action=ajout&etat=plusdun"
		lappend lsubst [list %LISTEUTILISATEURS% \
				    [auth-um-afficher-choix e $url $lut] \
				]

		set aucun "<FORM METHOD=POST ACTION=\"$e(url)\">\n"
		append aucun [::webapp::form-hidden "action" "ajout"]
		append aucun [::webapp::form-hidden "etat" "nouveau"]
		append aucun [::webapp::form-hidden "nom" $nom]
		append aucun "<INPUT TYPE=SUBMIT VALUE=\"Cr�er un nouvel utilisateur\">"
		append aucun "</FORM>\n"
		lappend lsubst [list %AUCUN% $aucun]

		set page $e(page-choix)
	    } else {
		#
		# Aucun utilisateur trouv�. Pr�parer le formulaire
		# pour rentrer un nouvel utilisateur.
		#
		# Trous � remplir :
		#	%ACTION%
		#	%ETAT%
		#	%LOGIN%
		#	%PARAMUTILISATEUR%
		#	%TITRE%
		#
		set lsubst [auth-um-afficher-modif e "_nouveau" $nom]
		set page $e(page-modif)
	    }
	}
	plusdun {
	    #
	    # Un utilisateur s�lectionn�. Pr�parer le formulaire
	    # pour rentrer les modifications de l'utilisateur.
	    #
	    # Trous � remplir :
	    #	%ACTION%
	    #	%ETAT%
	    #	%LOGIN%
	    #	%PARAMUTILISATEUR%
	    #	%TITRE%
	    #
	    set form {
		    {login 1 1}
		}
	    auth-get-data ftab $form $e(page-erreur)

	    set login [lindex $ftab(login) 0]
	    set lsubst [auth-um-afficher-modif e $login ""]
	    set page $e(page-modif)
	}
	nouveau {
	    #
	    # Demande de cr�ation d'utilisateur. Pr�parer le formulaire
	    # pour rentrer un nouvel utilisateur.
	    #
	    # Trous � remplir :
	    #	%ACTION%
	    #	%LOGIN%
	    #	%PARAMUTILISATEUR%
	    #
	    set form {
		    {nom 0 1}
		}
	    auth-get-data ftab $form $e(page-erreur)

	    set nom [lindex $ftab(nom) 0]

	    set lsubst [auth-um-afficher-modif e "_nouveau" $nom]
	    set page $e(page-modif)
	}
	creation {
	    #
	    # Formulaire de saisie de nouvel utilisateur rempli.
	    # Cr�er l'utilisateur, puis passer directement � la
	    # page de changement de mot de passe.
	    #
	    # Trous � remplir :
	    #	%ACTION% (passwd)
	    #	%LOGIN%
	    #
	    set form {
		    {login 1 1}
	    }
	    auth-get-data ftab $form $e(page-erreur)

	    set login [lindex $ftab(login) 0]
	    if {[auth-getuser $login u]} then {
		::webapp::error-exit $e(page-erreur) \
			"Le login '$login' existe d�j�."
	    }

	    #
	    # Nouvel utilisateur. On ignore le compl�ment et on
	    # passe tout de suite � la page de modification de mot
	    # de passe.
	    #
	    auth-um-enregistrer-modif e ftab $login

	    set lsubst [concat $lsubst [auth-um-afficher-passwd e $login]]
	    set page $e(page-passwd)
	}
	ok {
	    #
	    # Enregistrement d'utilisateur existant (modification).
	    #
	    # Trous � remplir :
	    #	%TITREACTION% (ajout)
	    #	%COMPLEMENT%
	    #
	    set form {
		    {login 1 1}
	    }
	    auth-get-data ftab $form $e(page-erreur)

	    set login [lindex $ftab(login) 0]
	    if {! [auth-getuser $login u]} then {
		::webapp::error-exit $e(page-erreur) \
			"Le login '$login' n'existe pas."
	    }

	    #
	    # Utilisateur existant dans la base
	    #
	    set lsubst [auth-um-enregistrer-modif e ftab $login]
	    set page $e(page-ok)
	}
	default {
	    set page $e(page-ajoutinit)
	}
    }
    return [list "html" $page $lsubst]
}

proc auth-um-consimpr {evar ftabvar etat mode} {
    upvar $evar e
    upvar $ftabvar ftab
    global libconf

    set lsubst {}
    set format "html"
    switch -- $etat {
	criteres {
	    #
	    # Crit�res de choix entr�s.
	    #
	    # Trous � remplir :
	    #	%NBUTILISATEURS%
	    #	%S%
	    #	%DATE%
	    #	%HEURE%
	    #	%TABLEAU%
	    #

	    set lut [auth-um-chercher-criteres e ftab]
	    if {[llength $lut] == 0} then {
		#
		# Aucun utilisateur trouv�. Pr�senter de nouveau
		# la page de s�lection de crit�res
		#
		set lsubst [auth-um-afficher-criteres e ftab \
				    "Aucun utilisateur trouv�"]
		set page $e(page-sel)
	    } else {
		#
		# D�terminer le format de sortie
		#

		switch $mode {
		    consult {
			set tabfmt "html"
			set page $e(page-liste)
		    }
		    impr {
			set format "pdf"
			set tabfmt "latex"
			set page $e(page-listetex)
		    }
		}

		#
		# Pr�senter la liste des utilisateurs
		#

		set donnees {}
		lappend donnees {Titre Login {Nom et pr�nom}
					Adresse M�l T�l Fax GSM {Groupes Web}}
		foreach login $lut {
		    if {[auth-getuser $login tab]} then {
			set mesgroupes [auth-um-mes-groupes e $tab(groupes)]
			lappend donnees [list Utilisateur \
					    $tab(login) \
					    "$tab(nom) $tab(prenom)" \
					    $tab(adr) \
					    $tab(mel) \
					    $tab(tel) $tab(fax) $tab(mobile) \
					    $mesgroupes
					] \
		    }
		}
		set tableau [::arrgen::output $tabfmt $libconf(tabliste) $donnees]

		#
		# Cosm�tique : nb d'utilisateurs avec ou sans s...
		#

		set nbut [llength $lut]
		set s ""
		if {$nbut > 1} then { set s "s" }

		#
		# Cosm�tique : date et heure
		#

		set date  [clock format [clock seconds] -format "%d/%m/%Y"]
		set heure [clock format [clock seconds] -format "%Hh%M"]

		lappend lsubst [list %TABLEAU% $tableau]
	    	lappend lsubst [list %NBUTILISATEURS% [llength $lut]]
		lappend lsubst [list %S% $s]
		lappend lsubst [list %DATE% $date]
		lappend lsubst [list %HEURE% $heure]
	    }
	}
	default {
	    #
	    # Page initiale pour saisir les crit�res de choix
	    #
	    # Trous � remplir :
	    #	%ACTION%
	    #	%MESSAGE%
	    #	%CRITERES%
	    #
	    set lsubst [auth-um-afficher-criteres e ftab ""]
	    set page $e(page-sel)
	}
    }
    return [list $format $page $lsubst]
}

proc auth-um-supmodpwd {evar ftabvar etat action} {
    upvar $evar e
    upvar $ftabvar ftab

    switch -- $etat {
	criteres {
	    #
	    # Crit�res de choix entr�s.
	    #
	    # Trous � remplir :
	    #	%LOGIN%
	    #	%NOM%
	    #	%PRENOM%
	    #

	    set lut [auth-um-chercher-criteres e ftab]
	    switch [llength $lut] {
		0 {
		    #
		    # Aucun utilisateur trouv�. Pr�senter de nouveau
		    # la page de s�lection de crit�res
		    #
		    set lsubst [auth-um-afficher-criteres e ftab \
					"Aucun utilisateur trouv�"]
		    set page $e(page-sel)
		}
		1 {
		    #
		    # Pr�senter la page de suppression, de modif ou de passwd
		    #
		    set login [lindex $lut 0]
		    switch -- $action {
			suppr {
			    set lsubst [auth-um-afficher-suppr e $login]
			    set page $e(page-suppr)
			}
			modif {
			    set lsubst [auth-um-afficher-modif e $login ""]
			    set page $e(page-modif)
			}
			passwd {
			    set lsubst [auth-um-afficher-passwd e $login]
			    set page $e(page-passwd)
			}
			default {
			    set lsubst [list %MESSAGE% "Formulaire non conforme"]
			    set page $e(page-erreur)
			}
		    }
		}
		default {
		    #
		    # Des utilisateurs correspondant au nom ont �t� trouv�s.
		    # Pr�senter la liste pour le choix.
		    #
		    # Trous � remplir :
		    #	%ACTION%
		    #	%MESSAGE%
		    #	%LISTEUTILISATEURS%
		    #	%AUCUN%
		    #
		    set message "Plusieurs utilisateurs r�pondent aux crit�res"
		    append message " Choisissez celui qui vous convient."
		    lappend lsubst [list %MESSAGE% $message]

		    set url "$e(url)?action=$action&etat=plusdun"
		    lappend lsubst [list %LISTEUTILISATEURS% \
					[auth-um-afficher-choix e $url $lut] \
				    ]

		    lappend lsubst [list %AUCUN% ""]
		    set page $e(page-choix)
		}
	    }
	}
	plusdun {
	    #
	    # Pr�senter la page de suppression, de modif ou de passwd
	    #
	    set form {
		{login 1 1}
	    }
	    auth-get-data ftab $form $e(page-erreur)

	    set login [lindex $ftab(login) 0]

	    if {! [auth-getuser $login u]} then {
		::webapp::error-exit $e(page-erreur) \
			"Le compte '$login' n'existe pas."
	    }

	    switch -- $action {
		suppr {
		    set lsubst [auth-um-afficher-suppr e $login]
		    set page $e(page-suppr)
		}
		modif {
		    set lsubst [auth-um-afficher-modif e $login ""]
		    set page $e(page-modif)
		}
		passwd {
		    set lsubst [auth-um-afficher-passwd e $login]
		    set page $e(page-passwd)
		}
		default {
		    set lsubst [list %MESSAGE% "Formulaire non conforme"]
		    set page $e(page-erreur)
		}
	    }

	}
	ok {
	    #
	    # Accomplir l'action
	    #

	    set form {
		{login 1 1}
	    }
	    auth-get-data ftab $form $e(page-erreur)

	    set login [lindex $ftab(login) 0]

	    if {! [auth-getuser $login u]} then {
		::webapp::error-exit $e(page-erreur) \
			"Le login '$login' n'existe pas."
	    }

	    set page $e(page-ok)
	    switch -- $action {
		suppr {
		    set lsubst [auth-um-supprime-utilisateur e ftab $login]
		}
		modif {
		    set lsubst [auth-um-enregistrer-modif e ftab $login]
		}
		passwd {
		    set lsubst [auth-um-enregistrer-passwd e ftab $login]
		}
		default {
		    set lsubst [list %MESSAGE% "Formulaire non conforme"]
		    set page $e(page-erreur)
		}
	    }
	}
	default {
	    #
	    # Page initiale pour saisir les crit�res de choix
	    #
	    # Trous � remplir :
	    #	%ACTION%
	    #	%MESSAGE%
	    #	%CRITERES%
	    #
	    set lsubst [auth-um-afficher-criteres e ftab ""]
	    set page $e(page-sel)
	}
    }

    return [list "html" $page $lsubst]
}

#
# Proc�dures auxiliaires de auth-usermanage
#

#
# Retourne une liste de groupes extraite de "groupes", dans laquelle
# ne figurent que les groupes affichables inscrits dans e(groupes)
# avec tous les groupes si e(groupes) est vide.
#

proc auth-um-mes-groupes {evar groupes} {
    upvar $evar e

    if {[llength $e(groupes)] == 0} then {
	set rg $groupes
    } else {
	foreach g $e(groupes) {
	    set x($g) 0
	}
	set rg {}
	foreach g $groupes {
	    if {[info exists x($g)]} then {
		lappend rg $g
	    }
	}
    }
    return $rg
}

#
# G�n�re une liste d'utilisateurs avec url associ�e
#
# Retour : valeur pour le trou %LISTEUTILISATEURS%
#

proc auth-um-afficher-choix {evar url lut} {
    upvar $evar e
    global libconf

    set donnes {}
    lappend donnees {Titre Login {Nom et pr�nom} Adresse M�l {Groupes Web}}
    foreach login $lut {
	if {[auth-getuser $login tab]} then {
	    set qlogin [::webapp::post-string $login]
	    set hlogin [::webapp::html-string $login]
	    set urllogin "<A HREF=\"$url&login=$qlogin\">$hlogin</A>"
	    set mesgroupes [auth-um-mes-groupes e $tab(groupes)]
	    lappend donnees [list Utilisateur \
					$urllogin "$tab(nom) $tab(prenom)" \
					$tab(adr) $tab(mel) $mesgroupes
				    ]
	}
    }
    return [::arrgen::output "html" $libconf(tabchoix) $donnees]
}

#
# G�n�re un bout de formulaire pour rentrer les informations d'un
# nouvel utilisateur (ou les modifications d'un utilisateur existant).
#
# Retour : liste de substitution pour les trous %LOGIN%, %PARAMUTILISATEUR%
#	%ETAT% et %TITRE%
#

proc auth-um-afficher-modif {evar login nom} {
    upvar $evar e
    global libconf

    #
    # R�cup�rer les informations d'auth pour l'utilisateur, ou en
    # simuler s'il s'agit d'une cr�ation
    #

    set nouveau [string equal $login "_nouveau"]
    if {$nouveau} then {
	array set u {
	    login {}
	    nom {}
	    prenom {}
	    adr {}
	    mel {}
	    tel {}
	    fax {}
	    mobile {}
	    groupes {}
	}
	set u(nom) $nom
	set etat  "creation"
	set titre "Ajout"
    } else {
	if {! [auth-getuser $login u]} then {
	    ::webapp::error-exit $e(page-erreur) \
		"L'utilisateur '$login' n'existe pas !"
	}
	set etat  "ok"
	set titre "Modification"
    }

    #
    # Choix de l'�dition des groupes
    #

    set menugroupes [auth-build-group-menu "list" \
				0 $e(groupes) $e(maxgroupes) gidx]

    #
    # R�cup�re les valeurs existantes, ou les valeurs par d�faut
    # d'un nouvel utilisateur
    #

    set valu [uplevel 3 [format $e(script-getuser) $login]]


    #
    # G�n�rer les champs de saisie des informations de auth
    #

    set donnees {}

    foreach c [concat $libconf(editfields) $libconf(editgroups)] {
	set ctitre [lindex $c 0]
	set spec   [lindex $c 1]
	set var    [lindex $c 2]
	set user   [lindex $c 3]
	if {[string equal $var "login"] && ! $nouveau} then {
	    #
	    # cas sp�cial pour le champ 'login' lorsqu'il est �ditable
	    #
	    set t [::webapp::html-string $login]
	    append t [::webapp::form-hidden "login" $login]
	} elseif {[string equal $var "groupes"]} then {
	    #
	    # Cas sp�cial pour les groupes
	    #
	    if {[llength $menugroupes] == 0} then {
		set t ""
	    } else {
		set lidx {}
		foreach g $u(groupes) {
		    if {[info exists gidx($g)]} then {
			lappend lidx $gidx($g)
		    }
		}
		set t [::webapp::form-field $menugroupes $var $lidx]
	    }
	} elseif {$user} then {
	    #
	    # Cas g�n�ral : c'est un champ � modifier
	    #
	    set t [::webapp::form-field $spec $var $u($var)]
	} else {
	    #
	    # Sinon, il s'agit d'un champ seulement pour la recherche
	    # comme apr exemple phnom et phprenom
	    #
	    set t ""
	}

	if {! [string equal $t ""]} then {
	    set l [list Normal $ctitre $t]
	    lappend donnees $l
	}
    }

    #
    # G�n�rer les champs de saisie propres � l'application
    #

    set n 0
    foreach c $e(specif) v $valu {
	incr n
	set ctitre [lindex $c 0]
	set spec   [lindex $c 1]
	set var    "uvar$n"
	lappend donnees [list Normal $ctitre [::webapp::form-field $spec $var $v]]
    }

    set paramutilisateur [::arrgen::output html $libconf(tabmodif) $donnees]

    #
    # G�n�rer les listes de substitution
    #

    lappend lsubst [list %LOGIN%	    $login]
    lappend lsubst [list %PARAMUTILISATEUR% $paramutilisateur]
    lappend lsubst [list %ETAT%		    $etat]
    lappend lsubst [list %TITRE%	    $titre]

    return $lsubst
}

#
# Enregistre les informations d'un utilisateur (nouveau ou modification)
#
# Retour : liste de substitution pour les trous %TITREACTION% et %COMPLEMENT%
#

proc auth-um-enregistrer-modif {evar ftabvar login} {
    upvar $evar e
    upvar $ftabvar ftab
    global libconf

    #
    # V�rifier si le script a bien le droit de modifier l'utilisateur
    #
    set msg [uplevel 3 [format $e(script-chkuser) $login]]
    if {! [string equal $msg ""]} then {
    	::webapp::error-exit $e(page-erreur) \
		"Impossible de modifier '$login' ($msg)"
    }

    #
    # Extraire les champs de formulaire (le login a d�j� �t� r�cup�r�,
    # mais on le re-r�cup�re quand m�me).
    #

    set form [auth-build-form-spec "modif" \
			[concat $libconf(editfields) $libconf(editgroups)] \
			$e(specif) \
		    ]

    auth-get-data ftab $form $e(page-erreur)

    #
    # R�cup�rer les informations pr�-existantes dans la base
    #
    set u(groupes) {}
    set nouveau [expr ! [auth-getuser $login u]]

    if {! [auth-transact "begin" m]} then {
	::webapp::error-exit $e(page-erreur) "Transaction invalide ($m)"
    }

    #
    # Positionner les champs d'utilisateur, par d�faut. On n'inclut
    # pas les groupes, car on le fait apr�s.
    #
    foreach c $libconf(editfields) {
	set var  [lindex $c 2]
	set user [lindex $c 3]
	if {$user} then {
	    set u($var) [lindex $ftab($var) 0]
	}
    }

    #
    # Gestion des groupes :
    #	- liste e(groupes) vide
    #		autoriser tous les groupes sp�cifi�s dans le formulaire
    #		et les positionner dans la base
    #	- liste e(groupes) = un seul �l�ment
    #		ne pas tenir compte du formulaire, et ajouter le groupe
    #		en question dans la base pour l'utilisateur
    #	- liste e(groupes) = plus d'un �l�ment
    #		prendre les groupes du formulaire, et positionner dans
    #		la base tous les groupes de e(groupes)
    #
    auth-lsgroup tabgrp
    switch [llength $e(groupes)] {
	0 {
	    #
	    # Prendre tous les groupes cit�s dans le formulaire et
	    # les positionner � la place des anciens
	    #
	    foreach g $ftab(groupes) {
		if {! [info exists tabgrp($g)]} then {
		    ::webapp::error-exit $e(page-erreur) "Groupe Web invalide ($g)"
		}
	    }
	    set u(groupes) $ftab(groupes)
	}
	1 {
	    #
	    # Ne pas autoriser la saisie des groupes : positionner le
	    # groupe cit� dans e(groupes) seulement s'il ne l'�tait pas
	    # d�j�
	    #
	    set trouve 0
	    if 
	    foreach g $u(groupes) {
		if {[string equal $g $e(groupes)]} then {
		    set trouve 1
		    break
		}
	    }
	    if {! $trouve} then {
		lappend u(groupes) $e(groupes)
	    }
	}
	default {
	    #
	    # Autoriser la saisie des groupes autoris�s :
	    # - retirer de u(groupes) tous les groupes de l'ensemble e(groupes)
	    # - ajouter les groupes s�lectionn�s dans le formulaire (en
	    #	v�rifiant qu'ils appartiennent � e(groupes)
	    #
	    foreach g $e(groupes) {
		set ag($g) 1
	    }

	    # ng = liste des groupes de u, amput�s des groupes de e(groupes)
	    set ng {}
	    foreach g $u(groupes) {
		if {! [info exists ag($g)]} then {
		    lappend ng $g
		}
	    }
	    set u(groupes) $ng

	    # ajouter les groupes du formulaire, sous r�serve qu'ils
	    # figurent dans ag()
	    foreach g $ftab(groupes) {
		if {! [info exists tabgrp($g)]} then {
		    ::webapp::error-exit $e(page-erreur) "Groupe Web invalide ($g)"
		}
		if {[info exists ag($g)]} then {
		    lappend u(groupes) $g
		}
	    }
	}
    }

    #
    # Effectuer le stockage de l'utilisateur dans l'authentification
    #
    set msg [auth-setuser u "pas de transaction"]
    if {! [string equal $msg ""]} then {
	auth-transact "abort" m
	::webapp::error-exit $e(page-erreur) \
		"Impossible d'ajouter '$login' dans auth ($msg)"
    }


    #
    # Effectuer le stockage des informations sp�cifiques de l'application
    #
    set lval {}
    set i 1
    while {[info exists ftab(uvar$i)]} {
	lappend lval $ftab(uvar$i)
	incr i
    }

    set msg [uplevel 3 [format $e(script-setuser) $login $lval]]
    if {! [string equal $msg ""]} then {
	auth-transact "abort" m
    	::webapp::error-exit $e(page-erreur) \
		"Impossible d'ajouter '$login' dans l'application ($msg)"
    }

    #
    # C'est fini, on y va !
    #
    if {! [auth-transact "commit" m]} then {
	auth-transact "abort" msg
    	::webapp::error-exit $e(page-erreur) "Erreur lors de l'ajout de '$login' ($m)"
    }

    if {$nouveau} then {
	set ta "d'ajout de compte"
    } else {
	set ta "de modification d'utilisateur"
    }

    set lsubst {}
    lappend lsubst [list %TITREACTION% $ta]
    lappend lsubst [list %COMPLEMENT% ""]
    return $lsubst
}

#
# Affiche les crit�res de s�lection d'utilisateurs
#
# Retour : liste de substitution pour les trous %CRITERES% et %MESSAGE%
#

proc auth-um-afficher-criteres {evar ftabvar msg} {
    upvar $evar e
    upvar $ftabvar ftab
    global libconf

    #
    # Gestion des groupes
    #

    set menugroupes [auth-build-group-menu "menu" 1 $e(groupes) 1 {}]
    if {[llength $menugroupes] == 0} then {
	set menugroupes {hidden}
    }

    #
    # G�n�rer les champs de saisie des informations de auth
    #

    set donnees {}
    foreach c [concat $libconf(editfields) $libconf(editgroups)] {
	set titre [lindex $c 0]
	set spec  [lindex $c 1]
	set var   [lindex $c 2]
	if {[string equal $var "groupes"]} then {
	    set t [::webapp::form-field $menugroupes $var ""]
	} else {
	    set t [::webapp::form-field $spec $var ""]
	}

	if {! [string equal $t ""]} then {
	    set l [list Normal $titre $t]
	    lappend donnees $l
	}
    }
    set criteres [::arrgen::output html $libconf(tabmodif) $donnees]

    set lsubst {}
    lappend lsubst [list %CRITERES% $criteres]
    lappend lsubst [list %MESSAGE% $msg]

    return $lsubst
}

#
# Exploiter les crit�res de recherche, pour renvoyer la liste
# des utilisateurs trouv�s.
#
# Retour : liste de logins des utilisateurs trouv�s
#

proc auth-um-chercher-criteres {evar ftabvar} {
    upvar $evar e
    upvar $ftabvar ftab
    global libconf

    #
    # R�cup�rer les param�tres
    #

    set form [auth-build-form-spec "critere" \
			[concat $libconf(editfields) $libconf(editgroups)] \
			{} \
		    ]
    auth-get-data ftab $form $e(page-erreur)

    foreach f $form {
	set var [lindex $f 0]
	set $var [string trim [lindex $ftab($var) 0]]
    }

    #
    # Si aucune clause n'a �t� sp�cifi�e, retourner un message
    # appropri� (et refuser de sortir la liste de tous les
    # utilisateurs, ce qui peut �tre long).
    # Si on souhaite *vraiment* avoir tous les utilisateurs,
    # il faut explicitement le demander en saisissant par
    # exemple "*" dans un des crit�res.
    #

    set ncriteres 0
    foreach var {login nom prenom mel adr groupes} {
	if {! [string equal [set $var] ""]} then {
	    incr ncriteres
	}
    }

    set touslesgroupes 1
    if {! ([string equal $groupes "_"] || [string equal $groupes ""])} then {
	set touslesgroupes 0
	incr ncriteres
    }

    if {$ncriteres == 0} then {
	::webapp::error-exit $e(page-erreur) "Vous n'avez saisi aucun crit�re"
    }

    #
    # Prise en compte des recherches phon�tiques
    #

    if {[regexp {^[01]$} $phren] && $phren} then {
	set phnom ""
    } else {
	set phnom $nom
	set nom ""
    }

    if {[regexp {^[01]$} $phrep] && $phrep} then {
	set phprenom ""
    } else {
	set phprenom $prenom
	set prenom ""
    }

    #
    # Rechercher suivant les crit�res demand�s
    #
    # Cas sp�cial pour les groupes : on recherche le groupe demand�,
    # ou alors tous les groupes (ceux d�finis, ou tous ceux de la base)
    # si on ne sp�cifie rien.
    #

    foreach var {login nom prenom phnom phprenom mel adr} {
	set tabcrit($var) [set $var]
    }

    if {$touslesgroupes} then {
	if {[llength $e(groupes)] > 0} then {
	    set tabcrit(groupe) $e(groupes)
	}
    } else {
	set lg $e(groupes)
	if {[llength $lg] == 0} then {
	    auth-lsgroup tabgrp
	    set lg [array names tabgrp]
	}
	if {[lsearch -exact $lg $groupes] == -1} then {
	    ::webapp::error-exit $e(page-erreur) "Groupe Web '$groupes' invalide"
	}
	set tabcrit(groupe) $groupes
    }

    return [auth-searchuser tabcrit {+nom +prenom}]
}

#
# Affiche les actions possibles pour un changement de mot de passe
#
# Retour : liste de substitution pour les trous %LOGIN%, %NOM% et %PRENOM%.
#

proc auth-um-afficher-passwd {evar login} {
    upvar $evar e

    if {! [auth-getuser $login u]} then {
	::webapp::error-exit $e(page-erreur) \
	    "L'utilisateur '$login' n'existe pas !"
    }

    set login  [::webapp::html-string $login]
    set nom    [::webapp::html-string $u(nom)]
    set prenom [::webapp::html-string $u(prenom)]

    set lsubst {}
    lappend lsubst [list %LOGIN%  $login]
    lappend lsubst [list %NOM%    $nom]
    lappend lsubst [list %PRENOM% $prenom]

    return $lsubst
}

#
# Enregistre un mot de passe
#
# Retour : liste de substitution pour les trous %TITREACTION% et %COMPLEMENT%
#

proc auth-um-enregistrer-passwd {evar ftabvar login} {
    upvar $evar e
    upvar $ftabvar ftab

    #
    # V�rifier si le script a bien le droit de modifier l'utilisateur
    #
    set msg [uplevel 3 [format $e(script-chkuser) $login]]
    if {! [string equal $msg ""]} then {
    	::webapp::error-exit $e(page-erreur) \
		"Impossible de changer le mot de passe de '$login' ($msg)"
    }

    #
    # R�cup�rer les param�tres du formulaire
    #
    set form {
	{valider 1 1}
	{pw1     0 1}
	{pw2     0 1}
    }

    auth-get-data ftab $form $e(page-erreur)

    set valider  [string trim [lindex $ftab(valider) 0]]
    set hlogin [::webapp::html-string $login]

    switch -- $valider {
	Bloquer {
	    set msg [auth-chpw $login {block} "nomail" {}]
	    set res "de blocage du compte '$hlogin'"
	    set comp ""
	}
	G�n�rer {
	    set mail [list "mail" $e(mailfrom) $e(mailreplyto) \
				$e(mailcc) $e(mailbcc) \
				[encoding convertto iso8859-1 $e(mailsubject)] \
				[encoding convertto iso8859-1 $e(mailbody)]]
	    set msg [auth-chpw $login {generate} $mail newpw]
	    set res "de g�n�ration de mot de passe ($newpw) pour '$hlogin'"
	    set comp "Le mot de passe a �t� envoy� par m�l."
	}
	Changer {
	    set pw1 [lindex $ftab(pw1) 0]
	    set pw2 [lindex $ftab(pw2) 0]
	    set msg [auth-chpw $login [list "change" $pw1 $pw2] "nomail" {}]
	    set res "de changement de mot de passe pour '$hlogin'"
	    set comp ""
	}
	default {
	    ::webapp::error-exit $e(page-erreur) "Formulaire non conforme"
	}
    }

    if {! [string equal $msg ""]} then {
	::webapp::error-exit $e(page-erreur) $msg
    }

    #
    # Affichage du r�sultat
    #

    set lsubst {}
    lappend lsubst [list %TITREACTION% $res]
    lappend lsubst [list %COMPLEMENT% $comp]

    return $lsubst
}

#
# Affiche la page de confirmation de suppression
#
# Retour : liste de substitution pour le trou %UTILISATEUR%
#

proc auth-um-afficher-suppr {evar login} {
    upvar $evar e

    #
    # V�rifications �l�mentaires
    #
    if {! [auth-getuser $login u]} then {
	::webapp::error-exit $e(page-erreur) \
	    "L'utilisateur '$login' n'existe pas !"
    }

    #
    # XXX : pr�senter davantage d'infos
    #

    set lsubst {}
    lappend lsubst [list %UTILISATEUR%  $login]
    lappend lsubst [list %LOGIN%  [::webapp::html-string $login]]
    return $lsubst
}

#
# Supprime l'utilisateur
#
# Retour : liste de substitution pour les trous %TITREACTION% et %COMPLEMENT%
#

proc auth-um-supprime-utilisateur {evar ftabvar login} {
    upvar $evar e
    upvar $ftabvar ftab

    #
    # Messages par d�faut si tout se passe bien.
    #
    set msg "de suppression de '$login' de l'application"
    set comp "Le compte reste toutefois actif dans le sous-syst�me d'authentification"

    #
    # V�rifier si le script a bien le droit de modifier l'utilisateur
    #
    set msg [uplevel 3 [format $e(script-chkuser) $login]]
    if {! [string equal $msg ""]} then {
    	::webapp::error-exit $e(page-erreur) \
		"Impossible de modifier '$login' ($msg)"
    }

    #
    # Supprimer les droits de l'application
    #
    set msg [uplevel 3 [format $e(script-deluser) $login]]
    if {! [string equal $msg ""]} then {
	::webapp::error-exit $e(page-erreur) $msg
    }

    #
    # Suppression du ou des groupes s�lectionn�s
    #
    if {! [auth-getuser $login u]} then {
	set comp "Le compte n'existait pas dans le sous-syst�me d'authentification"
    } else {
	set rmg {}
	set ng {}
	foreach g $u(groupes) {
	    if {[lsearch -exact $e(groupes) $g] == -1} then {
		# groupe ne faisant pas partie des groupes � supprimer
		lappend ng $g
	    } else {
		# groupe � supprimer
		lappend rmg $g
	    }
	}
	if {[llength $ng] != [llength $u(groupes)]} then {
	    set u(groupes) $ng
	    set m [auth-setuser u]
	    if {[string equal $m ""]} then {
		set rmg [join $rmg ", "]
		set comp "Le compte a �t� supprim� des groupes ci-apr�s : $rmg"
	    } else {
		set comp "Erreur lors de la suppression des groupes $rmg ($m)"
	    }
	}
    }

    #
    # Affichage du r�sultat
    #

    set lsubst {}
    lappend lsubst [list %TITREACTION% [::webapp::html-string $msg]]
    lappend lsubst [list %COMPLEMENT% [::webapp::html-string $comp]]
    return $lsubst
}

#
# Construit une liste de sp�cification de formulaire (pour ::webapp::get-data)
#
# Entr�e :
#	- modif : "modif" ou "critere"
#	- spec1 : cf variable libconf(editfields)
#	- spec2 : cf e(specif) dans auth-usermanage
# Sortie :
#	- une liste pr�te � �tre fournie � get-data
#

proc auth-build-form-spec {modif spec1 spec2} {
    set form {}

    foreach c $spec1 {
	set type [lindex [lindex $c 1] 0]
	set var  [lindex $c 2]
	set user [lindex $c 3]
	if {[string equal $modif "modif"]} then {
	    if {$user} then {
		switch -- $type {
		    list	{ lappend form [list $var 0 99999] }
		    default	{ lappend form [list $var 1 1] }
		}
	    }
	} else {
	    switch -- $type {
		list	{ lappend form [list $var 1 1] }
		default	{ lappend form [list $var 1 1] }
	    }
	}
    }

    set nvar 0
    foreach c $spec2 {
	incr nvar
	set type [lindex [lindex $c 1] 0]
	set var "uvar$nvar"
	switch -- $type {
	    list	{ lappend form [list $var 0 99999] }
	    default	{ lappend form [list $var 1 1] }
	}
    }

    return $form
}

#
# Construit un menu (ou une liste) sur les groupes
#
# Entr�e :
#	- type : list ou menu
#	- tous : vrai si l'entr�e "Tous" doit �tre affich�e
#	- grplist : liste de groupes � g�rer
#	- maxgrp : nb max de groupes � afficher
#	- idxtabvar : en retour, tableau des indexes des groupes dans le return
# Retour :
#	- champ pr�t � �tre affich� avec form-field
#

proc auth-build-group-menu {type tous grplist maxgrp gidxvar} {
    upvar $gidxvar gidx

    auth-lsgroup tabgrp

    set menugroupes {}
    set i 0
    switch [llength $grplist] {
	0 {
	    #
	    # Constituer un menu avec tous les groupes disponibles
	    #
	    if {$tous} then {
		lappend menugroupes [list "_" "Tous"]
		incr i
	    }
	    foreach g [lsort [array names tabgrp]] {
		set gidx($g) $i
		lappend menugroupes [list $g $g]
		incr i
	    }
	}
	1 {
	    #
	    # Ne pas autoriser la saisie des groupes
	    #
	}
	default {
	    #
	    # Autoriser la saisie des groupes s�lectionn�s
	    #
	    if {$tous} then {
		lappend menugroupes [list "_" "Tous"]
		incr i
	    }
	    foreach g $grplist {
		if {[info exists tabgrp($g)]} then {
		    set gidx($g) $i
		    lappend menugroupes [list $g $g]
		} else {
		    lappend menugroupes [list "Groupe Web '$g' invalide" $g]
		}
		incr i
	    }
	}
    }

    set ngroupes [llength $menugroupes]
    if {$ngroupes > 0} then {
	if {$maxgrp > 0 && $ngroupes > $maxgrp} then {
	    set ngroupes $maxgrp
	}
	if {[string equal $type "list"]} then {
	    set menugroupes [linsert $menugroupes 0 "list" "multi" $ngroupes]
	} else {
	    set menugroupes [linsert $menugroupes 0 "menu"]
	}
    }

    return $menugroupes
}

##############################################################################
# Gestion HTML des mots de passe
##############################################################################

#
# El�ment central des scripts CGI des applications pour la gestion
# des mots de passe.
#
# Entr�e :
#   - param�tres :
#	- e : environnement d'ex�cution du script, sous la forme d'un
#		tableau index� :
#		page-* : les fonds de page (HTML/Latex) avec les
#			trous, index� par le nom de la page :
#			-choix : page de changement de mot de passe
#			-ok : action effectu�e
#			-erreur : erreur d�tect�e
# Sortie :
#   - valeur de retour : aucune
#   - sortie standard : une page HTML pr�te � �tre envoy�e
#
# Historique :
#   2003/09/27 : pda      : d�but de la conception
#

proc auth-pwdmanage {evar} {
    upvar $evar e

    set login [::webapp::user]
    if {[string equal $login ""]} then {
	::webapp::error-exit $e(page-erreur) "Nom de login inconnu."
    }

    set form {
	{pw1     0 1}
	{pw2     0 1}
    }
    auth-get-data ftab $form $e(page-erreur)

    set pw1 [string trim [lindex $ftab(pw1) 0]]
    set pw2 [string trim [lindex $ftab(pw2) 0]]

    if {[string equal $pw1 ""] && [string equal $pw2 ""]} then {
	set page $e(page-choix)
    } else {
	set msg [auth-chpw $login [list change $pw1 $pw2] "nomail" {}]
	if {! [string equal $msg ""]} then {
	    ::webapp::error-exit $e(page-erreur) $msg
	} else {
	    set page $e(page-ok)
	}
    }

    ::webapp::send "html" [::webapp::file-subst $page {}]
}