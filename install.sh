#!/bin/bash
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Creating TAS conda environment..."
conda env create -f "$APP_DIR/environment.yml" || true

echo "Setting executable permissions..."
chmod +x "$APP_DIR/tas_gui.py"
chmod +x "$APP_DIR/run_pipeline.sh"
chmod +x "$APP_DIR/run_phylo3.sh"
chmod +x "$APP_DIR/covarplot.py"

echo "Creating desktop shortcut..."

mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/Desktop"

DESKTOP_FILE="$HOME/.local/share/applications/tas-gui.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=TAS
Exec=$APP_DIR/dist/tas_gui
Icon=$APP_DIR/tas_icon.png
Terminal=false
Categories=Science;
EOF

chmod 644 "$DESKTOP_FILE"

# Copy to Desktop
cp "$DESKTOP_FILE" "$HOME/Desktop/"
chmod +x "$HOME/Desktop/tas-gui.desktop"
update-desktop-database ~/.local/share/applications
echo "✅ Installation complete"
