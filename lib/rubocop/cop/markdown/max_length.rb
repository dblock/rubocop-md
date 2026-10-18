# frozen_string_literal: true

module RuboCop
  module Cop
    module Markdown
      # Wraps long prose lines, or unwraps paragraphs when Max is false.
      class MaxLength < Base
        extend AutoCorrector

        MSG = "Prose line is too long. [%<length>d/%<max>d]"
        UNWRAP_MSG = "Keep paragraph text on a single source line."
        BLOCK_START = /\A(?:
          [>\#]|[-+*](?:\s|\z)|\d+[.)](?:\s|\z)|`{3}|~{3}|
          (?:[=-]+|(?:[-*_][\t ]*){3,})[\t ]*\z
        )/x.freeze

        def validate_config
          max = cop_config["Max"]
          return if max == false || (max.is_a?(Integer) && max.positive?)

          raise ValidationError, "Markdown/MaxLength: Max must be a positive integer or false."
        end

        private

        def investigate_paragraph(paragraph)
          return unwrap_paragraph(paragraph) if cop_config["Max"] == false

          document.line_numbers(paragraph).each do |number|
            inspect_line(paragraph, number)
          end
        end

        def unwrap_paragraph(paragraph)
          document.soft_breaks(paragraph).each do |number|
            previous = document.line(number)
            following = document.line(number + 1)
            column = document.content_start(paragraph, number + 1)
            next if previous.match?(/<br\b[^>]*>\s*\z/i) ||
                    following[column..].match?(/\A<br\b[^>]*>/i)

            join = document.range(number, previous.rstrip.length, number + 1, column)
            offense = document.range(number + 1, column, number + 1, following.length)
            prose_offense(offense, message: UNWRAP_MSG) do |corrector|
              corrector.replace(document.processed_range(join), " ")
            end
          end
        end

        def inspect_line(paragraph, number)
          text = document.line(number)
          max = cop_config["Max"]
          return if text.length <= max

          first = document.content_start(paragraph, number)
          range = document.range(number, [first, max].max, number, text.length)
          prefix = document.continuation_prefix(paragraph)
          breaks = wrap_points(text, number, first, prefix, document.atomic_ranges(paragraph))
          prose_offense(range, message: format(MSG, length: text.length, max: max)) do |corrector|
            breaks.each do |space|
              replacement = "\n##{RuboCop::Markdown::Preprocess::MARKER}#{prefix}"
              corrector.replace(document.processed_range(space), replacement)
            end
          end
        end

        def wrap_points(text, number, first, prefix, atomic)
          spaces = breakable_spaces(text, number, first, atomic)
          breaks = []
          start = 0
          width = cop_config["Max"]
          while text.length - start > width
            candidates = spaces.select { |space| space.column > start }
            chosen = candidates.reverse.find { |space| space.column - start <= width }
            chosen ||= candidates.first
            break unless chosen

            breaks << chosen
            start = chosen.last_column
            width = cop_config["Max"] - prefix.length
          end
          breaks
        end

        def breakable_spaces(text, number, first, atomic)
          spaces = []
          text.to_enum(:scan, /[ \t]+/).each do
            match = Regexp.last_match
            next if match.begin(0) <= first || match.end(0) == text.length
            next if text[match.end(0)..].match?(BLOCK_START)
            next if text[0...match.begin(0)][/\\+\z/].to_s.length.odd?

            range = document.range(number, match.begin(0), number, match.end(0))
            next if atomic.any? { |protected| protected.overlaps?(range) }

            spaces << range
          end
          spaces
        end
      end
    end
  end
end
