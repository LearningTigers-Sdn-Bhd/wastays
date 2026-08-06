# frozen_string_literal: true

module PanelsUI
  # Renders a breadcrumb trail from the typed `parts` array that the portal
  # navigation helpers already produce (`*_breadcrumb_parts`), so it is a drop-in
  # replacement for `shared/navigation/_breadcrumb_bar` — no helper or controller
  # changes required.
  #
  # Each part is a Hash: `{ type:, label:, path:, siblings:, tab_label:,
  # subtab_label:, tabs_id:, tabs_ids:, hidden: }`. `type` is one of
  # :section, :menu_group, :menu,
  # :breakdown (or nil for appended parts). A part with `siblings:` renders a
  # sibling-menu dropdown; `tab_label:`/`subtab_label:` mark live labels. Optional
  # `tabs_id:`/`tabs_ids:` scope generic PanelsUI::Tabs change events to this
  # breadcrumb instance.
  #
  # ── Tab integration contract ──────────────────────────────────────────────────
  # PanelsUI::Tabs emits a generic window event. The breadcrumb listens only when a
  # live-label part names the relevant tab group, keeping both components independent.
  class Breadcrumb < PanelsUI::BaseComponent
    def initialize(parts:, id: nil, class: nil)
      @parts = Array(parts)
      @id = id || "breadcrumb-#{object_id}"
      @class = binding.local_variable_get(:class)
    end

    def parts? = @parts.any?
    def render? = parts?

    def tab_source_id
      parts.find { |part| part[:tab_label] }&.dig(:tabs_id)
    end

    def subtab_source_ids
      part = parts.find { |candidate| candidate[:subtab_label] }
      Array(part&.fetch(:tabs_ids, nil) || part&.fetch(:tabs_id, nil)).map(&:to_s)
    end

    def listens_for_tabs? = tab_source_id.present? || subtab_source_ids.any?

    private

    attr_reader :parts

    def last?(index) = index == parts.size - 1

    def menu_id(index) = "#{@id}-menu-#{index}"
    def trigger_id(index) = "#{@id}-trigger-#{index}"

    # Classify a part into a render kind. Mirrors the branching the old
    # `_breadcrumb_bar` partial did inline, kept here so the template stays flat.
    def kind_for(part, index)
      case part[:type]
      when :section, :menu_group
        :static
      when :menu, :breakdown
        return :dropdown if part[:siblings].present?
        return :link if part[:path].present? && !last?(index)

        :current
      else
        return :subtab_current if part[:subtab_label]
        return :tab_current if part[:tab_label]
        return :dropdown if part[:siblings].present?
        return :current if last?(index)

        part[:path].present? ? :link : :static
      end
    end
  end
end
