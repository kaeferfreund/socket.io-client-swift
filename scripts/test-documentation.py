#!/usr/bin/env python3
"""Regression checks for the offline documentation validator."""
from pathlib import Path
import runpy
import tempfile
import unittest

CHECKER = runpy.run_path(str(Path(__file__).with_name('check-documentation.py')))


class DocumentationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write('README.md', '# Start\n')

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8')
        return path

    def check(self):
        return CHECKER['validate'](self.root)

    def test_valid_relative_file_and_heading(self):
        self.write('README.md', '[Guide](Documentation/Guide.md#example)\n')
        self.write('Documentation/Guide.md', '# Example\n[Back](../README.md)\n')
        self.assertEqual(self.check(), [])

    def test_missing_file_fails(self):
        self.write('README.md', '[Missing](missing.md)')
        self.assertIn('missing path', self.check()[0])

    def test_missing_fragment_fails(self):
        self.write('README.md', '# Start\n[Missing](#absent)')
        self.assertIn('missing anchor', self.check()[0])

    def test_duplicate_and_unicode_headings(self):
        self.write('README.md', '# Café & `Swift`\n## Same\n## Same\n[One](#café--swift) [Two](#same-1)')
        self.assertEqual(self.check(), [])

    def test_existing_numbered_heading_does_not_collide(self):
        self.assertEqual(CHECKER['anchors']('# A\n# A-1\n# A\n'), {'a', 'a-1', 'a-2'})

    def test_fenced_and_inline_code_and_comments_are_ignored(self):
        self.write('README.md', '# Start\n```md\n[No](absent.md)\n```\n~~~\n[No](absent.md)\n~~~\n`[No](absent.md)`\n<!-- [No](absent.md) -->')
        self.assertEqual(self.check(), [])

    def test_space_and_parentheses_in_paths(self):
        self.write('README.md', '[One](a%20b.md) [Two](file(1).md) [Three](<a b.md>)')
        self.write('a b.md', '# A')
        self.write('file(1).md', '# B')
        self.assertEqual(self.check(), [])

    def test_reference_definition_and_undefined_reference(self):
        self.write('README.md', '# Start\n[Here][guide]\n[guide]: #start\n')
        self.assertEqual(self.check(), [])
        self.write('README.md', '[Here][missing]')
        self.assertIn('undefined Markdown reference', self.check()[0])

    def test_reference_destination_is_checked(self):
        self.write('README.md', '[Here][guide]\n[guide]: absent.md\n')
        self.assertIn('missing path', self.check()[0])

    def test_html_links_and_ids(self):
        self.write('README.md', '<a id="target"></a>\n<a href="#target">Here</a>')
        self.assertEqual(self.check(), [])
        self.write('README.md', '<img src="missing.png">')
        self.assertIn('missing path', self.check()[0])

    def test_remote_links_are_not_fetched(self):
        self.write('README.md', '[Remote](https://example.invalid/missing.md#no)')
        self.assertEqual(self.check(), [])

    def test_pages_current_repo_link_is_local(self):
        self.write('docs/index.html', '<a href="https://github.com/kaeferfreund/socket.io-client-swift/blob/master/missing.md">No</a>')
        self.assertIn('missing path', self.check()[0])

    def test_pinned_history_is_not_mistaken_for_current(self):
        self.write('README.md', '[Old](https://github.com/kaeferfreund/socket.io-client-swift/blob/7adf66498a086bdb7b5e75d032c9560b0b7aec64/missing.md)')
        self.assertEqual(self.check(), [])

    def test_path_escape_is_rejected(self):
        self.write('README.md', '[Escape](../outside.md)')
        self.assertIn('outside repository', self.check()[0])

    def test_historical_bodies_excluded_but_indexes_checked(self):
        for name in ('CHANGELOG.md', 'Documentation/ProtocolParityReview.md',
                     'Documentation/ReviewEvidence/Old.md', 'Documentation/Archive/UsageDocs/FAQ.md'):
            self.write(name, '[Historical](absent.md)')
        self.assertEqual(self.check(), [])
        self.write('Documentation/Archive/README.md', '[Broken](absent.md)')
        self.assertIn('missing path', self.check()[0])

    def test_source_line_number_survives_code_fences(self):
        self.write('README.md', '```\nignored\n```\n[Broken](missing.md)\n')
        self.assertTrue(self.check()[0].startswith('README.md:4:'))

    def test_link_with_title(self):
        self.write('README.md', '# Start\n[Here](#start "A title")')
        self.assertEqual(self.check(), [])


if __name__ == '__main__':
    unittest.main()
