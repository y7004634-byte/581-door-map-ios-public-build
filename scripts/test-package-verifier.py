import hashlib
import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path
spec = importlib.util.spec_from_file_location('verify_native_package', Path(__file__).with_name('verify-native-package.py'))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)

class PackageTests(unittest.TestCase):
    """Synthetic zip fixtures are NOT installable IPA evidence."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'fixture.zip'
        self.vendor = [{'file': 'maplibre-gl.js', 'sha256': hashlib.sha256(b'vendor').hexdigest()}]
    def tearDown(self): self.temp.cleanup()
    def fixture(self, bundle='com.door581.appletest', scheme='door581-apple-test', missing=False, signed=False, arch=0x0100000C):
        prefix = 'Payload/DoorMap581.app/'
        info = {'CFBundleIdentifier': bundle, 'CFBundleShortVersionString': '0.2.1', 'CFBundleVersion': '6',
                'CFBundleDisplayName': '581 Apple 測試', 'MinimumOSVersion': '16.0', 'CFBundleExecutable': 'DoorMap581',
                'CFBundleURLTypes': [{'CFBundleURLSchemes': [scheme]}], 'CFBundleIcons': {'CFBundlePrimaryIcon': {}}}
        with zipfile.ZipFile(self.path, 'w') as archive:
            archive.writestr(prefix + 'Info.plist', plistlib.dumps(info))
            archive.writestr(prefix + 'DoorMap581', struct.pack('<II', 0xFEEDFACF, arch))
            archive.writestr(prefix + 'Assets.car', b'fixture')
            archive.writestr(prefix + 'battery-stations-fallback.json', b'fixture')
            if signed: archive.writestr(prefix + 'embedded.mobileprovision', b'fixture')
            if not missing:
                for name in ['nlsc-map.html', 'nlsc-map.js', 'nlsc-contract.js']: archive.writestr(prefix + 'MiniMap/' + name, b'fixture')
            archive.writestr(prefix + 'MiniMap/maplibre-gl.js', b'vendor')
    def test_valid_fixture(self):
        self.fixture(); self.assertEqual(verifier.verify(self.path, self.vendor)['status'], 'PASS')
    def test_production_bundle_rejected(self):
        self.fixture(bundle='com.door581.probe')
        with self.assertRaises(AssertionError): verifier.verify(self.path, self.vendor)
    def test_production_scheme_rejected(self):
        self.fixture(scheme='waze')
        with self.assertRaises(AssertionError): verifier.verify(self.path, self.vendor)
    def test_missing_resources_rejected(self):
        self.fixture(missing=True)
        with self.assertRaises(AssertionError): verifier.verify(self.path, self.vendor)
    def test_wrong_architecture_rejected(self):
        self.fixture(arch=0x01000007)
        with self.assertRaises(AssertionError): verifier.verify(self.path, self.vendor)
    def test_unexpected_provisioning_rejected(self):
        self.fixture(signed=True)
        with self.assertRaises(AssertionError): verifier.verify(self.path, self.vendor)

if __name__ == '__main__': unittest.main()
