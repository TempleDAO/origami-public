#!/usr/bin/env python3
import re
import sys
import os
import requests
import time
from typing import Dict, Optional

scripts_dir = os.path.dirname(os.path.abspath(__file__))

# Thanks anthropic!!

def get_contract_creation_block(chainid: str, address: str, api_key: str) -> Optional[int]:
    """Get the block number when a contract was created using Etherscan API."""
    
    # Skip empty addresses
    if not address or address == '0x':
        return None
    
    params = {
        'chainid': chainid,
        'module': 'contract',
        'action': 'getcontractcreation',
        'contractaddresses': address,
        'apikey': api_key
    }
    
    try:
        etherscan_url = "https://api.etherscan.io/v2/api"
        response = requests.get(etherscan_url, params=params)
        response.raise_for_status()
        data = response.json()
        
        if data['status'] == '1' and data['result']:
            # Convert string block number to decimal
            block_hex = data['result'][0]['blockNumber']
            block = int(block_hex, 10)
            print (f"contract: {address} : {block}")
            return block
        else:
            print(f"Warning: Could not get creation block for {address}: {data.get('message', 'Unknown error')}")
            return None
            
    except Exception as e:
        print(f"Error fetching creation block for {address}: {e}")
        return None

def update_creation_blocks(chainid, file_path: str):
    """Update creationBlock values using Etherscan API to get actual contract creation blocks."""
    
    api_key = os.getenv('ETHERSCAN_API_KEY')
    if not api_key:
        print("Error: ETHERSCAN_API_KEY environment variable not set")
        sys.exit(1)
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Pattern to match address and creationBlock pairs
    pattern = r"(address:\s*'([^']+)',\s*(?:\n\s*)?creationBlock:\s*)(\d+)"
    
    def replace_creation_block(match):
        prefix = match.group(1)
        address = match.group(2)
        existing = match.group(3)

        creation_block = None

        if existing == "0": 
            print(f"Fetching creation block for {address}...")
            creation_block = get_contract_creation_block(chainid, address, api_key)
            time.sleep(0.2)
      
        # Use the fetched block number, or keep original if fetch failed
        if creation_block is not None:
            return f"{prefix}{creation_block}"
        else:
            # Extract current value to keep it unchanged
            current_match = re.search(r'creationBlock:\s*(\d+)', match.group(0))
            current_value = current_match.group(1) if current_match else '0'
            return f"{prefix}{current_value}"
    
    # Replace all matches
    updated_content = re.sub(pattern, replace_creation_block, content)
    
    # Write back to file
    with open(file_path, 'w') as f:
        f.write(updated_content)
    
    print(f"Updated creationBlock values in {file_path}")

if __name__ == "__main__":
    file_path = os.path.join(scripts_dir, "deploys/mainnet/contract-addresses/mainnet.ts")
    update_creation_blocks(1, file_path)

    file_path = os.path.join(scripts_dir, "deploys/berachain/contract-addresses/berachain.ts")
    update_creation_blocks(80094, file_path)
