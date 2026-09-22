import unittest
from pathlib import Path
from unittest.mock import patch
from test_enrollment import client


class AndroidSocketTests(unittest.TestCase):
    def test_termux_path_leaves_room_for_openssh_temporary_suffix(self):
        root = Path('/data/data/com.termux/files/home/.ssh/qrbridge')
        destination = dict(host='100.90.80.70', port=2222, user='Admin', hostkey='test-host-key')
        with patch.object(client, 'ROOT', root):
            path = client.control_path(destination)
            # Conservative 104-byte Unix socket bound including terminating NUL.
            self.assertLessEqual(len((str(path) + '.' + 'a' * 16).encode()) + 1, 104)
            self.assertEqual(path.parent, root)
            self.assertEqual(path, client.control_path(dict(reversed(list(destination.items())))))
            self.assertNotEqual(path, client.control_path(dict(destination, host='100.76.198.54')))
            self.assertNotEqual(path, client.control_path(dict(destination, hostkey='changed-key')))
