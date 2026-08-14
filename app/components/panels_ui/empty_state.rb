# frozen_string_literal: true

module PanelsUI
  # A region that has nothing in it yet: what is missing, why it matters, and
  # the one action that fixes it.
  #
  # The pattern started inside RecordTable, which still renders this component
  # for its own empty row. Anything that is not a table — an album, a list, a
  # panel — renders it directly rather than restating the same markup.
  class EmptyState < PanelsUI::BaseComponent
    # The action belongs in the state itself: someone looking at an empty region
    # should never have to go hunting for the control that fills it.
    renders_one :action

    def initialize(title:, description: nil, icon: "inbox", class: nil, **attributes)
      @title = title
      @description = description
      @icon = icon
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    attr_reader :title, :description, :icon

    def root_attributes
      @attributes.merge(class: tw_merge("panel-empty-state", @class))
    end
  end
end
