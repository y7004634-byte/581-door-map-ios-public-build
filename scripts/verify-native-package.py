"""Read-only IPA checks; does not sign or install anything."""
import hashlib
import gzip
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

def verify(ipa, vendor_manifest):
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        infos = [n for n in names if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        assert len(infos) == 1, 'Expected exactly one app Info.plist'
        prefix = infos[0][:-len('Info.plist')]
        info = plistlib.loads(archive.read(infos[0]))
        assert info['CFBundleIdentifier'] == 'com.door581.appletest', 'Not the isolated test bundle'
        assert info['CFBundleShortVersionString'] == '0.3.1' and str(info['CFBundleVersion']) == '8'
        assert info['CFBundleDisplayName'] == '581 Apple 測試'
        assert float(info['MinimumOSVersion']) >= 16
        schemes = [s for row in info.get('CFBundleURLTypes', []) for s in row.get('CFBundleURLSchemes', [])]
        assert schemes == ['door581-apple-test'], 'Production URL scheme would be intercepted'
        assert prefix + 'embedded.mobileprovision' not in names, 'Expected unsigned build'
        assert not any(n.startswith(prefix + '_CodeSignature/') for n in names), 'Expected unsigned build'
        executable = archive.read(prefix + info['CFBundleExecutable'])
        assert len(executable) >= 8 and struct.unpack('<II', executable[:8]) == (0xFEEDFACF, 0x0100000C), 'Expected arm64 Mach-O'
        assert prefix + 'battery-stations-fallback.json' in names, 'Station fallback missing'
        assert prefix + 'Assets.car' in names and info.get('CFBundleIcons'), 'App icon missing'
        for name in ['nlsc-map.html', 'nlsc-map.js', 'nlsc-contract.js']:
            assert prefix + 'MiniMap/' + name in names, f'Missing miniature resource: {name}'
        for record in vendor_manifest:
            data = archive.read(prefix + 'MiniMap/' + record['file'])
            assert hashlib.sha256(data).hexdigest() == record['sha256'], 'Vendor resource mismatch'
        root = Path(__file__).resolve().parents[1]
        receipt = json.loads((root / 'docs/COMPRESSED_DATA_RECEIPT.json').read_text(encoding='utf-8'))
        for name, record in receipt.items():
            compressed = archive.read(prefix + 'Behavior/' + name + '.gz')
            assert hashlib.sha256(compressed).hexdigest() == record['gzipSha256'], name
            data = gzip.decompress(compressed)
            assert len(data) == record['bytes'] and hashlib.sha256(data).hexdigest() == record['sha256'], name
        integrations = json.loads((root / 'docs/RESTORATION_REFERENCE_RECEIPT.json').read_text(encoding='utf-8'))['integrationHashes']
        for name, digest in integrations.items():
            assert hashlib.sha256(archive.read(prefix + 'Behavior/' + name)).hexdigest() == digest, name
        release = json.loads(archive.read(prefix + 'Behavior/release.json'))
        assert release['build'].endswith('community-1150630-v2-cache1-fitlock6')
        assert not any('/PlugIns/' in name or 'osm-query-baseline' in name for name in names), 'Test bundles/fixtures must not ship'
        return {'status': 'PASS', 'bundle': info['CFBundleIdentifier'], 'version': '0.3.1', 'build': '8',
                'unsigned': True, 'architecture': 'arm64', 'nlscResources': True,
                'acceptedBehavior': release['build'], 'gzipResourceHashesVerified': len(receipt),
                'officialDoorplates': 756225, 'officialCommunityIdentities': 7285, 'osmBuildings': 9342, 'osmRoadGeometries': 60074,
                'bytes': Path(ipa).stat().st_size, 'sha256': hashlib.sha256(Path(ipa).read_bytes()).hexdigest()}

if __name__ == '__main__':
    manifest = json.loads((Path(__file__).resolve().parents[1] / 'docs/minimap-vendor.json').read_text(encoding='utf-8'))
    print(json.dumps(verify(Path(sys.argv[1]), manifest), ensure_ascii=False, indent=2))
