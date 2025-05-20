#!/bin/bash

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (sudo)"
    exit 1
fi

# Configuration
NEW_CPU_NAME="3rd Gen HRYDEN E2980H"
NEW_VENDOR_NAME="HRYDEN Inc."
TEMP_DIR=$(mktemp -d)
MOCK_CPUINFO="$TEMP_DIR/cpuinfo"

# Create modified cpuinfo with complete CPU identity change
{
    while IFS= read -r line; do
        case "$line" in
            *"model name"*)
                echo "model name      : $NEW_CPU_NAME"
                ;;
            *"vendor_id"*)
                echo "vendor_id       : $NEW_VENDOR_NAME"
                ;;
            *"cpu family"*)
                echo "cpu family      : 9"
                ;;
            *"model"*)
                if [[ $line =~ ^model[[:space:]]*: ]]; then
                    echo "model           : 33"
                else
                    echo "$line"
                fi
                ;;
            *"stepping"*)
                echo "stepping        : 2"
                ;;
            *)
                echo "$line"
                ;;
        esac
    done
} < /proc/cpuinfo > "$MOCK_CPUINFO"

# Create correct DMI structure
mkdir -p "$TEMP_DIR/sys/devices/virtual/dmi/id"
cd "$TEMP_DIR/sys/devices/virtual/dmi/id"

# Create the DMI files with consistent naming
echo "$NEW_VENDOR_NAME" > sys_vendor
echo "Hydren System" > product_name
echo "1.0" > product_version
echo "$NEW_VENDOR_NAME" > board_vendor
echo "Hydren Board" > board_name
echo "$NEW_VENDOR_NAME" > bios_vendor
echo "Hydren BIOS 1.0" > bios_version

# Create CPU topology structure
CPU_COUNT=$(grep -c "^processor" /proc/cpuinfo)
for ((i=0; i<CPU_COUNT; i++)); do
    mkdir -p "$TEMP_DIR/sys/devices/system/cpu/cpu$i/topology"
    # Create topology files
    echo "1" > "$TEMP_DIR/sys/devices/system/cpu/cpu$i/topology/core_id"
    echo "1" > "$TEMP_DIR/sys/devices/system/cpu/cpu$i/topology/physical_package_id"
done

# Create CPU vendor information
mkdir -p "$TEMP_DIR/sys/devices/system/cpu/cpu0"
echo "$NEW_VENDOR_NAME" > "$TEMP_DIR/sys/devices/system/cpu/cpu0/vendor"

# Create systemd service
cat > "/etc/systemd/system/cpu-spoof.service" << EOF
[Unit]
Description=CPU and System Information Spoofer
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '\
    mount --bind $MOCK_CPUINFO /proc/cpuinfo && \
    mount --bind $TEMP_DIR/sys/devices/virtual/dmi/id /sys/devices/virtual/dmi/id && \
    for i in \$(seq 0 $((CPU_COUNT-1))); do \
        [ -d "$TEMP_DIR/sys/devices/system/cpu/cpu\$i" ] && \
        mount --bind "$TEMP_DIR/sys/devices/system/cpu/cpu\$i/topology" "/sys/devices/system/cpu/cpu\$i/topology"; \
    done && \
    mount --bind "$TEMP_DIR/sys/devices/system/cpu/cpu0/vendor" "/sys/devices/system/cpu/cpu0/vendor"'

[Install]
WantedBy=multi-user.target
EOF

# Move spoof files to permanent location
mkdir -p /usr/local/lib/system-spoof
cp -r "$TEMP_DIR"/* /usr/local/lib/system-spoof/

# Update service file with permanent paths
sed -i "s|$TEMP_DIR|/usr/local/lib/system-spoof|g" /etc/systemd/system/cpu-spoof.service

# Enable and start the service
systemctl daemon-reload
systemctl enable cpu-spoof
systemctl start cpu-spoof

echo -e "\nSystem information has been spoofed!"
echo "Current CPU info:"
cat /proc/cpuinfo | grep "model name\|vendor_id"
echo -e "\nNote: For complete effect, please reboot the system."
