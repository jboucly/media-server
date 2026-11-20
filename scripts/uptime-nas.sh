#!/bin/sh
# Path /etc/zfs/zed.d/all-discord.sh
# ZFS a un service de surveillance intégré, ZED (ZFS Event Daemon), 
# qui réagit aux événements du pool : disque défaillant, erreurs, fin de vérification… 
# Ce script envoie ces événements sur Discord.

# Il envoie : 

# ❌ une alerte immédiate si un disque du miroir passe en dégradé ou en défaut ;
# ⚠️ une alerte en cas d’erreurs de lecture ou de corruption, au maximum une par heure pour éviter le spam ;
# ✅ un message chaque mois à la fin de la vérification automatique (scrub), qui confirme que tout va bien ;
# 🔄 un message quand le miroir a fini de se reconstruire après un remplacement de disque.

# ZED -> Discord : alertes du pool ZFS, message lisible
[ -f "${ZED_ZEDLET_DIR}/zed.rc" ] && . "${ZED_ZEDLET_DIR}/zed.rc"
. "${ZED_ZEDLET_DIR}/zed-functions.sh"
WEBHOOK=__A_REMPLACER__
POOL="${ZEVENT_POOL}"

etat() {
  case "$1" in
    ONLINE) echo "OK" ;; DEGRADED) echo "dégradé" ;; FAULTED) echo "en panne" ;;
    UNAVAIL) echo "introuvable" ;; OFFLINE) echo "hors ligne" ;; REMOVED) echo "retiré" ;;
    *) echo "$1" ;;
  esac
}

case "${ZEVENT_SUBCLASS}" in
  statechange)
    [ "${ZEVENT_VDEV_STATE_STR}" = "ONLINE" ] && exit 0
    title="❌ ZFS : un disque du miroir est $(etat "${ZEVENT_VDEV_STATE_STR}")"; color=15158332
    msg="Les données restent accessibles grâce à l'autre disque, mais le miroir n'est plus protégé. Remplacer le disque rapidement." ;;
  scrub_finish)
    if zpool status -x "$POOL" | grep -q "is healthy"; then
      title="✅ ZFS : vérification mensuelle terminée"; color=3066993
      msg="Toutes les données du miroir ont été relues et contrôlées : aucune erreur."
    else
      title="⚠️ ZFS : vérification terminée AVEC des erreurs"; color=15105570
      msg="Des erreurs ont été trouvées. Regarder \`zpool status -v $POOL\` sur l'hôte."
    fi ;;
  resilver_finish)
    title="🔄 ZFS : reconstruction du miroir terminée"; color=3447003
    msg="Le disque remplacé est synchronisé : le miroir est de nouveau protégé." ;;
  data|io|checksum)
    zed_rate_limit "${POOL};${ZEVENT_SUBCLASS}" || exit 0
    title="⚠️ ZFS : erreurs de lecture détectées"; color=15105570
    msg="ZFS a détecté des erreurs (${ZEVENT_SUBCLASS}). Il les corrige grâce au miroir quand c'est possible. Surveiller le disque concerné." ;;
  *) exit 0 ;;
esac

health=$(etat "$(zpool list -H -o health "$POOL")")
usage=$(zpool list -H -o alloc,size,cap "$POOL" | awk '{print $1 " / " $2 " (" $3 ")"}')
disks=$(zpool status "$POOL" | awk '$1 ~ /^(ata|wwn|scsi)-/ || $1 ~ /^[0-9]{10,}$/ {
  n=$1; sub(/.*_/, "", n); err=$3+$4+$5
  icon = ($2=="ONLINE") ? "🟢" : "🔴"
  st = ($2=="ONLINE") ? "OK" : $2
  printf "%s %s : %s, %d erreur(s)\n", icon, n, st, err }')
scan=$(zpool status "$POOL" | sed -n 's/^ *scan: //p' | head -1)
errs=$(zpool status "$POOL" | sed -n 's/^errors: //p')
[ "$errs" = "No known data errors" ] && errs="Aucune"

payload=$(jq -n --arg t "$title" --argjson c "$color" --arg m "$msg" \
  --arg h "$health" --arg u "$usage" --arg d "${disks:-—}" \
  --arg s "${scan:-—}" --arg e "${errs:-—}" --arg p "$POOL" \
  '{username: "Rufus - ZFS",
    embeds: [{title: $t, color: $c, description: $m,
              fields: [
                {name: "Pool", value: $p, inline: true},
                {name: "État", value: $h, inline: true},
                {name: "Occupation", value: $u, inline: true},
                {name: "Disques", value: $d},
                {name: "Dernière vérification", value: $s},
                {name: "Erreurs de données", value: $e}
              ],
              footer: {text: "pve · ZFS"},
              timestamp: (now | todate)}]}')
curl -s -H "Content-Type: application/json" -d "$payload" "$WEBHOOK" >/dev/null
exit 0
EOF

WH=$(grep -m1 '^WEBHOOK=' /usr/local/bin/vzdump-discord.sh | cut -d= -f2-)
sed -i "s#^WEBHOOK=__A_REMPLACER__#WEBHOOK=${WH}#" /etc/zfs/zed.d/all-discord.sh
chmod 700 /etc/zfs/zed.d/all-discord.sh
grep -c '^WEBHOOK="https://discord.com/api/webhooks/' /etc/zfs/zed.d/all-discord.sh