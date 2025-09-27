#!/bin/bash

# Script d'installation automatique d'Ubuntu 24.04 Server
# Version simplifiée avec un minimum de variables

# Couleurs pour l'affichage
ROUGE='\033[0;31m'
VERT='\033[0;32m'
BLEU='\033[0;34m'
NC='\033[0m' # Pas de couleur

# Fonctions de log
log_info() {
    echo -e "${BLEU}[INFO]${NC} $1"
}

log_succes() {
    echo -e "${VERT}[SUCCÈS]${NC} $1"
}

log_erreur() {
    echo -e "${ROUGE}[ERREUR]${NC} $1"
}

# Vérification des privilèges root
if [[ $EUID -ne 0 ]]; then
    log_erreur "Ce script doit être exécuté en tant que root ou avec sudo"
    exit 1
fi

# Répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Paramètres de la VM (fixes)
read NOM_VM
#NOM_VM="ubuntu-server"
RAM_VM="4048"
VCPUS_VM="2"
TAILLE_DISQUE="40G"
CHEMIN_DISQUE="/var/lib/libvirt/images"
URL_ISO="https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-live-server-amd64.iso"
CHEMIN_ISO="${SCRIPT_DIR}/ubuntu-24.04.3-live-server-amd64.iso"
BRIDGE="br0"  # Changé de "virbr0" vers "br0"

# Vérification des prérequis
log_info "Vérification des prérequis..."
PAQUETS_REQUIS=("qemu-kvm" "libvirt-daemon-system" "libvirt-clients" "bridge-utils" "virtinst" "genisoimage")
PAQUETS_MANQUANTS=()

for paquet in "${PAQUETS_REQUIS[@]}"; do
    if ! dpkg -l | grep -q "^ii.*$paquet"; then
        PAQUETS_MANQUANTS+=("$paquet")
    fi
done

if [[ ${#PAQUETS_MANQUANTS[@]} -gt 0 ]]; then
    log_info "Installation des paquets manquants: ${PAQUETS_MANQUANTS[*]}"
    apt update
    apt install -y "${PAQUETS_MANQUANTS[@]}"
fi

# Démarrage de libvirt si nécessaire
if ! systemctl is-active --quiet libvirtd; then
    log_info "Démarrage du service libvirt..."
    systemctl start libvirtd
    systemctl enable libvirtd
fi

# Téléchargement de l'ISO si nécessaire
if [[ ! -f "${CHEMIN_ISO}" ]]; then
    log_info "Téléchargement de l'ISO Ubuntu..."
    wget --progress=dot:giga -O "${CHEMIN_ISO}" "${URL_ISO}"
    
    if [[ ! -f "${CHEMIN_ISO}" ]]; then
        log_erreur "Échec du téléchargement de l'ISO"
        exit 1
    fi
    
    log_succes "ISO téléchargée avec succès"
else
    log_info "ISO déjà présente: ${CHEMIN_ISO}"
fi

# Création du fichier cloud-init
log_info "Création de la configuration cloud-init..."
i
# Création des fichiers cloud-init si nécessaires
if [[ ! -f "${SCRIPT_DIR}/user-data" ]]; then
    cat > "${SCRIPT_DIR}/user-data" << EOF
#cloud-config
hostname: ubuntu-server
password: ubuntu
chpasswd:
  expire: false
ssh_pwauth: true
package_update: true
package_upgrade: true
EOF
    log_info "Fichier user-data créé"
fi

if [[ ! -f "${SCRIPT_DIR}/meta-data" ]]; then
    cat > "${SCRIPT_DIR}/meta-data" << EOF
instance-id: ubuntu-server-001
local-hostname: ubuntu-server
EOF
    log_info "Fichier meta-data créé"
fi


# Création du répertoire temporaire pour cloud-init
CLOUD_INIT_DIR="${SCRIPT_DIR}/cloud-init-temp"
CLOUD_INIT_ISO="${SCRIPT_DIR}/cloud-init.iso"

mkdir -p "${CLOUD_INIT_DIR}"
cp "${SCRIPT_DIR}/user-data" "${CLOUD_INIT_DIR}/"
cp "${SCRIPT_DIR}/meta-data" "${CLOUD_INIT_DIR}/"

# Création de l'ISO cloud-init
log_info "Création de l'ISO cloud-init..."
genisoimage -output "${CLOUD_INIT_ISO}" -volid cidata -joliet -rock "${CLOUD_INIT_DIR}/user-data" "${CLOUD_INIT_DIR}/meta-data"  

if [[ ! -f "${CLOUD_INIT_ISO}" ]]; then
    log_erreur "Échec de la création de l'ISO cloud-init"
    rm -rf "${CLOUD_INIT_DIR}"
    exit 1
fi

log_succes "ISO cloud-init créée: ${CLOUD_INIT_ISO}"
rm -rf "${CLOUD_INIT_DIR}"

# Vérification si la VM existe déjà
if virsh list --all | grep -q "${NOM_VM}"; then
    log_info "La VM '${NOM_VM}' existe déjà"
    read -p "Voulez-vous la supprimer et la recréer? (o/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Oo]$ ]]; then
        log_info "Suppression de la VM existante..."
        virsh destroy "${NOM_VM}" 2>/dev/null || true
        virsh undefine "${NOM_VM}" --remove-all-storage 2>/dev/null || true
    else
        log_info "Annulation..."
        exit 0
    fi
fi

# Création du disque VM
DISQUE_VM="${CHEMIN_DISQUE}/${NOM_VM}.qcow2"
log_info "Création du disque VM: ${DISQUE_VM}"

# Création du répertoire si nécessaire
if [[ ! -d "${CHEMIN_DISQUE}" ]]; then
    mkdir -p "${CHEMIN_DISQUE}"
fi

# Création du disque
qemu-img create -f qcow2 "${DISQUE_VM}" "${TAILLE_DISQUE}"

# Vérification des chemins des ISO
if [[ ! -f "${CHEMIN_ISO}" ]]; then
    log_erreur "L'ISO Ubuntu n'a pas été trouvée à: ${CHEMIN_ISO}"
    exit 1
fi

if [[ ! -f "${CLOUD_INIT_ISO}" ]]; then
    log_erreur "L'ISO cloud-init n'a pas été trouvée à: ${CLOUD_INIT_ISO}"
    exit 1
fi

# Création de la VM
log_info "Création de la VM ${NOM_VM}..."
virt-install \
    --name="${NOM_VM}" \
    --memory="${RAM_VM}" \
    --vcpus="${VCPUS_VM}" \
    --disk="path=${DISQUE_VM},format=qcow2,bus=virtio" \
    --cdrom="${CHEMIN_ISO}" \
    --disk="path=${CLOUD_INIT_ISO},device=cdrom,bus=sata" \
    --network="bridge=${BRIDGE},model=virtio" \
    --graphics="vnc,listen=0.0.0.0" \
    --os-variant="ubuntu24.04" \
    --console="pty,target_type=serial" \
    --noautoconsole \
    --boot="uefi" \
    --features="acpi=on" \

if [[ $? -eq 0 ]]; then
    log_succes "VM '${NOM_VM}' créée avec succès!"
    log_info "Vous pouvez vous connecter à la console avec: virsh console ${NOM_VM}"
    log_info "L'installation d'Ubuntu se fait automatiquement"
    
    # Affichage du statut de la VM
    log_info "Statut de la VM:"
    virsh list --all | grep "${NOM_VM}"
    
    log_info "Commandes utiles:"
    echo "  Démarrer la VM: virsh start ${NOM_VM}"
    echo "  Arrêter la VM: virsh shutdown ${NOM_VM}"
    echo "  Forcer l'arrêt: virsh destroy ${NOM_VM}"
    echo "  Console: virsh console ${NOM_VM}"
    echo "  Informations: virsh dominfo ${NOM_VM}"
else
    log_erreur "Échec de la création de la VM"
    exit 1
fi

log_succes "Installation terminée!"
