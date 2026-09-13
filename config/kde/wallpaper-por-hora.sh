#!/usr/bin/env bash
# wallpaper-por-hora.sh -- troca o papel de parede conforme a hora do dia
# amanhecer 5-8h | dia 8-17h | entardecer 17-20h | noite 20-5h
set -euo pipefail

BASE="$HOME/Pictures/wallpapers-dynamic"
HORA=$(date +%H | sed 's/^0//')

if   [ "$HORA" -ge 5  ] && [ "$HORA" -lt 8 ];  then PASTA="dawn"
elif [ "$HORA" -ge 8  ] && [ "$HORA" -lt 17 ]; then PASTA="day"
elif [ "$HORA" -ge 17 ] && [ "$HORA" -lt 20 ]; then PASTA="dusk"
else                                                 PASTA="night"
fi

# guarda a última pasta usada para só trocar de novo quando o periodo mudar
# (senão fica trocando a cada 15min dentro do mesmo periodo tambem, o que é ok
# mas assim tambem gera variedade dentro do periodo)
IMG=$(find "$BASE/$PASTA" -type f -name '*.jpg' | shuf -n1)

if [ -n "$IMG" ]; then
  plasma-apply-wallpaperimage "$IMG" >/dev/null 2>&1
fi
