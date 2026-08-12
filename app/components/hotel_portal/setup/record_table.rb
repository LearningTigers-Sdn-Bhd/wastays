# frozen_string_literal: true

module HotelPortal
  module Setup
    # An editable table of repeating records — draft staff, property taxes and fees.
    #
    # Callers supply the column headers and the field cells for one record. The
    # table owns everything around them: the row wrapper, the leading remove
    # control, the blank row cloned when a record is added, the empty state, and
    # the add-row footer.
    #
    # The leading column is `Remove`, never `Actions`. `Actions` names a trailing
    # column that opens the row action sheet, and a header reading `Actions` above
    # a control that only ever discards the row misdescribes it. See
    # docs/onboarding/DESIGN_DECISIONS.md.
    class RecordTable < PanelsUI::BaseComponent
      CONTROLLER = "record-table"

      class Column < PanelsUI::BaseComponent
        def initialize(label:, required: false, class: nil)
          @label = label
          @required = required
          @class = binding.local_variable_get(:class)
        end

        def call
          tag.th(scope: "col", class: @class) do
            safe_join([ @label, (required_marker if @required) ].compact)
          end
        end

        private

        # Each control carries its own required state for assistive tech. The
        # header repeats it visually because the field's own label — and with it
        # the usual marker — is hidden once the row is laid out as a table row.
        def required_marker
          tag.span("*", class: "panel-record-table__required", title: "Required", aria: { hidden: "true" })
        end
      end

      class Row < PanelsUI::BaseComponent
        # `remove_label` names the record rather than the column: "Remove
        # Breakfast" tells an operator which row the button discards, which the
        # header alone cannot.
        def initialize(remove_label:, persisted: false, confirm: nil, key: nil)
          @remove_label = remove_label
          @persisted = persisted
          @confirm = confirm
          @key = key
        end

        def call
          tag.tr(class: "panel-record-table__row", data: {
            "#{CONTROLLER}_target": "row",
            record_table_persisted: @persisted.to_s,
            record_table_key: @key
          }.compact) do
            safe_join([ remove_cell, content ])
          end
        end

        private

        # `with_content` rather than a block: a block passed from a `call` method
        # writes to no output buffer, so the button would render empty.
        def remove_cell
          tag.td(class: "panel-record-table__control") do
            render PanelsUI::Button.new(
              as: :button,
              variant: :ghost,
              size: :icon_sm,
              icon_only: true,
              aria_label: @remove_label,
              data: {
                action: "#{CONTROLLER}#remove",
                record_table_confirm: @confirm
              }.compact
            ).with_content(helpers.app_icon("trash-2", class: "size-4", aria: { hidden: "true" }))
          end
        end
      end

      renders_many :columns, Column
      renders_many :rows, Row

      # The row the add button clones. It is the same Row as any other, rendered
      # blank, so an added record cannot drift from an existing one. It also
      # anchors the insertion, which is why it is required rather than optional:
      # without it the add button has nothing to add.
      renders_one :blank_row, Row

      def initialize(caption:, add_label:, empty:, spreadsheet: false, actions: false, class: nil)
        @caption = caption
        @add_label = add_label
        @empty = empty
        @spreadsheet = spreadsheet
        @actions = actions
        @class = binding.local_variable_get(:class)
      end

      attr_reader :caption, :add_label, :empty
      def spreadsheet? = @spreadsheet
      def actions? = @actions

      def before_render
        raise ArgumentError, "RecordTable requires at least one column" if columns.empty?
        raise ArgumentError, "RecordTable requires a blank_row to clone" unless blank_row?
      end

      def table_classes = tw_merge("panel-record-table", ("panel-record-table--spreadsheet" if spreadsheet?), @class)

      # The leading control column counts too — a spanning cell that stops short
      # of it leaves the empty state and the add row visibly inset.
      def column_count = columns.size + 1 + (actions? ? 1 : 0)
    end
  end
end
