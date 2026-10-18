# frozen_string_literal: true

module RuboCop
  module Cop
    module Markdown
      # Shared source mapping for cops inspecting prose rather than Ruby snippets.
      class Base < RuboCop::Cop::Base
        exclude_from_registry

        def on_new_investigation
          super
          return unless document

          investigate_document
        end

        def on_other_file
          super
          on_new_investigation
        end

        private

        def document
          processed_source.markdown_document
        end

        def investigate_document
          document.paragraphs.each { |paragraph| investigate_paragraph(paragraph) }
        end

        # Corrections share the Ruby buffer; only reported locations use the original.
        def range_for_original(range)
          document.original_range(range)
        end

        def prose_offense(range, **options, &block)
          block = nil unless processed_source.valid_syntax?
          add_offense(document.processed_range(range), **options, &block)
        end
      end
    end
  end
end
