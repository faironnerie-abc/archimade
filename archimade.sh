#!/bin/bash

OUTPUT=""
FORCE=""
SUDO=""
SIZE="6G"
FSTYPE="ext4"
FSOPTS="-F"
ARCH="i686"
VERSION="2015.06.01"
MIRROR="http://archlinux.mirrors.ovh.net/archlinux/iso"
NAME="archimade"
VGA="intel"
IMG_USER="faironnier"
IMG_USER_GROUPS="wheel,audio,video,users,storage"

BASE_PACKAGES="base grub os-prober gparted openssh ntfs-3g dosfstools"

DE="xfce4"
DE_PACKAGES=""

DM="lightdm"
DM_PACKAGES=""
DM_SERVICE=""

AUTOLOGIN=""

function usage() {
	cat <<EOF >&2
Usage $0: [OPTIONS] ([-o OUTPUT] | OUTPUT)

	OUTPUT: fichier image
	-s    : taille de l\'image (défaut : 6G)
	-f    : force l\'écrasement d\'une image existante
	-A    : architecture (i686|x86-64)
	-t    : type de la partition (défaut : ext4)
	-O    : option du formatage (défaut : \"-F\")
	-n    : nom de la machine
	-x    : désactive l\'environnement bureautique
	-d    : spécifie l\'environnement bureautique (défaut : xfce4)
	-c    : spécifie le gestionnaire de connexion (défaut : lightdm)
	-S    : active sudo pour l\'utilisateur
	-a    : active l\'autologin
EOF
}

while getopts fo:s:t:O:d:c:xSaA opt
do
	case $opt in
	f)	FORCE=1          ;;
	o)	OUTPUT="$OPTARG" ;;
	s)	SIZE="$OPTARG"   ;;
	t)	FSTYPE="$OPTARG" ;;
	O)	FSOPTS="$OPTARG" ;;
	n)	NAME="$OPTARG"   ;;
	d)  DE="$OPTARG"     ;;
	c)  DM="$OPTARG"     ;;
	x)  DE=""            ;;
	S)  SUDO="oui"       ;;
	a)  AUTOLOGIN="oui"  ;;
	A)  ARCH="$OPTARG"   ;;
	?)  usage
		exit 1 ;;
	:)	printf "Option -$OPTARG requires an argument.\n" >&2
		usage
		exit 1 ;;
	esac
done

if [ -z "$DE" ]
then
	DE_PACKAGES=""
	DM_PACKAGES=""
	X_PACKAGES=""
else
	case $DE in
	xfce4)
		DE_PACKAGES="xfce4"
		;;
	gnome)
		DE_PACKAGES="gnome"
		;;
	enlightenment)
		DE_PACKAGES="enlightenment"
		;;
	?)  echo "Environnement de bureau non géré $DE." >&2
		exit 1
		;;
	esac
	
	case $DM in
	lightdm)
		DM_PACKAGES="lightdm lightdm-gtk-greeter"
		DM_SERVICE="lightdm.service"
		;;
	gdm)
		DM_PACKAGES="gdm"
		DM_SERVICE="gdm"
		;;
	?)  echo "Gestionnaire de connexion non géré $DM." >&2
		exit 1
		;;
	esac
	
	X_PACKAGES="xorg-server xorg-xinit xorg-server-utils xf86-video-$VGA"
fi

USER_PACKAGES="blender inkscape gimp openscad nmap gedit xz chromium"
PACKAGES="$BASE_PACKAGES $X_PACKAGES $DE_PACKAGES $DM_PACKAGES $USER_PACKAGES"

if [ -n "$SUDO" ]
then
	PACKAGES="$PACKAGES sudo"
fi

shift $(($OPTIND - 1))

if [ `echo $SIZE | grep -e '^[[:digit:]]\+[KMG]$' | wc -l` -eq 0 ]
then
	printf "La taille '%s' est invalide. Elle doit être au format DIGIT+(K,M,G). Exemple : 4G.\n" $SIZE >&2
	exit 1
fi

if [ -z "$OUTPUT" ]
then
	if [ -z "$1" ]
	then
		echo "Vous devez spécifier un nom de fichier de sortie." >&2
		usage
		exit 1
	fi
	
	OUTPUT="$1"
fi

if [ -e "$OUTPUT" ]
then
	echo "$OUTPUT existe déjà." >&2
	
	if [ -z "$FORCE" ]
	then
		echo "Utilisez l'option -f pour l'écraser." >&2
		exit 1
	fi
fi

if [ -n "$AUTOLOGIN" ]
then
	IMG_USER_GROUPS="$IMG_USER_GROUPS,autologin"
fi

BOOTSTRAP="archlinux-bootstrap-${VERSION}-${ARCH}.tar.gz"
MOUNT_POINT="$OUTPUT-mount-point"

#
# Vérification de la configuration
#

cat <<EOF
Image             : $OUTPUT
Type de partition : $FSTYPE
Taille            : $SIZE
Architecture      : $ARCH
Version           : $VERSION
Serveur           : $MIRROR
Bootstrap         : $BOOTSTRAP
Point de montage  : $MOUNT_POINT
Bureau            : $DE
Connexions        : $DM
Carte vidéo       : $VGA
Packages          : $PACKAGES
Nom de la machine : $NAME
Utilisateur       : $IMG_USER
Groupes           : $IMG_USER_GROUPS
Sudo              : $SUDO
Autologin         : $AUTOLOGIN
EOF

echo -n "On y va ? [On] "
read reponse

if [ "$reponse" = "n" -o "$reponse" = "N" ]
then
	echo "Snif, ok ok."
	exit 1
fi

#
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# On commence le boulot maintenant !
# <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
#

function delete_image() {
	echo -n "Supprimer l'image ? [Yn] "
	read reponse
	
	if [ "$reponse" = "n" -o "$reponse" = "N" ]
	then
		echo "On garde l'image $OUTPUT."
	else
		rm -f $OUTPUT
	fi
}

function terminate() {
	sudo umount $MOUNT_POINT
	rmdir $MOUNT_POINT
}

function on_error() {
	echo "Erreur dans la phase \"$1\""
	
	case $1 in
	get_bootstrap)   ;;
	allocate)        ;;
	format)          delete_image ;;
	mount)           delete_image ;;
	bootstrap)       terminate && delete_image ;;
	pre_config)      terminate && delete_image ;;
	packages)        terminate && delete_image ;;
	post_config)     terminate && delete_image ;;
	user)            terminate && delete_image ;;
	custom_commands) terminate && delete_image ;;
	esac
	
	exit 1
}

function archroot() {
	sudo arch-chroot $MOUNT_POINT $*
}

#
# Récupération du bootstrap Archlinux
#

function phase_get_bootstrap() {
	echo "[build] get bootstrap"
	if [ -e "$BOOTSTRAP" ]
	then
		echo "[build] find existing bootstrap"
	else
		echo -n "[build] downloading $MIRROR/$VERSION/$BOOTSTRAP ..."
		curl --silent --remote-name "$MIRROR/$VERSION/$BOOTSTRAP" && echo " done"
	fi
}

phase_get_bootstrap || on_error "get_bootstrap"

#
# Allocation de l'espace.
#

function phase_allocate() {
	echo "[build] allocate file space"
	fallocate -l $SIZE "$OUTPUT"
}

phase_allocate || on_error "allocate"

#
# Formatage.
#

function phase_format() {
	echo "[build] format partition"
	mkfs.$FSTYPE $FSOPTS $OUTPUT
}

phase_format || on_error "format"

#
# Montage
#

function phase_mount() {
	echo "[build] mount"
	if [ -e "$MOUNT_POINT" ]
	then
		if [ -z "$FORCE" ]
		then
			echo "Le point de montage temporaire existe et l'option -f n'est pas activée."
			exit 1
		fi
	else
		mkdir $MOUNT_POINT
	fi

	sudo mount $OUTPUT $MOUNT_POINT 
}

phase_mount || on_error "mount"

#
# Bootstrap de Archlinux sur l'image.
#

function phase_bootstrap() {
	echo "[build] bootstrap"
	tar zxf $BOOTSTRAP                && \
	sudo mv root.$ARCH/* $MOUNT_POINT && \
	rmdir root.$ARCH
}

phase_bootstrap || on_error "bootstrap"

#
# Copie des fichiers de configuration.
#

function phase_pre_config() {
	echo "[build] configure system"
	if [ -z "$MOUNT_POINT" ]
	then
		echo "Attention !!"
		exit 1
	fi
	
	if [ -d "$OUTPUT-config" ]
	then
		CONFIG="$OUTPUT-config"
	else
		CONFIG="config/"
	fi
	
	sed -e "s/Architecture = \(.*\)/Architecture = $ARCH/" $CONFIG/pacman.conf | \
		sudo tee $MOUNT_POINT/etc/pacman.conf > /dev/null                   && \
	sudo cp $CONFIG/pacman-mirrorlist  $MOUNT_POINT/etc/pacman.d/mirrorlist && \
	sudo cp $CONFIG/vconsole.conf      $MOUNT_POINT/etc/                    && \
	sudo cp $CONFIG/locale.gen         $MOUNT_POINT/etc/                    && \
	sudo cp $CONFIG/locale.conf        $MOUNT_POINT/etc/                    || return 1
	
	sudo echo $NAME > $MOUNT_POINT/etc/hostname
}

phase_pre_config || on_error "pre_config"

#
# Installation des packages.
#

function phase_packages() {
	echo "[build] init pacman keys"
	archroot pacman-key --init                   && \
	archroot pacman-key --populate archlinux     && \
	echo "[build] install packages (this can be really long)" && \
	archroot pacman -Syuq --noconfirm $PACKAGES
}

phase_packages || on_error "packages"

#
# Copie des fichiers de configuration.
#

function phase_post_config() {
	echo "[build] configure system"
	if [ -z "$MOUNT_POINT" ]
	then
		echo "Attention !!"
		exit 1
	fi
	
	if [ -d "$OUTPUT-config" ]
	then
		CONFIG="$OUTPUT-config"
	else
		CONFIG="config/"
	fi
	
	if [ -n "$SUDO" ]
	then
		sudo cp $CONFIG/sudoers $MOUNT_POINT/etc/  && \
	fi || return 1
	
	if [ -n "$DM" ]
	then
		archroot systemctl enable $DM.service
	fi || return 1
	
	if [ -n "$AUTOLOGIN" ]
	then
		archroot groupadd autologin && \
		case $DM in
		lightdm)
			sudo cp $CONFIG/lightdm-autologin.conf $MOUNT_POINT/etc/lightdm/
			;;
		esac
	fi || return 1
}

phase_post_config || on_error "post_config"

function copy_files() {
	if [ -d "$OUTPUT-files" ]
	then
		sudo cp -r $OUTPUT-files/*  $MOUNT_POINT/home/$IMG_USER/ && \
		sudo cp -r $OUTPUT-files/.* $MOUNT_POINT/home/$IMG_USER/
	fi || return 1
}

function phase_user() {
	echo "[build] configure user"
	archroot locale-gen                                            && \
	archroot useradd -G $IMG_USER_GROUPS -m -s /bin/bash $IMG_USER && \
	copy_files                                                     && \
	archroot chown -R $IMG_USER:$IMG_USER /home/$IMG_USER
}

phase_user || on_error "user"

#
# Ouverture shell
#

function phase_custom_commands() {
	echo "[build] custom commands"
	echo -n "Voulez-vous exécuter des commandes sur le système ? Définir le mot de passe root par exemple [Ny] "
	read reponse
	
	if [ "$reponse" = "Y" -o "$reponse" = "y" ]
	then
		archroot bash 
	fi || return 1
}

phase_custom_commands || on_error "custom_commands"

#
# Finalisation.
#

terminate

echo "[build] Construction de l'image terminée !"

