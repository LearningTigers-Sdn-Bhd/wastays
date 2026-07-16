# frozen_string_literal: true

module PanelsUI
  # Global command palette (⌘K / Ctrl+K) built on the native <dialog> primitive.
  #
  # Structure is two nested Stimulus controllers:
  #   • panels-ui--command-palette (this root) — owns the trigger, the global
  #     ⌘K / "/" shortcut, the debounced async search, the listbox keyboard
  #     navigation, and navigate-on-select (Turbo.visit).
  #   • panels-ui--dialog (the inner <dialog>) — reused verbatim for scroll-lock,
  #     backdrop-dismiss, Escape/cancel and top-layer. Native <dialog> also gives
  #     focus-trapping for free, so the palette controller never touches focus
  #     containment.
  #
  # The palette does NOT bind to a form field — it is a stateless search-and-
  # navigate surface, which is why it is not a Combobox (that wraps a <select>).
  #
  #   <%= render PanelsUI::CommandPalette.new(
  #         endpoint: hotel_global_search_index_path(current_hotel),
  #         placeholder: "Search dashboard pages…") %>
  #
  # The endpoint must return JSON of the shape:
  #   { "results": [{ "title":, "subtitle":, "url":, "group": }, …],
  #     "quick_actions": [{ "group":, "label":, "url": }, …] }
  class CommandPalette < PanelsUI::BaseComponent
    def initialize(endpoint:, placeholder: "Search pages and records…",
                   label: "Open global search", id: nil, class: nil)
      @endpoint    = endpoint
      @placeholder = placeholder
      @label       = label
      @id          = id || "command-palette-#{SecureRandom.hex(4)}"
      @class       = binding.local_variable_get(:class)
    end

    attr_reader :endpoint, :placeholder, :label

    def dialog_id   = "#{@id}-dialog"
    def input_id    = "#{@id}-input"
    def listbox_id  = "#{@id}-listbox"
    def root_class  = tw_merge("panel-command-palette", @class)
  end
end
