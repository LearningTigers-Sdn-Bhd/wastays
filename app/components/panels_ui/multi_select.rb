# frozen_string_literal: true

module PanelsUI
  # A searchable multi-select, progressively enhanced by Tom Select.
  #
  # Derived from Combobox: it renders the same structure over a native
  # <select multiple>, which stays the source of truth for validation and form
  # submission (posting an array). The only differences are the Stimulus
  # controller it wires up, the root id/class, and the multiple flag — all of
  # which are override hooks on Combobox.
  class MultiSelect < PanelsUI::Combobox
    # max_visible_items caps how many pills the trigger shows before collapsing the
    # remainder into a "+N more" badge; the full selection stays managable in the
    # dropdown's selected-badges panel.
    def initialize(max_visible_items: 3, all_selected_text: "All options selected", **kwargs)
      @max_visible_items = max_visible_items
      @all_selected_text = all_selected_text
      super(**kwargs)
    end

    def placeholder_text = @placeholder || @prompt || "Search and select…"

    def stimulus_identifier = "panels-ui--multi-select"
    def root_id = "#{native_id}-multi-select"
    # Keep panel-combobox so every combobox style applies; panel-multi-select adds
    # the multi-item pill overrides on top.
    def root_class = "panel-combobox panel-multi-select"
    def native_multiple? = true

    def extra_root_data
      {
        "#{stimulus_identifier}-max-visible-items-value" => @max_visible_items,
        # Shown in the empty menu when every option is already selected.
        "#{stimulus_identifier}-all-selected-text-value" => @all_selected_text
      }
    end
  end
end
