#!/usr/bin/env python3
"""
Parse RFID tag data from Yanpodo RU6500 via /dev/usb/hiddev0.
Simplified version with continuous monitoring.
"""

import os
import sys
import time

def decode_hiddev_report(data):
    """
    Decode hiddev report format.
    Extract value bytes as hex string.
    """
    hex_values = []
    
    # Parse 8 reports from the 64-byte chunk
    for i in range(8):
        offset = i * 8
        if offset + 5 <= len(data):
            report_type = data[offset]
            value_byte = data[offset + 4]
            
            if report_type == 0x03 and value_byte != 0x00:
                hex_values.append(f"{value_byte:02x}")
    
    return ''.join(hex_values)

def main():
    hiddev = '/dev/usb/hiddev0'
    
    if not os.path.exists(hiddev):
        print(f"Device {hiddev} not found")
        sys.exit(1)
    
    print("Yanpodo RU6500 RFID Tag Reader")
    print("=" * 60)
    print("Scanning for tags...\n")
    
    current_tag = []
    empty_count = 0
    
    try:
        with open(hiddev, 'rb') as f:
            while True:
                chunk = f.read(64)
                if not chunk:
                    continue
                
                decoded = decode_hiddev_report(chunk)
                
                if decoded:
                    # Got data
                    current_tag.append(decoded)
                    empty_count = 0
                    sys.stdout.write(f"\rAccumulating: {len(''.join(current_tag))//2} bytes")
                    sys.stdout.flush()
                else:
                    # Empty chunk
                    empty_count += 1
                    
                    # After 3 empty chunks, output the tag if we have data
                    if empty_count >= 3 and current_tag:
                        tag_hex = ''.join(current_tag).upper()
                        timestamp = time.strftime("%H:%M:%S")
                        print(f"\n[{timestamp}] Tag scanned!")
                        print(f"  EPC (hex): {tag_hex}")
                        print(f"  Length: {len(tag_hex)//2} bytes\n")
                        current_tag = []
                        empty_count = 0
    
    except KeyboardInterrupt:
        print("\n\nExiting...")
    except PermissionError:
        print(f"Permission denied. Run with sudo")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()

