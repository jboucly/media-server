#!/bin/bash
# Path: /usr/local/bin/vzdump-discord.sh
# Hook vzdump -> rapport détaillé sur Discord

WEBHOOK='' # Set this to your Discord webhook URL
STATE="/tmp/vzdump-discord"
phase="$1"; vmid="${3:-}"

guest_name() {
  if [ "$VMTYPE" = "qemu" ]; then
    qm config "$1" 2>/dev/null | awk '/^name:/{print $2}'
  else
    pct config "$1" 2>/dev/null | awk '/^hostname:/{print $2}'
  fi
}

fmt_dur() { printf '%dm%02ds' $(( $1 / 60 )) $(( $1 % 60 )); }

case "$phase" in
  job-start)
    rm -rf "$STATE"; mkdir -p "$STATE"
    date +%s > "$STATE/job.start" ;;

  backup-start)
    date +%s > "$STATE/$vmid.start" ;;

  backup-end)
    start=$(cat "$STATE/$vmid.start" 2>/dev/null || date +%s)
    dur=$(( $(date +%s) - start ))
    size=$(du -h "$TARGET" 2>/dev/null | cut -f1)
    printf '✅ %-4s %-20s %6s  %s\n' "$vmid" "$(guest_name "$vmid")" "${size:-?}" "$(fmt_dur $dur)" >> "$STATE/lines" ;;

  backup-abort)
    printf '❌ %-4s %-20s ÉCHEC\n' "$vmid" "$(guest_name "$vmid")" >> "$STATE/lines" ;;

  job-end|job-abort)
    start=$(cat "$STATE/job.start" 2>/dev/null || date +%s)
    total=$(fmt_dur $(( $(date +%s) - start )))
    lines=$(cat "$STATE/lines" 2>/dev/null)
    ok=$(grep -c '^✅' "$STATE/lines" 2>/dev/null); ok=${ok:-0}
    ko=$(grep -c '^❌' "$STATE/lines" 2>/dev/null); ko=${ko:-0}
    if [ "$phase" = "job-abort" ] || [ "$ko" -gt 0 ]; then
      title="❌ Sauvegarde des VMs : échec"; color=15158332
    else
      title="✅ Sauvegarde des VMs réussie"; color=3066993
    fi
    usb=$(df -h --output=used,size,pcent /mnt/pve/backup-usb | tail -1 | xargs)

    payload=$(jq -n --arg t "$title" --argjson c "$color" --arg d "$lines" \
      --arg n "$ok OK / $ko échec(s)" --arg dur "$total" --arg usb "$usb" \
      '{username: "Rufus - Proxmox",
        embeds: [{
          title: $t, color: $c,
          description: ("```\n" + $d + "\n```"),
          fields: [
            {name: "Invités",      value: $n,   inline: true},
            {name: "Durée totale", value: $dur, inline: true},
            {name: "Disque USB",   value: $usb, inline: true}
          ],
          footer: {text: "pve · backup-usb"},
          timestamp: (now | todate)
        }]}')
    curl -s -H "Content-Type: application/json" -d "$payload" "$WEBHOOK" >/dev/null ;;
esac

exit 0