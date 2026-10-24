"""Python reference contracts, mirrored in test/core_regressions_test.dart."""

import unittest

from slack_table.core import (
    AmbiguousColumnsError, ParseError, Table, format_markdown, format_tsv,
    parse_table, render,
)


class CoreRegressionTests(unittest.TestCase):
    def test_quoted_csv_cells_and_newlines(self):
        self.assertEqual(
            render('Name,Note\r\n"Doe, Jane","said ""hi""\r\non Monday"\r\n'),
            'Name\tNote\nDoe, Jane\tsaid "hi" on Monday',
        )

    def test_csv_keeps_numbers_as_text_and_pads_rows(self):
        self.assertEqual(
            render('ID,Amount,Other\n001,1.00\n002,1e3,""', input_format="csv"),
            'ID\tAmount\tOther\n001\t1.00\t\n002\t1e3\t',
        )

    def test_permissive_csv_quote_behavior(self):
        for text, expected in [
            ('A,B\n"unclosed,value', 'A\tB\nunclosed,value\t'),
            ('A,B\n "a",b', 'A\tB\n"a"\tb'),
            ('A,B\n"a"suffix,b', 'A\tB\nasuffix\tb'),
            ('A,B\na"b,c', 'A\tB\na"b\tc'),
        ]:
            with self.subTest(text=text):
                self.assertEqual(render(text, input_format="csv"), expected)

    def test_quoted_tsv_and_empty_rows(self):
        self.assertEqual(
            render('A\tB\n\t\n"x\ty"\tz\n', input_format="tsv"),
            'A\tB\nx y\tz',
        )

    def test_unicode_markdown_width_counts_code_points(self):
        self.assertEqual(
            format_markdown(Table([["😀", "e\u0301"], ["😀😀😀😀", "x"]])),
            '| 😀    | e\u0301  |\n| ---- | --- |\n| 😀😀😀😀 | x   |',
        )

    def test_python_whitespace_and_bom_semantics(self):
        for whitespace in ['\x1c', '\x85', '\xa0', '\u2003', '\u202f']:
            with self.subTest(whitespace=repr(whitespace)):
                self.assertEqual(
                    format_tsv(Table([[whitespace + 'a' + whitespace + 'b', ' c ']])),
                    'a b\tc',
                )
        self.assertEqual(render('\ufeffA,B\nx,y'), '\ufeffA\tB\nx\ty')

    def test_source_format_and_detection_precedence(self):
        for text, source in [
            ('| A | B |\n| --- | --- |\n| x | y |', 'markdown'),
            ('A\tB\nx\ty', 'tsv'),
            ('A,B\nx,y', 'csv'),
            ('A | B\nx | y', 'pipe'),
            ('A\n\nB\n\nx\n\ny', 'spaced'),
            ('A\tB\tC\nx\ny\nz', 'cursor'),
        ]:
            with self.subTest(source=source):
                self.assertEqual(parse_table(text).source_format, source)

    def test_markdown_escapes_and_surrounding_prose(self):
        self.assertEqual(
            parse_table('Intro\n| A | B |\n| :--- | ---: |\n| x\\|y | z |\nEnd').rows,
            [['A', 'B'], ['x|y', 'z']],
        )
        self.assertEqual(parse_table('A|B\nx|y\\', 'pipe').rows, [['A', 'B'], ['x', 'y\\']])

    def test_errors_and_column_candidates(self):
        with self.assertRaisesRegex(ParseError, "unknown input format"):
            parse_table('A,B', 'invalid')
        text = '\n\n'.join(str(i) for i in range(12))
        with self.assertRaises(AmbiguousColumnsError) as raised:
            parse_table(text)
        self.assertEqual(raised.exception.candidates, [2, 3, 4, 6])
        self.assertEqual(
            str(raised.exception), 'ambiguous column count; valid choices are 2, 3, 4, 6',
        )
        with self.assertRaisesRegex(ParseError, "multiple complete rows of 5 columns"):
            parse_table(text, 'spaced', columns=5)

    def test_cursor_fragment_errors(self):
        with self.assertRaisesRegex(ParseError, "ended before a row was complete"):
            parse_table('A\tB\tC\nx\ny', 'cursor')

    def test_empty_rows_and_empty_cells(self):
        self.assertEqual(format_tsv(Table([[], []])), '\n')
        with self.assertRaisesRegex(ParseError, "no table rows"):
            format_markdown(Table([[]]))
        with self.assertRaisesRegex(ParseError, "no csv rows"):
            parse_table(',\n,', 'csv')

    def test_csv_field_limit_matches_reference(self):
        with self.assertRaisesRegex(ParseError, "field larger than field limit"):
            parse_table('A,B\n' + 'x' * 131073 + ',y', 'csv')


if __name__ == '__main__':
    unittest.main()
