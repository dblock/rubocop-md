# frozen_string_literal: true

require_relative "parser"

module RuboCop
  module Markdown
    # Original Markdown, its parsed blocks, and coordinates in the Ruby source buffer.
    class Document
      # A deliberate prose edit mapped into the shared Ruby correction buffer.
      class ProseRange < ::Parser::Source::Range; end

      attr_reader :buffer, :code_prefixes
      attr_accessor :processed_buffer

      def initialize(source, path, ignore_front_matter: true)
        @buffer = ::Parser::Source::Buffer.new(path, source: source)
        @code_prefixes = {}
        @ignore_front_matter = ignore_front_matter
      end

      def code_blocks
        return enum_for(__method__) unless block_given?

        walk(root) { |node| yield node if node.type == :codeblock }
      end

      def code_lines(block)
        first = block.options.fetch(:code_start_line)
        block.options.fetch(:code_lines).each_with_index.to_h do |text, index|
          number = first + index
          original = line(number)
          unless original.end_with?(text)
            raise "Cannot map Markdown code block source on line #{number}"
          end

          code_prefixes[number] = original.delete_suffix(text)
          [number, text]
        end
      end

      def corrected_source(corrector)
        rewriter = ::Parser::Source::TreeRewriter.new(buffer)
        corrector.as_replacements.each do |range, replacement|
          text = replacement.dup
          Preprocess.restore!(text)
          prefix = code_prefixes[range.first_line]
          text = text.gsub("\n", "\n#{prefix}") if prefix
          rewriter.replace(original_range(range), text)
        end
        rewriter.process
      end

      def ignore_front_matter=(value)
        return if @ignore_front_matter == value

        @ignore_front_matter = value
        @parsed = nil
      end

      def paragraphs
        return enum_for(__method__) unless block_given?

        walk(root) { |node| yield node if node.type == :p && node.options[:prose_source] }
      end

      def warnings
        parsed.last
      end

      def line(number)
        buffer.source_line(number)
      end

      def original_range(processed)
        return processed if processed.source_buffer.equal?(buffer)

        range(
          processed.first_line, [processed.column - line_offset(processed.first_line), 0].max,
          processed.last_line, [processed.last_column - line_offset(processed.last_line), 0].max
        )
      end

      def content_start(paragraph, number)
        relative = number - paragraph.options[:location]
        text = source_lines(paragraph).fetch(relative)
        line(number).rindex(text) ||
          raise("Cannot map Markdown paragraph source on line #{number}")
      end

      def line_numbers(paragraph)
        first = paragraph.options[:location]
        first..(first + source_lines(paragraph).length - 1)
      end

      def continuation_prefix(paragraph)
        number = paragraph.options[:location]
        prefix = line(number)[0...content_start(paragraph, number)]
        prefix.gsub(/[-+*]|\d+[.)]/) { |marker| " " * marker.length }
      end

      def soft_breaks(paragraph)
        return enum_for(__method__, paragraph) unless block_given?

        numbers = line_numbers(paragraph)
        (numbers.first...numbers.last).each do |number|
          text = line(number)
          next if text.end_with?("  ") || text[/\\+\z/].to_s.length.odd?

          join = range(number, text.rstrip.length, number + 1, content_start(paragraph, number + 1))
          next if atomic_ranges(paragraph).any? { |atom| atom.overlaps?(join) }

          yield number
        end
      end

      def atomic_ranges(paragraph)
        return paragraph.options[:original_ranges] if paragraph.options[:original_ranges]

        source = paragraph.options[:prose_source]
        inline = ::Parser::Source::Buffer.new("(paragraph)", source: source)
        paragraph.options[:original_ranges] ||= paragraph.options[:prose_atoms].map do |first, last|
          start_line, start_column = inline.decompose_position(first)
          end_line, end_column = inline.decompose_position(last)
          first_line = paragraph.options[:location] + start_line - 1
          last_line = paragraph.options[:location] + end_line - 1
          range(
            first_line, content_start(paragraph, first_line) + start_column,
            last_line, content_start(paragraph, last_line) + end_column
          )
        end
      end

      def range(first_line, first_column, last_line = first_line, last_column = first_column)
        ::Parser::Source::Range.new(
          buffer,
          buffer.line_range(first_line).begin_pos + first_column,
          buffer.line_range(last_line).begin_pos + last_column
        )
      end

      def processed_range(original)
        return original if original.source_buffer.equal?(processed_buffer)

        ProseRange.new(
          processed_buffer,
          processed_position(original.first_line, original.column),
          processed_position(original.last_line, original.last_column)
        )
      end

      private

      def source_lines(paragraph)
        paragraph.options[:source_lines] ||= paragraph.options[:prose_source].split("\n", -1)
      end

      def root
        parsed.first
      end

      def parsed
        @parsed ||= Markdown::Parser.parse(
          buffer.source, hard_wrap: false, gfm_quirks: %i[paragraph_end no_auto_typographic],
                         ignore_front_matter: @ignore_front_matter
        )
      end

      def walk(node, &block)
        yield node
        node.children.each { |child| walk(child, &block) }
      end

      def processed_position(number, column)
        processed_buffer.line_range(number).begin_pos + line_offset(number) + column
      end

      def line_offset(number)
        processed_buffer.source_line(number).length - line(number).length
      end
    end
  end
end
