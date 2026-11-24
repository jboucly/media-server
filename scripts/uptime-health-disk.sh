# Path : etc/smartd.conf => Fichier de conf de surveillance de tous les disques, alertes Discord
# DEVICESCAN -d removable -d sat -a -o on -S on -n standby,q -s (S/../../7/02|L/../15/./10) -W 0,50,55 -m <nomailer> -M exec /usr/local/bin/smartd-discord.sh -M daily -M test

# Ce que fait cette ligne :

# Option	Rôle
# DEVICESCAN -d removable -d sat	Surveille tous les disques détectés, y compris le disque USB, sans erreur s'il est débranché
# -a	                            Surveille la santé globale, les attributs d'usure, les secteurs défectueux et les erreurs
# -n standby,q	                    Ne réveille pas un disque en veille juste pour le contrôler
# -s (S/../../7/02|L/../15/./10)	Test court chaque dimanche à 2 h, test long le 15 du mois à 10 h (en dehors des sauvegardes et du scrub)
# -W 0,50,55	                    Alerte si un disque dépasse 55 °C
# -M daily	                        Rappel quotidien tant que le problème persiste
# -M test	                        Message de test au démarrage, à retirer ensuite

# PATH : /usr/local/bin/smartd-discord.sh
# Script de notification Discord pour smartd (Proxmox)

#!/bin/bash
# smartd -> Discord : alertes de santé des disques
WEBHOOK=__A_REMPLACER__

case "$SMARTD_FAILTYPE" in
    EmailTest)   title="🧪 SMART : test de notification"; color=3447003
    msg="La surveillance de ce disque est active." ;;
    Health)      title="❌ SMART : le disque annonce une panne imminente"; color=15158332
    msg="Le disque signale lui-même qu'il est en fin de vie. Sauvegarder et le remplacer au plus vite." ;;
    CurrentPendingSector|OfflineUncorrectableSector)
        title="⚠️ SMART : secteurs défectueux détectés"; color=15105570
    msg="Des zones du disque sont devenues illisibles. Premier signe d'usure : surveiller et prévoir le remplacement." ;;
    Usage)       title="⚠️ SMART : un indicateur d'usure a dépassé son seuil"; color=15105570
    msg="Un attribut SMART critique est passé sous le seuil du fabricant. Prévoir le remplacement." ;;
    SelfTest)    title="❌ SMART : échec du test automatique"; color=15158332
    msg="Le test périodique du disque a échoué. Vérifier avec smartctl -l selftest." ;;
    ErrorCount)  title="⚠️ SMART : nouvelles erreurs enregistrées"; color=15105570
    msg="Le disque a enregistré de nouvelles erreurs. Peut venir d'un câble ou du disque lui-même." ;;
    Temperature) title="🌡️ SMART : température trop élevée"; color=15105570
    msg="Le disque chauffe trop. Vérifier la ventilation de la tour." ;;
    *)           title="⚠️ SMART : problème sur un disque ($SMARTD_FAILTYPE)"; color=15105570
    msg="smartd a détecté une anomalie. Vérifier avec smartctl -a." ;;
esac

model=$(echo "$SMARTD_DEVICEINFO" | cut -d, -f1)
serial=$(echo "$SMARTD_DEVICEINFO" | sed -n 's/.*S\/N:\([^,]*\).*/\1/p')

payload=$(jq -n --arg t "$title" --argjson c "$color" --arg m "$msg" \
    --arg mo "${model:-?}" --arg s "${serial:-?}" --arg d "${SMARTD_DEVICE:-?}" \
    --arg r "${SMARTD_MESSAGE:-—}" --arg f "${SMARTD_TFIRST:-—}" \
    '{username: "Rufus - Disques",
    embeds: [{title: $t, color: $c, description: $m,
              fields: [
                {name: "Disque", value: $mo, inline: true},
                {name: "N° de série", value: $s, inline: true},
                {name: "Périphérique", value: $d, inline: true},
                {name: "Détail", value: ("```" + $r + "```")},
                {name: "Première détection", value: $f}
              ],
              footer: {text: "pve · smartd"},
timestamp: (now | todate)}]}')
curl -s -H "Content-Type: application/json" -d "$payload" "$WEBHOOK" >/dev/null
exit 0