"""Supplementary parser check for Windows; Xcode compilation remains authoritative."""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.validation' / 'deps'))
import tree_sitter
import tree_sitter_swift

parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
failures = []
count = 0
paths = [ROOT / item for item in sys.argv[1:]] if len(sys.argv) > 1 else [path for folder in ('App', 'Core', 'DesignSystem', 'Features', 'Providers', 'Tests') for path in (ROOT / folder).rglob('*.swift')]
for path in paths:
        count += 1
        source = path.read_bytes()
        tree = parser.parse(source)
        if tree.root_node.has_error:
            pending = [tree.root_node]
            while pending:
                node = pending.pop()
                if node.type == 'ERROR' or node.is_missing:
                    failures.append(f'{path.relative_to(ROOT)}:{node.start_point.row + 1}: {source[node.start_byte:node.end_byte][:100]!r}')
                pending.extend(reversed(node.children))
print('\n'.join(failures) if failures else f'Parsed {count} Swift files without syntax errors.')
sys.exit(bool(failures))
