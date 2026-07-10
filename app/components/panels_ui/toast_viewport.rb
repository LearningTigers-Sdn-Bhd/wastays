# frozen_string_literal: true

module PanelsUI
  # Persistent RailsBlocks-style toast host. Render this once per layout near
  # the end of <body>; it is both the Stimulus controller root and the stable
  # Turbo Stream target used by server-triggered notifications.
  class ToastViewport < PanelsUI::BaseComponent
    PLACEMENTS = %i[top_left top_center top_right bottom_left bottom_center bottom_right].freeze

    def initialize(id: "toast-viewport", placement: :top_right, layout: :default, auto_dismiss_duration: 4000, limit: 3, gap: 14, class: nil)
      @id = id
      @placement = PLACEMENTS.include?(placement) ? placement : :top_right
      @layout = %i[default expanded].include?(layout) ? layout : :default
      @auto_dismiss_duration = auto_dismiss_duration
      @limit = limit
      @gap = gap
      @class = binding.local_variable_get(:class)
    end

    def placement_value = @placement.to_s.tr("_", "-")
    def layout_value = @layout.to_s
  end
end
