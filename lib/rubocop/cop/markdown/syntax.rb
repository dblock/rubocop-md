# frozen_string_literal: true

module RuboCop
  module Cop
    module Markdown
      # Reports Markdown parser diagnostics through RuboCop's standard formatters.
      class Syntax < Base
        private

        def investigate_document
          document.warnings.group_by { |warning| warning_line(warning) }.each do |number, warnings|
            range = document.range(number, 0, number, document.line(number).length)
            prose_offense(range, message: warnings.join("; "))
          end
        end

        def warning_line(warning)
          number = warning.scan(/\bline (\d+)\b/).last&.first&.to_i
          number&.between?(1, document.buffer.last_line) ? number : 1
        end
      end
    end
  end
end
