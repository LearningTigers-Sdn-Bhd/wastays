# frozen_string_literal: true

module PanelsUI
  class PageHeader < PanelsUI::BaseComponent
    renders_one :caption
    renders_one :actions

    TITLE_TAGS = %i[h1 h2 h3 h4 h5 h6].freeze

    def initialize(title:, description: nil, title_as: :h1, class: nil, **attributes)
      raise ArgumentError, "Page headers require a title" if title.blank?

      @title = title
      @description = description
      @title_as = TITLE_TAGS.include?(title_as) ? title_as : :h1
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def root_attributes
      @attributes.merge(class: tw_merge("panel-page-header", @class))
    end

    def description_popover_id
      "page-header-description-#{object_id}"
    end
  end
end
