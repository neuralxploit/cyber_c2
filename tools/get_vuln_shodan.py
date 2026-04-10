import shodan
import json

api = shodan.Shodan('b6ZHqNQ9vnogziP2CMMwMFE1404Wa9U4')

# Search for Next.js servers
results = api.search('\"_next\" http', limit=1000)

targets = []
for r in results['matches']:
    ip = r['ip_str']
    port = r['port']
    org = r.get('org', 'Unknown')
    country = r.get('location', {}).get('country_name', 'Unknown')
    
    # Build URL
    ssl = r.get('ssl') is not None or port == 443
    proto = 'https' if ssl else 'http'
    
    hostnames = r.get('hostnames', [])
    hostname = hostnames[0] if hostnames else None
    host = hostname if hostname else ip
    
    url = f'{proto}://{host}:{port}' if port not in [80, 443] else f'{proto}://{host}'
    
    targets.append({
        'url': url,
        'ip': ip,
        'port': port,
        'org': org,
        'country': country
    })
    print(f'{url} | {org} | {country}')

# Save to file
with open('nextjs_targets.json', 'w') as f:
    json.dump(targets, f, indent=2)

print(f'\n✅ Saved {len(targets)} targets to targets/nextjs_targets.json')
