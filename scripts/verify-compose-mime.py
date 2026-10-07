#!/usr/bin/env python3
"""Check Swift's emitted MIME using Python's independent RFC email parser."""
import sys
from email import policy
from email.parser import BytesParser
from pathlib import Path

message = BytesParser(policy=policy.default).parsebytes(Path(sys.argv[1]).read_bytes())
assert message.get_content_type() == "multipart/mixed"
assert not message.defects, message.defects
assert message["To"] == "other@example.com"
assert message["In-Reply-To"] == "<original@example.com>"
parts = list(message.iter_parts())
assert len(parts) == 2
assert parts[0].get_content_type() == "text/plain"
assert parts[0].get_payload(decode=True) == b"Hello\r\nWorld"
assert parts[1].get_content_type() == "application/octet-stream"
assert parts[1].get_content_disposition() == "attachment"
assert parts[1].get_filename() == "résumé.pdf", parts[1].get_filename()
assert parts[1].get_payload(decode=True) == bytes([0, 13, 10, 255, 128, 42])
assert all(not part.defects for part in parts)
print("Independent MIME verification passed: body, binary attachment, Unicode filename and headers.")
