# frozen_string_literal: true

module SystemDesigns
  # Registry of PanelsUI showcase sections. Extracted from the view so the
  # controller can filter it down to a single component via `?only=` — system
  # specs use this to avoid booting all ~40 live components on every visit.
  module Previews
    ALL = [
      { name: "Accordion", partial: "accordion_preview" },
      { name: "Alert", partial: "alert_preview" },
      { name: "Alert dialog", partial: "alert_dialog_preview" },
      { name: "Avatar", partial: "avatar_preview" },
      { name: "Badge", partial: "badge_preview" },
      { name: "Banner", partial: "banner_preview" },
      { name: "Breadcrumb", partial: "breadcrumb_preview" },
      { name: "Button", partial: "button_preview" },
      { name: "Button group", partial: "button_group_preview" },
      { name: "Card", partial: "card_preview" },
      { name: "Checkbox", partial: "checkbox_preview" },
      { name: "Collapsible", partial: "collapsible_preview" },
      { name: "Combobox", partial: "combobox_preview" },
      { name: "Date picker", partial: "date_picker_preview" },
      { name: "Date time picker", partial: "date_time_picker_preview" },
      { name: "Dialog", partial: "dialog_preview" },
      { name: "Dropdown menu", partial: "dropdown_menu_preview" },
      { name: "File upload", partial: "file_upload_preview" },
      { name: "Form fields", partial: "form_fields_preview" },
      { name: "Form submission", partial: "form_submission_preview" },
      { name: "Keyboard shortcut", partial: "kbd_preview" },
      { name: "Loading states", partial: "loading_preview" },
      { name: "Metric card", partial: "metric_card_preview" },
      { name: "Multi-select", partial: "multi_select_preview" },
      { name: "Native select", partial: "native_select_preview" },
      { name: "Navbar", partial: "navbar_preview" },
      { name: "Page header", partial: "page_header_preview" },
      { name: "Pagination", partial: "pagination_preview" },
      { name: "Popover", partial: "popover_preview" },
      { name: "Radio", partial: "radio_preview" },
      { name: "Scroll area", partial: "scroll_area_preview" },
      { name: "Select menu", partial: "select_menu_preview" },
      { name: "Separator", partial: "separator_preview" },
      { name: "Sheet", partial: "sheet_preview" },
      { name: "Sidebar", partial: "sidebar_preview" },
      { name: "Switch", partial: "switch_preview" },
      { name: "Table", partial: "table_preview" },
      { name: "Tabs", partial: "tabs_preview" },
      { name: "Time picker", partial: "time_picker_preview" },
      { name: "Timeline", partial: "timeline_preview" },
      { name: "Toast", partial: "toast_preview" },
      { name: "Toggle", partial: "toggle_preview" },
      { name: "Toggle group", partial: "toggle_group_preview" },
      { name: "Tooltip", partial: "tooltip_preview" }
    ].map { |preview| preview.merge(anchor: preview[:partial].tr("_", "-")) }.freeze
  end
end
