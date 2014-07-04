## ######### PROJECT NAME : ##########
##
## Objet_Conf.pm
##
## ######### PROJECT DESCRIPTION : ###
##
## Objet Configuration
##
## ###################################
##

# Declaration du package Conf

package Objet_Conf;

# Utilisation de l'objet LOGGER

use strict;
use warnings;
use Objet_Logger;
use Tie::File;
use Data::Dumper;

# Valeurs par defaut
my $DEFAULT_SEPARATOR_CHAR = '=';
my $DEFAULT_COMMENT_CHAR   = '#';
my $DEFAULT_SECTION_NAME   = "DEFAUTINTELLIQUEUNIQUE";
my $DEFAULT_LOG_FILE       = "/var/log/storiq/Objet_Conf.log";

# Fonction de création de l'objet de conf
# Cette fonction prend en parametre :
# 1. Le path vers le fichier de conf
# 2. l'instance d'un objet de log (objet_logger) (optionnel)
# 3. Le caractere separateur (optionnel)
# 4. Le caractere de commentaire (optionnel)
# En cas de succes, cette fonction retourne l'instance de l'objet cree. Si
# l'instanciation echoue, la fonction retourne 0.
sub new {
    my $conf = {};

    # Remplissage des variables de l'objet
    $conf->{OBJNAME}         = shift;
    $conf->{FILE_PATH}       = shift;
    $conf->{LOGGER}          = shift;
    $conf->{SEPARATEUR}      = shift;
    $conf->{COMMENTAIRE}     = shift;
    $conf->{DEFAULT_SECTION} = $DEFAULT_SECTION_NAME;

    # Initialisation de la hash de conf avec la section par defaut
    $conf->{CONF} = {};
    $conf->{CONF}->{ $conf->{DEFAULT_SECTION} } = {};

    # Verification du chemin du fichier
    if ( !-e $conf->{FILE_PATH} ) {
        open my $file, '>', $conf->{FILE_PATH}
          or return ( 3, "can't open ' $conf->{FILE_PATH}': $!");
        close $file;
    }

    # Verification si le fichier est lisible
    return ( 1, "$conf->{FILE_PATH} is not readable." )
      if ( !-r $conf->{FILE_PATH} );

    # Verification de la presence de l'objet logger
    if ( !defined( $conf->{LOGGER} ) ) {
        $conf->{LOGGER} = new Objet_Logger($DEFAULT_LOG_FILE);
        $conf->{LOGGER}
          ->debug("$conf->{OBJNAME} : new : creation de l'Objet_Logger");
    } elsif ( ref( $conf->{LOGGER} ) ne "Objet_Logger" ) {
        $conf->{LOGGER} = new Objet_Logger($DEFAULT_LOG_FILE);
        $conf->{LOGGER}->warn(
            "$conf->{OBJNAME} : new : Wrong Objet_Logger parameter, renew..");
    }

    # Test du caractere separateur
    if ( !defined( $conf->{SEPARATEUR} ) ) {
        $conf->{SEPARATEUR} = $DEFAULT_SEPARATOR_CHAR;
        $conf->{LOGGER}->debug(
"$conf->{OBJNAME} : new : Utilisation du caractere de separation par defaut"
        );
    }

    # Test du caractere commentaire
    if ( !defined( $conf->{COMMENTAIRE} ) ) {
        $conf->{COMMENTAIRE} = $DEFAULT_COMMENT_CHAR;
        $conf->{LOGGER}->debug(
"$conf->{OBJNAME} : new : utilisation du caractere de commentaire par defaut"
        );
    }

    # Il faut que le separateur et le commentaire soit different
    if ( $conf->{COMMENTAIRE} eq $conf->{SEPARATEUR} ) {
        $conf->{LOGGER}->error(
"$conf->{OBJNAME} : new : Separator char and Comment char are identical."
        );
        return ( 1, "Separator char and Comment char are identical." );
    }

    # creation de l'objet
    bless($conf);

    # J'appelle la fonction de chargement du fichier
    _load($conf);

    return ( 0, $conf );
}

# Fonction de rechargement du fichier en memoire
sub reload {
    my $self = shift;

    $self->{LOGGER}
      ->info("$self->{OBJNAME} : reload : Rebuilding configuration hash.");
    $self->{CONF} = {};

    return ( _load($self) );
}

# Fonction de recuperation d'une valeur en fonction de la clef et de la section
# Cette fonction prend en parametre :
# 1. La clef
# 2. La section. Ce paramètre est optionnel; s'il est absent la clef est cherchee
# dans hors section.
sub get_value {
    my ( $self, $cle, $section ) = @_;

    # Si $section est defini, on positionne la variable de l'objet
    unless ($section) {
        $section = $self->{DEFAULT_SECTION};
    }

    # Je teste la cle recue
    unless ( defined($cle) ) {
        $self->{LOGGER}
          ->error("$self->{OBJNAME} : get_value : Key parameter is missing");
        return ( 1, "Key parameter is missing" );
    }

    # Je verifie la presence de la section dans l'objet
    unless ( exists $self->{CONF}->{$section} ) {
        $self->{LOGGER}->error(
            "$self->{OBJNAME} : get_value : Section $section is not found");
        return ( 1, "Section $section is not found" );
    }

    # Je verifie la presence de la cle dans l'objet
    unless ( exists $self->{CONF}->{$section}->{$cle} ) {
        $self->{LOGGER}->error(
"$self->{OBJNAME} : get_value : Key $cle is missing in section $section"
        );
        return ( 1, "Key $cle is missing in section $section" );
    }

    return ( 0, $self->{CONF}->{$section}->{$cle} );
}

# Fonction de modification d'un couple clef/valeur
# en fonction de la section
# Cette fonction prend en parametre :
# 1. La clef
# 2. La valeur
# 3. La section. Ce paramètre est optionnel; s'il est absent la clef est cherchee
# hors section.
sub set_value {
    my ( $self, $cle, $valeur, $section ) = @_;

    # Je teste la cle recue
    unless ( defined($cle) ) {
        $self->{LOGGER}
          ->error("$self->{OBJNAME} : set_value : Key parameter is missing");
        return ( 1, "Key parameter is missing" );
    }

    # Je teste la valeur recue
    unless ( defined($valeur) ) {
        $self->{LOGGER}
          ->error("$self->{OBJNAME} : set_value : Value parameter is missing");
        return ( 1, "Value parameter is missing" );
    }

    # Si je n'ai pas recu de section je l'initialise a Defaut
    unless ($section) {
        $section = $self->{DEFAULT_SECTION};
    }

    # Je verifie la presence de la section dans l'objet
    unless ( exists $self->{CONF}->{$section} ) {
        $self->{LOGGER}->warn(
"$self->{OBJNAME} : set_value : Section $section is missing, we create it"
        );
        $self->{CONF}->{$section} = {};
    }

    # Si la cle demande n'existe pas je sort
    unless ( exists $self->{CONF}->{$section}->{$cle} ) {
        $self->{LOGGER}->warn(
"$self->{OBJNAME} : set_value : Key $cle is missing in Section $section"
        );
    }

    # Positionement de la valeur a la cle de la section demande
    $self->{CONF}->{$section}->{$cle} = $valeur;

    return (0);
}

# Fonction de sauvegarde de la conf
# Cette fonction prend en parametre :
# 1. Le nom du fichier a enregistrer. Ce parametre est optionnel.
# S'il est absent le fichier donne lors du new est utilise
sub save {

    #
    # Bon courage pour debugger cette fonction :P
    #

    my ( $self, $fullname ) = @_;

    # Si le fichier n'est pas specifie on utilise celui specifie dans l'init
    unless ($fullname) {
        $fullname = $self->{FILE_PATH};
    }

    # Copie de la hash conf dans une hash temporaire
    my $conftemp = {};
    foreach my $fst_key ( keys %{ $self->{CONF} } ) {
        foreach my $snd_key ( keys %{ $self->{CONF}->{$fst_key} } ) {
            $conftemp->{$fst_key}->{$snd_key} =
              $self->{CONF}->{$fst_key}->{$snd_key};
        }
    }

    # Verification et ouverture du fichier
    my @file;

    unless ( tie( @file, 'Tie::File', $fullname ) ) {
        $self->{LOGGER}
          ->error("$self->{OBJNAME} : save : Unable to open file $fullname");
        return ( 1, "Unable to open file : $fullname" );
    }

    # Initialisation de la section a defaut
    my $section = $self->{DEFAULT_SECTION};
    my $numline = 0;

    while ( $numline < scalar(@file) && defined($section) ) {
        if ( exists( $conftemp->{$section} ) ) {
            ( $numline, $section ) =
              _save_section_in_file( $self, $conftemp, \@file, $numline,
                $section );
        } else {
            ( $numline, $section ) =
              _delete_section_in_file( $self, $conftemp, \@file, $numline,
                $section );
        }
    }

    # Il faut aussi écrire les nouvelles sections..
    foreach $section ( keys( %{$conftemp} ) ) {
        splice( @file, $numline, 0, "", "[" . $section . "]" );
        $numline += 2;

        my $cle;
        foreach $cle ( keys %{ $conftemp->{$section} } ) {
            my $line_to_add =
              "$cle $self->{SEPARATEUR} $conftemp->{$section}->{$cle}";
            splice( @file, $numline, 0, $line_to_add );
            $numline++;
        }
        delete( $conftemp->{$section} );
    }

    # Close le fichier
    untie(@file);

    return ( 0, 0 );
}

sub _delete_section_in_file {
    my ( $self, $conftemp, $pfile, $numline, $section ) = @_;

    my $new_section = undef;
    my $line;

    while ( $numline < scalar(@$pfile) ) {
        splice( @$pfile, $numline, 1 );

        last if ( $numline == scalar(@$pfile) );
        last if ( $new_section = _matchsection( $self, $$pfile[$numline] ) );
    }
    return ( $numline, $new_section );
}

sub _save_section_in_file {
    my ( $self, $conftemp, $pfile, $numline, $section ) = @_;

    my $new_section = undef;
    my $line;

    while ( $numline < scalar(@$pfile) ) {
        $line = $$pfile[$numline];

        # J'ignore les lignes de commentaire et vides
        if ( $line =~ m/^\s*$self->{COMMENTAIRE}/ || $line =~ m/^\s*$/ ) {
            $numline++;
            next;
        }

        if ( ( $new_section = _matchsection( $self, $$pfile[$numline] ) ) ) {
            last if ( $new_section ne $section );
        }

        # Recuperation du couple cle/valeur separe par le separateur
        if ( my ( $k, $v ) = _matchline( $self, $line ) ) {

            # Si la ligne presente dans le fichier ne l'est pas dans la hash
            # Je la supprime.
            if ( !exists $conftemp->{$section}->{$k} ) {
                splice( @$pfile, $numline, 1 );
                delete( $conftemp->{$section}->{$k} );
                next;
            }

       # Si la valeur dans la hash temporaire est differente de celle du fichier
       # je modifie le fichier
            elsif ( $conftemp->{$section}->{$k} ne $v ) {
                _changeline( $self, \$$pfile[$numline],
                    $conftemp->{$section}->{$k} );
            }

            # Je supprime la cle de la section de la hash temporaire
            delete( $conftemp->{$section}->{$k} );
        }
        $numline++;
    }

# Je suis sur une nouvelle section ou a la fin d'un fichier.
# S'il reste des entrees dans la section precedente je les ecrit dans le fichier
    if ( keys( %{ $conftemp->{$section} } ) ) {
        my $tmp_numline = $numline;

        # Je cherche la derniere ligne non vide
        while ( $tmp_numline >= 0 && $$pfile[ $tmp_numline - 1 ] =~ m/^\s*$/ ) {
            $tmp_numline--;
        }

        my $cle;
        foreach $cle ( keys %{ $conftemp->{$section} } ) {
            my $line_to_add =
              "$cle $self->{SEPARATEUR} $conftemp->{$section}->{$cle}";
            splice( @$pfile, $tmp_numline, 0, $line_to_add );
            $tmp_numline++;
            $numline++;
        }
    }

    delete( $conftemp->{$section} );

    return ( $numline, $new_section );
}

# Fonction renvoyant un tableau de toutes les clefs d'une section.
# Cette fonction prend en parametre :
# 1. La section. Ce parametre est optionnel.
sub get_key {
    my ( $self, $section ) = @_;

    # Si je n'ai pas recu de section je l'initialise a Defaut
    unless ($section) {
        $section = $self->{DEFAULT_SECTION};
    }

    # Je verifie la presence de la section dans l'objet
    unless ( exists $self->{CONF}->{$section} ) {
        $self->{LOGGER}->error(
            "$self->{OBJNAME} : get_value : Section $section is not found");
        return ( 1, "Section $section is not found" );
    }

    my @return_tab = keys( %{ $self->{CONF}->{$section} } );
    return ( 0, \@return_tab );
}

# Fonction de recuperation de la hash. Cette fonction retourne une copie de la hash
# qui contient toute la conf
sub get_all {
    my $self = shift;

    #copie de la hash dans la hash que lon renvoie
    my %ret = %{ $self->{CONF} };
    return ( 0, %ret );
}

# Fonction qui renvoie un tableau contenant les noms de toutes les sections
sub get_section {
    my $self = shift;
    return ( 0, keys( %{ $self->{CONF} } ) );
}

# Fonction de suppression d'une clef en fonction de la section.
# Cette fonction prend en parametre :
# 1. La clef a supprimer
# 2. La section. Ce parametre est optionnel.
sub delete_key {
    my ( $self, $cle, $section ) = @_;

    # Si $section est defini, on positionne la variable de l'objet
    unless ($section) {
        $section = $self->{DEFAULT_SECTION};
    }

    # Je teste la cle recue
    unless ( defined($cle) ) {
        $self->{LOGGER}
          ->error("$self->{OBJNAME} : delete_key : Key parameter is missing");
        return ( 1, "Key parameter is missing" );
    }

    # Si la hash existe je cherche et je supprime la cle corespondante
    if ( exists $self->{CONF}->{$section}->{$cle} ) {
        $self->{LOGGER}->info(
"$self->{OBJNAME} : delete_key : Deletion of key $cle in section $section"
        );
        delete( $self->{CONF}->{$section}->{$cle} );
    } else {
        $self->{LOGGER}
          ->warn("$self->{OBJNAME} : delete_key : Key $cle not found");
        return ( 1, "Key $cle not found" );
    }

    return (0);
}

# Fonction de suppression d'une section entiere.
# Cette fonction prend en parametre :
# 1. La section a supprimer.
# On ne peut pas supprimer la fonction par defaut..
sub delete_section {
    my ( $self, $section ) = @_;

    # Si $section est defini, on positionne la variable de l'objet
    unless ( defined($section) ) {
        $self->{LOGGER}->error(
            "$self->{OBJNAME} : delete_section : Section parameter is missing"
        );
        return ( 1, "Section parameter is missing" );
    }

    if ( $section eq $self->{DEFAULT_SECTION} ) {
        $self->{LOGGER}->error(
"$self->{OBJNAME} : delete_section : Trying to delete default section : you are crazy..."
        );
        return ( 1, "Unable to delete this section !" );
    }

    # Si la hash existe je cherche et je supprime la section corespondante
    if ( exists $self->{CONF}->{$section} ) {
        $self->{LOGGER}->info(
            "$self->{OBJNAME} : delete_section : Deletion of section $section"
        );
        delete( $self->{CONF}->{$section} );
    } else {
        $self->{LOGGER}->warn(
            "$self->{OBJNAME} : delete_section : Section $section not found");
        return ( 1, "Section $section not found" );
    }

    return (0);
}

############################### PRIVATES FUNCTIONS ###################################

# Fonction de chargement du fichier en memoire
sub _load {
    my $self = shift;
    my $section;
    my $find;

    # Verification et ouverture du fichier
    my @file;
    $self->{LOGGER}->debug(
        "$self->{OBJNAME} : _load : Ouverture du fichier $self->{FILE_PATH}");

    if ( !-r $self->{FILE_PATH} ) {
        $self->{LOGGER}->error(
            "$self->{OBJNAME} : _load : File $self->{FILE_PATH} is unreadable."
        );
        return ( 1, "$self->{FILE_PATH} is not readable." );
    }

    use Fcntl 'O_RDONLY';
    unless ( tie( @file, 'Tie::File', $self->{FILE_PATH}, mode => O_RDONLY ) ) {
        $self->{LOGGER}->error(
            "$self->{OBJNAME} : _load : Unable to open $self->{FILE_PATH}");
        return ( 1, "Unable to open $self->{FILE_PATH}" );
    }

    # Initialisation de la section par Defaut
    $section = $self->{DEFAULT_SECTION};

    # Remplissage et decoupage par section de l'objet avec le fichier
    $self->{LOGGER}
      ->debug("$self->{OBJNAME} : _load : Parcours et decoupage du fichier");

    my $lineclean;
    foreach (@file) {

# Decoupage des lignes par rapport au commentateur pour eliminer les commentaires
        ($lineclean) = split $self->{COMMENTAIRE}, $_;

# Je passe a la ligne suivante si la courante est vide ou ne contient que des espaces
        next if ( !$lineclean or $lineclean =~ /^\s*$/ );

        # Le nom de la section commence par [ et fini par ]
        if ( my $sec = _matchsection( $self, $lineclean ) ) {

     # On creer la section dans la hash seulement si elle n'existe pas deja
     # Si la section dans la hash existe deja, on la recree en tapant un warning
            if ( $self->{CONF}->{$sec} ) {
                $self->{LOGGER}->warn(
"$self->{OBJNAME} : _load : Section $sec already exists, flushing the previous section."
                );
            }
            $self->{CONF}->{$sec} = {};

            # Positionnement de la Section courante sur la nouvelle section
            $section = $sec;
            next;
        }

        # Recuperation du couple cle/valeur separe par le separateur
        if ( my ( $k, $v ) = _matchline( $self, $lineclean ) ) {

            # Erreur si la cle existe deja dans la section
            if ( $self->{CONF}->{$section}{$k} ) {
                $self->{LOGGER}->warn(
"$self->{OBJNAME} : _load : Key $k already exists in section $section, flushing the previous key"
                );
            }

            # Positionnement dans la hash section du couple cle/valeur
            $self->{CONF}->{$section}{$k} = $v;
            next;
        }

        # Nous signalons par un Warning que la ligne numero n'est pas correct
        $self->{LOGGER}
          ->warn("$self->{OBJNAME} : _load : Line $. non compliant");
    }

    # Close le fichier
    untie(@file);

    return (0);
}

sub _matchsection {

    # _matchsection($self, $line);

    my ( $self, $line ) = @_;

    if ( $line =~ m/^\s*\[\s*(((\w|[:."'-])*\s*)*(\w|[:."'-]))\s*\]\s*$/ ) {
        return $1;
    }

    return;
}

sub _changeline {

    # _changeline($self, $line, $valeur);
    # Modifie directement dans $line la valeur par $valeur

    my ( $self, $line, $valeur ) = @_;

# Si il y a des commentaires a la fin de la ligne ils sont stocke dans la 1er case du tableau
    ( ${$line}, my @endline ) = split $self->{COMMENTAIRE}, ${$line};

    # Les commentaires sont initialise a null
    my $comm = "";

    # Si il y a des commentaires je les inclus dans $comm
    if ( scalar(@endline) ) {

        # $l contien la concatenation de tout les commentaire
        my $l;
        foreach (@endline) {
            $l .= $self->{COMMENTAIRE};
            $l .= $_;
        }
        $comm = " " . $l;
    }

    ${$line} =~
s/(^\s*(((\w|[\/:."'&+~-])*\s*)*(\w|[\/;:."'&+~-]))\s*$self->{SEPARATEUR}\s*)((\s*\S)*)\s*$/$1$valeur$comm/;
}

sub _matchline {

    # _matchline($self, $line);
    # retourne la cle et la valeur de la ligne sinon renvoie rien

    my ( $self, $line ) = @_;

    if ( $line =~
m/^\s*(((\w|[\/:."'&+~-])*\s*)*(\w|[\/;:."'&+~-]))\s*$self->{SEPARATEUR}\s*((\s*\S)*)\s*$/
      )
    {
        return ( $1, $5 );
    }

    return;
}

1;
