# frozen_string_literal: true

require "test_helper"

class RuboCop::Markdown::MaxLengthTest < Minitest::Test
  def test_unwraps_paragraphs_with_original_offense_locations
    source = "First paragraph\ncontinues here.\n\nAnother paragraph\ncontinues too.\n"
    corrected, offenses = format_markdown(source, max: false)

    assert_equal "First paragraph continues here.\n\nAnother paragraph continues too.\n", corrected
    assert_equal [2, 5], offenses.map(&:line)
    assert_equal [0, 0], offenses.map(&:column)
    assert_equal "continues here.", offenses.first.location.source_line
  end

  def test_unwraps_nested_lists_blockquotes_and_lazy_continuations
    source = <<~MARKDOWN
      - First item
        continues.
        - Nested item
          continues too.

      > Quoted text
      > continues.
      >
      > - Quoted list
      >   continues.

      - Lazy item
      continuation.
    MARKDOWN
    expected = <<~MARKDOWN
      - First item continues.
        - Nested item continues too.

      > Quoted text continues.
      >
      > - Quoted list continues.

      - Lazy item continuation.
    MARKDOWN

    assert_format expected, source, max: false
  end

  def test_preserves_hard_breaks_and_html_breaks
    source = "First  \nsecond\nthird\\\nfourth\nfifth<br>\nsixth\n<br />\nseventh\n"
    expected = "First  \nsecond third\\\nfourth fifth<br>\nsixth\n<br />\nseventh\n"

    assert_format expected, source, max: false
  end

  def test_ignores_non_paragraph_blocks
    source = <<~MARKDOWN
      # Heading

      Setext heading
      --------------

      ```text
      fenced
      code
      ```

      ~~~text
      tilde
      fence
      ~~~

          indented
          code

      <div>
      HTML
      block
      </div>

      | First | Second |
      | ----- | ------ |
      | Cell  | Cell   |
    MARKDOWN

    assert_format source, source, max: false
    assert_format source, source, max: 10
  end

  def test_preserves_multiline_inline_code
    source = "Some `inline\ncode` here\ncontinues.\n"

    assert_format "Some `inline\ncode` here continues.\n", source, max: false
    assert_format "Some\n`inline\ncode`\nhere\ncontinues.\n", source, max: 5
  end

  def test_parser_warnings_are_not_written_to_stderr
    _, warnings = capture_io do
      format_markdown("[label][missing]\n", max: false, file: File.join(Dir.pwd, "test", "guide.md"))
    end

    assert_empty warnings
  end

  def test_ignores_html_only_paragraphs_but_formats_mixed_prose
    source = "<a href=\"https://example.com\">Follow me</a>\n<script>example();</script>\n"
    [false, 10].each do |max|
      corrected, offenses = format_markdown(source, max: max)

      assert_equal source, corrected
      assert_empty offenses
    end
    assert_format "Text <em>emphasis</em> continues.\n",
                  "Text <em>emphasis</em>\ncontinues.\n", max: false
  end

  def test_wraps_at_the_limit_and_reports_original_columns
    source = "One two three four five six seven.\n"
    corrected, offenses = format_markdown(source, max: 18)

    assert_equal "One two three four\nfive six seven.\n", corrected
    assert_equal 18, offenses.first.column
    assert_equal source.chomp, offenses.first.location.source_line
    assert_includes offenses.first.message, "[34/18]"
    assert(corrected.lines.all? { |line| line.chomp.length <= 18 })
  end

  def test_wraps_lists_and_blockquotes_with_continuation_prefixes
    source = "- One two three four five six seven.\n\n> 1. One two three four five six seven.\n"
    expected = "- One two three\n  four five six\n  seven.\n\n> 1. One two\n>    three four\n>    five six\n>    seven.\n"

    assert_format expected, source, max: 16
  end

  def test_does_not_split_links_code_or_html_tags
    source = "Before [a long label](https://example.com/path) after `some long code` end.\n"
    expected = "Before\n[a long label](https://example.com/path)\nafter\n`some long code`\nend.\n"

    assert_format expected, source, max: 20
    assert_format "<span title=\"long attribute value\"> text</span>\n",
                  "<span title=\"long attribute value\"> text</span>\n", max: 20
  end

  def test_unbreakable_words_are_reported_without_corrections
    source = "averylongwordwithoutspaces\n"
    corrected, offenses = format_markdown(source, max: 10)

    assert_equal source, corrected
    assert_equal 1, offenses.length
    refute offenses.first.correctable?
  end

  def test_does_not_introduce_new_markdown_blocks
    source = "First words # not a heading and more words.\n"
    corrected, = format_markdown(source, max: 12)

    refute_match(/^# /, corrected)
    assert_includes corrected, "words #"
  end

  def test_unicode_offsets_and_no_final_newline
    corrected, offenses = format_markdown("Caf\u00e9 prose\ncontinues", max: false)

    assert_equal "Caf\u00e9 prose continues", corrected
    assert_equal 0, offenses.first.column
    assert_format "Caf\u00e9 prose\nhas words.", "Caf\u00e9 prose has words.", max: 12
  end

  def test_task_lists_and_tab_indentation
    assert_format "- [ ] First item continues.\n", "- [ ] First item\n  continues.\n", max: false
    assert_format "-\tFirst item continues.\n", "-\tFirst item\n\tcontinues.\n", max: false
    assert_format "- [x] One two\n  three four\n  five.\n",
                  "- [x] One two three four five.\n", max: 14
  end

  def test_preserves_multiline_links_and_reference_links
    source = "Some [long\nlink](https://example.com) text\ncontinues.\n"
    assert_format "Some [long\nlink](https://example.com) text continues.\n", source, max: false
    assert_format "[long label][ref]\nafter text.\n\n[ref]: https://example.com\n",
                  "[long label][ref] after text.\n\n[ref]: https://example.com\n", max: 18
  end

  def test_wrapping_does_not_introduce_hard_breaks_or_setext_headings
    ["First words --", "First words _ _ _", "First words\\ after more words"].each do |source|
      corrected, = format_markdown("#{source}\n", max: 12)
      refute_match(/\\\n/, corrected)
      refute_match(/^(?:--|_ _ _)$/, corrected)
    end
  end

  def test_reports_prose_even_when_ruby_is_invalid
    source = "First line\nsecond line\n\n```ruby\ndef broken(\n```\n"
    corrected, offenses = format_markdown(source, max: false)

    assert_equal source, corrected
    assert_equal [2], offenses.map(&:line)
    refute offenses.first.correctable?
  end

  def test_ignores_ruby_files
    source = "# A long Ruby comment which is not Markdown prose.\n"

    assert_format source, source, max: 10, file: "test.rb"
  end

  def test_inline_disabling
    source = <<~MARKDOWN
      <span style="display:none;"># rubocop:disable Markdown/MaxLength </span>

      Keep this
      wrapped.

      <span style="display:none;"># rubocop:enable Markdown/MaxLength </span>

      Join this
      paragraph.
    MARKDOWN
    expected = source.sub("Join this\nparagraph.", "Join this paragraph.")

    assert_format expected, source, max: false
  end

  def test_rejects_invalid_limits
    [nil, 0, -1, "80", true].each do |max|
      error = assert_raises(RuboCop::ValidationError) { prose_cop(max) }
      assert_includes error.message, "positive integer or false"
    end
  end

  def test_html_comment_disabling
    source = "<!-- # rubocop:disable Markdown/MaxLength -->\n\nKeep this\nwrapped.\n"

    assert_format source, source, max: false
  end

  private

  def prose_cop(max)
    config = RuboCop::ConfigLoader.merge_with_default(
      RuboCop::Config.new(
        "Markdown/MaxLength" => { "Enabled" => true, "Max" => max }
      ),
      File.join(__dir__, ".rubocop.yml")
    )
    cop = RuboCop::Cop::Markdown::MaxLength.new(config, autocorrect: true)
    cop.validate_config
    cop
  end

  def assert_format(expected, source, **options)
    corrected, = format_markdown(source, **options)
    assert_equal expected, corrected
    repeated, = format_markdown(corrected, **options)
    assert_equal corrected, repeated
  end

  def format_markdown(source, max:, file: "test.md")
    first_offenses = nil
    20.times do
      cop = prose_cop(max)
      processed = RuboCop::ProcessedSource.new(source, RuboCop::TargetRuby::DEFAULT_VERSION, file)
      processed.config = cop.config
      processed.registry = RuboCop::Cop::Registry.new([cop.class])
      report = RuboCop::Cop::Commissioner.new([cop], [], raise_error: true).investigate(processed)
      first_offenses ||= report.offenses
      corrector = report.correctors.compact.first
      return [source, first_offenses] unless corrector && !corrector.empty?

      source = corrector.rewrite
    end
    flunk "Prose autocorrection did not converge"
  end
end
