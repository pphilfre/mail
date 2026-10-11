#!/usr/bin/env python3
"""Independently parse the MIME emitted by PremiumMailTests with Python's RFC parser."""
import sys
from email import policy
from email.parser import BytesParser
from pathlib import Path

message = BytesParser(policy=policy.default).parsebytes(Path(sys.argv[1]).read_bytes())
assert message.get_content_type() == "multipart/mixed"
parts = list(message.iter_parts())
assert len(parts) == 2
assert parts[0].get_content_type() == "multipart/alternative"
alternatives = list(parts[0].iter_parts())
assert [part.get_content_type() for part in alternatives] == ["text/plain", "text/html"]
assert alternatives[0].get_payload(decode=True) == b"Hello\r\n\xe2\x80\xa2 Review"
html = alternatives[1].get_payload(decode=True).decode("utf-8")
assert "<strong>Hello</strong>" in html
assert "<ul><li>Review</li></ul>" in html
assert parts[1].get_filename() == "notes.txt"
assert parts[1].get_payload(decode=True) == bytes([1, 2, 3])
assert all(not part.defects for part in message.walk())
print("Rich MIME verified: nested alternatives, formatted HTML, plain text, and exact attachment bytes.")
