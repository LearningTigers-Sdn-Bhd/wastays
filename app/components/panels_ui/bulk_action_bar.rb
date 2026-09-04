# frozen_string_literal: true

module PanelsUI
  # The bar that appears once a list has a selection: how many rows are picked,
  # a way to clear them, and the actions that apply to all of them.
  #
  # It starts hidden and the Stimulus controller named in `controller:` reveals
  # it once a row is picked. The bar makes no assumption about the list above it
  # — a table, a board, or a set of cards all drive it the same way.
  #
  #   render PanelsUI::BulkActionBar.new(noun: "guest") do |bar|
  #     bar.with_action { render PanelsUI::Button.new(...) }
  #   end
  class BulkActionBar < PanelsUI::BaseComponent
    renders_many :actions

    def initialize(noun: "item", controller: "bulk-select", aria_label: "Bulk actions", class: nil, **attributes)
      @noun = noun
      @controller = controller
      @aria_label = aria_label
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    attr_reader :noun

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        role: "region",
        aria: { label: @aria_label },
        class: tw_merge(
          "fixed bottom-[76px] left-1/2 z-overlay hidden w-[calc(100%-2rem)] -translate-x-1/2 " \
          "items-center justify-between gap-3 rounded-lg border border-border bg-card " \
          "px-4 py-3 text-card-foreground shadow-lg " \
          "lg:bottom-6 lg:w-auto lg:justify-start lg:gap-4",
          @class
        ),
        data: data.merge("#{@controller}-target": "banner")
      )
    end

    def count_data
      { "#{@controller}-target": "count" }
    end

    def clear_data
      { action: "#{@controller}#clear" }
    end

    def empty_label
      "0 #{@noun.pluralize} selected"
    end
  end
end
