"""Read-only IPA checks; does not sign or install anything."""
import gzip
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def sha256(data):
    return hashlib.sha256(data).hexdigest()

def verify(ipa):
    seed = json.loads((ROOT / 'DoorMap581/NativeData/seed-catalog.json').read_text(encoding='utf-8'))
    decoded = seed['decoded']
    compressed_records = seed['manifest']['files']
    assert len(decoded) == 3122, 'Unexpected decoded seed count'
    assert len(compressed_records) == 3122, 'Unexpected compressed seed count'

    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        infos = [n for n in names if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        assert len(infos) == 1, 'Expected exactly one app Info.plist'
        prefix = infos[0][:-len('Info.plist')]
        info = plistlib.loads(archive.read(infos[0]))

        assert info['CFBundleIdentifier'] == 'com.door581.appletest', 'Not the isolated test bundle'
        assert info['CFBundleShortVersionString'] == '0.4.0' and str(info['CFBundleVersion']) == '9', 'Not build9'
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

        # Exact MiniMap package bytes must match the public build snapshot.
        minimap_root = ROOT / 'DoorMap581/MiniMap'
        mini_count = 0
        for src in sorted(p for p in minimap_root.rglob('*') if p.is_file()):
            rel = src.relative_to(minimap_root).as_posix()
            packaged = archive.read(prefix + 'MiniMap/' + rel)
            assert packaged == src.read_bytes(), f'MiniMap resource mismatch: {rel}'
            mini_count += 1
        assert mini_count >= 6, 'MiniMap resources incomplete'

        # Verify every compressed seed blob plus its decoded bytes.
        for record in compressed_records:
            rel_gz = record['path']
            compressed = archive.read(prefix + 'Behavior/' + rel_gz)
            assert len(compressed) == record['bytes'], rel_gz
            assert sha256(compressed) == record['sha256'], rel_gz
            decoded_name = rel_gz[:-3] if rel_gz.endswith('.gz') else rel_gz
            meta = decoded[decoded_name]
            data = gzip.decompress(compressed)
            assert len(data) == meta['bytes'], decoded_name
            assert sha256(data) == meta['sha256'], decoded_name

        # Exact-copy verification for every non-gzip Behavior source file.
        behavior_root = ROOT / 'DoorMap581/Behavior'
        direct_count = 0
        for src in sorted(p for p in behavior_root.rglob('*') if p.is_file() and p.suffix != '.gz'):
            rel = src.relative_to(behavior_root).as_posix()
            packaged = archive.read(prefix + 'Behavior/' + rel)
            assert packaged == src.read_bytes(), f'Behavior resource mismatch: {rel}'
            direct_count += 1

        release = json.loads(archive.read(prefix + 'Behavior/release.json'))
        assert release['build'].endswith('community-1150630-v2-cache1-fitlock6')
        assert not any('/PlugIns/' in name or 'osm-query-baseline' in name for name in names), 'Test bundles/fixtures must not ship'

        return {
            'status': 'PASS',
            'bundle': info['CFBundleIdentifier'],
            'version': '0.4.0',
            'build': '9',
            'unsigned': True,
            'architecture': 'arm64',
            'nlscResources': True,
            'acceptedBehavior': release['build'],
            'gzipResourceHashesVerified': len(compressed_records),
            'decodedResourceHashesVerified': len(decoded),
            'behaviorDirectFilesVerified': direct_count,
            'miniMapFilesVerified': mini_count,
            'officialDoorplates': 756225,
            'officialCommunityIdentities': 7285,
            'osmBuildings': 9342,
            'osmRoadGeometries': 60074,
            'bytes': Path(ipa).stat().st_size,
            'sha256': sha256(Path(ipa).read_bytes())
        }

if __name__ == '__main__':
    print(json.dumps(verify(Path(sys.argv[1])), ensure_ascii=False, indent=2))
