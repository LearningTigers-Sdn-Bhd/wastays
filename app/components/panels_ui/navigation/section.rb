# frozen_string_literal: true

module PanelsUI
  module Navigation
    # A labelled group of navigation Items — the sidebar's top-level heading ("Home",
    # "Operations", "Finance"). Supersedes the per-portal `NavSection`/`AdminSection`
    # Structs. Purely a container; visibility filtering stays in the helpers.
    #
    #   Navigation::Section.new(label: "Operations", items: [Navigation::Item.new(...)])
    Section = Data.define(:label, :items) do
      def initialize(label:, items: [])
        super(label:, items: Array(items).dup.freeze)
      end

      def items? = items.any?
    end
  end
end
