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
        # `soft_remove` keeps a removed row in the DOM, hidden and marked for
        # destruction, rather than discarding it. A row whose identity comes from
        # elsewhere — a room category the operator cannot retype — has to survive
        # its own removal so something can put it back.
        def initialize(remove_label:, persisted: false, confirm: nil, key: nil, removable: true,
                       remove_disabled_reason: nil, soft_remove: false, hidden: false, table: nil)
          @remove_label = remove_label
          @persisted = persisted
          @confirm = confirm
          @key = key
          @removable = removable
          @remove_disabled_reason = remove_disabled_reason
          @soft_remove = soft_remove
          @hidden = hidden
          @table = table
        end

        def call
          tag.tr(class: "panel-record-table__row", hidden: @hidden, data: {
            "#{CONTROLLER}_target": "row",
            record_table_persisted: @persisted.to_s,
            record_table_soft: (@soft_remove ? "true" : nil),
            record_table_key: @key
          }.compact) do
            safe_join([ remove_cell, content ].compact)
          end
        end

        private

        # Whether the column exists is the table's decision, not the row's. A row
        # that opts out of removal still has to hold the cell open or every cell
        # after it lands under the wrong header.
        def control_column?
          return @table.removable? if @table

          @removable || @remove_disabled_reason.present?
        end

        # `with_content` rather than a block: a block passed from a `call` method
        # writes to no output buffer, so the button would render empty.
        def remove_cell
          return unless control_column?
          return tag.td(class: "panel-record-table__control") unless @removable || @remove_disabled_reason.present?

          tag.td(class: "panel-record-table__control") do
            render PanelsUI::Button.new(
              as: :button,
              variant: :ghost,
              size: :icon_sm,
              icon_only: true,
              aria_label: @remove_label,
              disabled: !@removable,
              title: @remove_disabled_reason,
              data: {
                action: "#{CONTROLLER}#remove",
                record_table_confirm: @confirm
              }.compact
            ).with_content(helpers.app_icon("trash-2", class: "size-4", aria: { hidden: "true" }))
          end
        end
      end

      # A heading row that opens a run of records — one rate plan above the room
      # rows priced under it. It spans the record columns rather than filling
      # them: the fields belong to the records, and the group only names them
      # and carries the controls that act on the run as a whole.
      class GroupRow < PanelsUI::BaseComponent
        def initialize(table:, key:, locked: false, locked_reason: nil,
                       remove_label: nil, persisted: false, confirm: nil, add_label: nil)
          @table = table
          @key = key
          @locked = locked
          @locked_reason = locked_reason
          @remove_label = remove_label
          @persisted = persisted
          @confirm = confirm
          @add_label = add_label
        end

        def call
          tag.tr(class: "panel-record-table__group", data: {
            "#{CONTROLLER}_target": "group",
            record_table_key: @key,
            record_table_persisted: @persisted.to_s
          }.compact) do
            safe_join([ control_cell, label_cell ].compact)
          end
        end

        private

        def locked? = @locked

        # The control column is held open even for a locked group so the group
        # heading and the records below it stay on the same grid.
        def control_cell
          return unless @table.removable?

          tag.td(class: "panel-record-table__control") do
            locked? ? lock_marker : remove_button
          end
        end

        def lock_marker
          tag.span(
            helpers.app_icon("lock", class: "size-4", aria: { hidden: "true" }),
            class: "text-muted-foreground",
            title: @locked_reason,
            aria: { label: @locked_reason.presence || "Protected" }
          )
        end

        def remove_button
          render PanelsUI::Button.new(
            as: :button, variant: :ghost, size: :icon_sm, icon_only: true,
            aria_label: @remove_label,
            data: {
              action: "#{CONTROLLER}#remove",
              record_table_confirm: @confirm
            }.compact
          ).with_content(helpers.app_icon("trash-2", class: "size-4", aria: { hidden: "true" }))
        end

        def label_cell
          tag.td(colspan: @table.group_colspan, class: "panel-record-table__group-label") do
            tag.div(class: "panel-record-table__group-content") do
              safe_join([ content, add_button ].compact)
            end
          end
        end

        # The add button belongs to the group, not the table footer: with several
        # groups stacked in one table a single footer button has no way to say
        # which run of records it extends.
        def add_button
          return if @add_label.blank?

          render PanelsUI::Button.new(
            as: :button, variant: :ghost, size: :xs,
            data: {
              action: "#{CONTROLLER}#add",
              "#{CONTROLLER}_group_param": @key
            }
          ).with_content(safe_join([
            helpers.app_icon("plus", class: "size-4", aria: { hidden: "true" }),
            tag.span(@add_label)
          ]))
        end
      end

      # The clone source for one group, placed after that group's records so it
      # anchors insertion the same way the table-level blank row does.
      class TemplateRow < PanelsUI::BaseComponent
        # `group` names the run this template extends; `key` inside row_options
        # is the cloned row's own placeholder, and the two are not the same.
        def initialize(group:, table: nil, **row_options)
          @group = group
          @table = table
          @row_options = row_options
        end

        def call
          tag.template(data: { "#{CONTROLLER}_target": "template", record_table_group: @group }) do
            render(Row.new(table: @table, **@row_options).with_content(content))
          end
        end
      end

      renders_many :columns, Column

      # One ordered collection so a group heading, its records and its clone
      # template keep the sequence the caller wrote them in. Separate slots would
      # render as separate blocks and lose it.
      renders_many :rows, types: {
        record: ->(**args) { Row.new(table: self, **args) },
        group: ->(**args) { GroupRow.new(table: self, **args) },
        template: ->(**args) { TemplateRow.new(table: self, **args) }
      }

      # The flat tables — staff, taxes, extra charges — predate groups and keep
      # calling `with_row`.
      def with_row(...)
        @record_row_count = @record_row_count.to_i + 1
        with_row_record(...)
      end

      def with_group_row(...) = with_row_group(...)
      def with_group_template_row(...) = with_row_template(...)

      # The row the add button clones. It is the same Row as any other, rendered
      # blank, so an added record cannot drift from an existing one. It also
      # anchors the insertion, which is why it is required rather than optional:
      # without it the add button has nothing to add.
      renders_one :blank_row, Row

      def initialize(caption:, add_label: nil, empty:, spreadsheet: false, actions: false,
                     removable: true, addable: true, footer_message: nil, class: nil)
        @caption = caption
        @add_label = add_label
        @empty = empty
        @spreadsheet = spreadsheet
        @actions = actions
        @removable = removable
        @addable = addable
        @footer_message = footer_message
        @class = binding.local_variable_get(:class)
      end

      attr_reader :caption, :add_label, :empty
      def spreadsheet? = @spreadsheet
      def actions? = @actions
      def removable? = @removable
      def addable? = @addable
      attr_reader :footer_message

      def before_render
        raise ArgumentError, "RecordTable requires at least one column" if columns.empty?
        raise ArgumentError, "RecordTable requires a blank_row to clone" if addable? && !blank_row?
        raise ArgumentError, "RecordTable requires an add_label" if addable? && add_label.blank?
      end

      def table_classes = tw_merge("panel-record-table", ("panel-record-table--spreadsheet" if spreadsheet?), @class)

      # The leading control column counts too — a spanning cell that stops short
      # of it leaves the empty state and the add row visibly inset.
      def column_count = columns.size + (removable? ? 1 : 0) + (actions? ? 1 : 0)

      # A group heading renders its own control cell, so its label spans what is
      # left after that column rather than the whole width.
      def group_colspan = column_count - (removable? ? 1 : 0)

      # Only records answer the empty state. A table showing group headings and
      # nothing under them is still empty in the sense the message means.
      def records? = @record_row_count.to_i.positive?
    end
  end
end
