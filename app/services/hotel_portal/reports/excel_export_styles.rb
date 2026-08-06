# frozen_string_literal: true

module HotelPortal
  module Reports
    module ExcelExportStyles
      COLORS = {
        ink: "18332F", primary: "205B4E", primary_light: "E7F1ED",
        muted: "667772", border: "D9E4DF", stripe: "F5F8F7",
        white: "FFFFFF", negative: "A33636"
      }.freeze

      FONT_SIZES = {
        title: 18, kpi_value: 13, section: 12, body: 11
      }.freeze
    end
  end
end
