# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

module RuboCop
  module Markdown
    # Retains block source coordinates and inline token ranges before normalization.
    class Parser < Kramdown::Parser::GFM
      # Accept metadata after the language without replacing Kramdown's block parser.
      FENCED_CODEBLOCK_MATCH = /
        ^[ ]{0,3}(([~`])\2{2,})[ \t]*((\S+)[^\n]*?)?[ \t]*\n
        (.*?)^[ ]{0,3}\1\2*[ \t]*\n
      /mx.freeze

      protected

      def parse_codeblock_fenced
        first = @src.pos
        result = super
        return result unless result

        block = @tree.children.last
        indent = @src.string.byteslice(first..)[/\A */].length
        block.options[:code_start_line] = block.options[:location] + 1
        block.options[:code_lines] = block.value.lines(chomp: true).map do |line|
          line.sub(/\A {0,#{indent}}/, "")
        end
        result
      end

      def parse_codeblock
        first = @src.pos
        result = super
        block = @tree.children.last
        raw = @src.string.byteslice(first, @src.pos - first)
        block.options[:code_start_line] = block.options[:location]
        block.options[:code_lines] = raw.lines(chomp: true).map do |line|
          line.sub(Kramdown::Parser::Kramdown::INDENT, "")
        end
        result
      end

      def update_tree(element)
        if element.type == :p && (raw = element.children.find { |child| child.type == :raw_text })
          raw.value.sub!(/\n+\z/, "")
          element.options[:prose_source] = raw.value.dup
          element.options[:prose_atoms] = raw.options[:prose_atoms] = []
          raw.options[:prose_atoms] << [0, 3] if raw.value.match?(/\A\[[ xX]\]/)
        end
        result = super
        element.options.delete(:prose_source) if element.type == :p && html_only?(element)
        result
      end

      def html_only?(paragraph)
        paragraph.children.all? do |child|
          child.type == :html_element || (child.type == :text && child.value.strip.empty?)
        end
      end

      def parse_spans(element, *args, &block)
        previous = @prose_atoms
        @prose_atoms = element.options[:prose_atoms] if element.type == :raw_text
        super
      ensure
        @prose_atoms = previous
      end

      # Task-list rendering replaces source with generated HTML, which we do not need.
      def parse_list
        Kramdown::Parser::Kramdown.instance_method(:parse_list).bind(self).call
      end

      def parse_link
        if @src.pos.zero? && @src.check(/\[[ xX]\]/)
          add_text(@src.scan(/\[[ xX]\]/))
        else
          capture_atom { super }
        end
      end

      %i[parse_codespan parse_autolink parse_span_html].each do |method|
        define_method(method) { capture_atom { super() } }
      end

      def capture_atom
        scanner = @src
        first = scanner.pos
        atoms = @prose_atoms
        result = yield
        return result unless atoms

        atoms << [scanner.string.byteslice(0, first).length,
                  scanner.string.byteslice(0, scanner.pos).length]
        result
      end
    end
  end
end
