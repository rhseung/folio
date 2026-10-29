#!/usr/bin/env bash
# Screens take type sizes, colors and corner radii from Theme (docs/DESIGN.md). A value that belongs to one screen
# alone carries `// design: one-off, <why>` on its line. app/design is exempt: it is where the tokens are applied.
set -euo pipefail
cd "$(dirname "$0")/.."
colors='red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|gray|white|black'
hits=$(rg -n --glob '*.swift' \
  -e '\.system\(size:' \
  -e 'cornerRadius: [0-9]' \
  -e 'Color\((red|white|hue|light):' \
  -e '0x[0-9A-Fa-f]{6}' \
  -e "Color\.($colors)\b" \
  -e "[(:,?] ?\.($colors)\b" \
  app/features app/app \
  | rg -v 'design: one-off' \
  | rg -v 'shadow\(color: \.black' || true)
if [[ -n "$hits" ]]; then
  echo "Raw design values outside Theme (use a token, or mark the line // design: one-off, <why>):" >&2
  echo "$hits" >&2
  exit 1
fi

# Spacing, sizes and corner radii sit on a 4pt grid, 2pt where 4 is too coarse. Type sizes and stroke widths are exempt,
# and so are 1pt hairlines.
odd='-?([1-9][0-9]*[13579]|[3579]|[0-9]+\.[0-9]+)([^0-9.%]|$)'
grid=$(rg -n --glob '*.swift' \
  -e "\b(spacing|width|height|cornerRadius|top|leading|bottom|trailing|minLength|dx|dy): $odd" \
  -e "padding\((\.[a-zA-Z]+, )?$odd\)" \
  -e "CGFloat = $odd" \
  -e "(CourseDot|IconTile|Avatar)\([^)]*size: $odd" \
  app \
  | rg -v 'design: one-off' || true)
if [[ -n "$grid" ]]; then
  echo "Off the 4/2pt grid (spacing, sizes and radii are multiples of 4, or of 2 where 4 is too coarse):" >&2
  echo "$grid" >&2
  exit 1
fi
