#!/bin/bash

set -e

echo "=== Klipper Database Upload Installer ==="

# 1. Prompt for environment variables
read -p "1. Enter printer name: " PRINTER_NAME
read -s "2. Enter Pi user: " PI_USER
read -p "3. Enter PostgreSQL host: " DB_HOST
read -p "4. Enter PostgreSQL port [5432]: " DB_PORT
DB_PORT=${DB_PORT:-5432}
read -p "5. Enter PostgreSQL database name: " DB_NAME
read -p "6. Enter PostgreSQL user: " DB_USER
read -s -p "7. Enter PostgreSQL password: " DB_PASSWORD
echo

# 2. Prompt for frequency (in minutes)
read -p "How often should the script run (in minutes)? " FREQUENCY

# 3. Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="klipper_database_upload.py"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="/tmp/klipper_database_upload.log"
VENV_DIR="$SCRIPT_DIR/venv"

# 4. Create .env file
echo "Creating .env file..."
cat > "$ENV_FILE" <<EOF
PI_USER=$PI_USER
PRINTER_NAME=$PRINTER_NAME
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
EOF

# 5. Create Python virtual environment
echo "Creating Python virtual environment..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip

if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    pip install -r "$SCRIPT_DIR/requirements.txt"
else
    echo "Warning: requirements.txt not found. Installing psycopg2-binary directly."
    pip install psycopg2-binary
fi

deactivate

# 6. Create wrapper script to run with env
WRAPPER="$SCRIPT_DIR/run_klipper_upload.sh"
cat > "$WRAPPER" <<EOF
#!/bin/bash
source "$VENV_DIR/bin/activate"
set -a
source "$ENV_FILE"
set +a
python "$SCRIPT_DIR/$SCRIPT_NAME" >> "$LOG_FILE" 2>&1
EOF

chmod +x "$WRAPPER"

# 7. Add to crontab
CRON_JOB="*/$FREQUENCY * * * * $WRAPPER"
echo "Adding cron job: $CRON_JOB"
(crontab -l 2>/dev/null | grep -v "$WRAPPER"; echo "$CRON_JOB") | crontab -

echo "✅ Setup complete. The script will run every $FREQUENCY minutes."
echo "📄 Logs will be written to $LOG_FILE"

