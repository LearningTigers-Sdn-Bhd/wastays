# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      class ExcelTheme
        COLORS = ExcelExportStyles::COLORS
        FONT_SIZES = ExcelExportStyles::FONT_SIZES

        def initialize(workbook)
          @styles = build_styles(workbook.styles)
        end

        def fetch(name)
          @styles.fetch(name)
        end

        private

        def build_styles(styles)
          base = {
            fg_color: COLORS[:ink],
            sz: FONT_SIZES[:body],
            alignment: { vertical: :top, wrap_text: true }
          }
          bottom_border = { style: :thin, color: COLORS[:border], edges: [ :bottom ] }

          {
            title: styles.add_style(
              bg_color: COLORS[:primary], fg_color: COLORS[:white], b: true, sz: FONT_SIZES[:title],
              alignment: { vertical: :center }
            ),
            metadata: styles.add_style(
              fg_color: COLORS[:muted], sz: FONT_SIZES[:body],
              alignment: { vertical: :center, wrap_text: true }
            ),
            section: styles.add_style(
              bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:section],
              border: bottom_border, alignment: { vertical: :center }
            ),
            header: styles.add_style(
              bg_color: COLORS[:ink], fg_color: COLORS[:white], b: true, sz: FONT_SIZES[:body],
              alignment: { vertical: :center, wrap_text: true }
            ),
            body: styles.add_style(**base, border: bottom_border),
            body_alt: styles.add_style(**base, bg_color: COLORS[:stripe], border: bottom_border),
            date: typed_style(styles, base, bottom_border, "yyyy-mm-dd"),
            date_alt: typed_style(styles, base, bottom_border, "yyyy-mm-dd", background: COLORS[:stripe]),
            datetime: typed_style(styles, base, bottom_border, "yyyy-mm-dd hh:mm"),
            datetime_alt: typed_style(styles, base, bottom_border, "yyyy-mm-dd hh:mm", background: COLORS[:stripe]),
            integer: typed_style(styles, base, bottom_border, "#,##0"),
            integer_alt: typed_style(styles, base, bottom_border, "#,##0", background: COLORS[:stripe]),
            percentage: typed_style(styles, base, bottom_border, "0.00%"),
            percentage_alt: typed_style(styles, base, bottom_border, "0.00%", background: COLORS[:stripe]),
            money: typed_style(styles, base, bottom_border, "#,##0.00;[Red]-#,##0.00"),
            money_alt: typed_style(styles, base, bottom_border, "#,##0.00;[Red]-#,##0.00", background: COLORS[:stripe]),
            kpi_label: styles.add_style(
              fg_color: COLORS[:muted], b: true, sz: FONT_SIZES[:body],
              border: bottom_border, alignment: { vertical: :center }
            ),
            kpi_integer: styles.add_style(
              fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:kpi_value], format_code: "#,##0",
              border: bottom_border, alignment: { horizontal: :right, vertical: :center }
            ),
            kpi_money: styles.add_style(
              fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:kpi_value],
              format_code: "#,##0.00;[Red]-#,##0.00", border: bottom_border,
              alignment: { horizontal: :right, vertical: :center }
            ),
            currency: styles.add_style(
              fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:body], border: bottom_border,
              alignment: { horizontal: :center, vertical: :center }
            ),
            total_label: styles.add_style(
              bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:body],
              border: { style: :thin, color: COLORS[:primary], edges: [ :top ] }
            ),
            total_date: total_typed_style(styles, "yyyy-mm-dd"),
            total_datetime: total_typed_style(styles, "yyyy-mm-dd hh:mm"),
            total_integer: total_typed_style(styles, "#,##0"),
            total_percentage: total_typed_style(styles, "0.00%"),
            total_money: total_typed_style(styles, "#,##0.00;[Red]-#,##0.00"),
            empty: styles.add_style(
              fg_color: COLORS[:muted], sz: FONT_SIZES[:body], i: true,
              alignment: { vertical: :center, wrap_text: true }
            )
          }
        end

        def typed_style(styles, base, border, format_code, background: nil)
          options = base.merge(
            format_code: format_code,
            border: border,
            alignment: { horizontal: :right, vertical: :top, wrap_text: true }
          )
          options[:bg_color] = background if background
          styles.add_style(**options)
        end

        def total_typed_style(styles, format_code)
          styles.add_style(
            bg_color: COLORS[:primary_light], fg_color: COLORS[:ink], b: true, sz: FONT_SIZES[:body],
            format_code: format_code,
            border: { style: :thin, color: COLORS[:primary], edges: [ :top ] },
            alignment: { horizontal: :right }
          )
        end
      end
    end
  end
end
