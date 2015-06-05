Archimade : création d'image Archlinux sur mesure
=================================================

# Usage :

Une fois l'image créer, sur la machine cible démarrer Archlinux en live :

1. Partitionner le disque
2. Copier le contenu de l'image sur la partition (qui doit être de la même dimension que l'image)
   `dd if=mon-image.raw of=/dev/ma-partition bs=4M
3. Monter la partition sur /mnt, ainsi qu'éventuellement la partition home (dans /mnt/home) et le swap
4. Générer le fstab via `genfstab -U /mnt > /mnt/etc/fstab`. Ce qui permettra de monter les disques correctement avec les UUID.
5. Chrooter le nouveau système via `arch-chroot /mnt bash`
	1. Générer le disque initial via `mkinitcpio -p linux`
	2. Générer la configuration de Grub via `grub-mkconfig -o /boot/grub/grub.cfg`
	3. Installer Grub via `grub-install --recheck /dev/sdX`

