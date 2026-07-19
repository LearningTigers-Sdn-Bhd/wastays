# frozen_string_literal: true

module HotelPortal
  module StayView
    class OperationalIndicators < PanelsUI::BaseComponent
      PRESENTATIONS = {
        dnd: { label: "Do not disturb", icon: "door-closed", variant: :warning }.freeze,
        priority: { label: "Cleaning priority", icon: "flag", variant: :destructive }.freeze,
        housekeeping: { label: "Housekeeping request", icon: "brush-cleaning", variant: :info }.freeze
      }.freeze

      DEFAULT_ORDER = %i[housekeeping priority dnd].freeze
      ORDERS = PRESENTATIONS.keys.freeze

      def initialize(room:, state: nil, order: DEFAULT_ORDER, class: nil, **attributes)
        @room = room
        @state = state
        @order = Array(order).map(&:to_sym)
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "OperationalIndicators requires a StayView::RoomRow" unless @room.is_a?(::StayView::RoomRow)
        raise ArgumentError, "Unsupported operational indicator order" unless @order.sort == ORDERS.sort
      end

      def call
        return if indicators.empty?

        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        aria = attributes.delete(:aria) || {}
        tag.div(
          safe_join(indicators),
          **attributes.merge(
            class: tw_merge("flex items-center gap-1", @class, attributes.delete(:class)),
            data: data.merge(slot: "stay-view-operational-indicators"),
            aria: aria.merge(label: "Current operational indicators for room #{@room.room_number}")
          )
        )
      end

      private

      def indicators
        @indicators ||= @order.filter_map do |key|
          case key
          when :housekeeping then housekeeping_popover
          when :priority, :dnd then flag_popover(key) if @room.capabilities.view_room_readiness?
          end
        end
      end

      def flag_popover(key)
        presentation = PRESENTATIONS.fetch(key)
        active = @room.operational_flags.fetch(key, false)
        label = "#{presentation.fetch(:label)}: #{active ? 'on' : 'off'}"
        editable = @state && @room.capabilities.manage_room_status?

        render PanelsUI::Popover.new(
          id: flag_id(key),
          placement: :bottom_end,
          class: "w-72 p-3",
          focus: editable
        ) do |popover|
          popover.with_trigger(unstyled: true, aria_label: editable ? "#{label} — change" : label, class: "inline-flex rounded-full") do
            flag_badge(key, active, presentation)
          end
          editable ? flag_form(key, active, presentation) : flag_details(key, active, presentation)
        end
      end

      def flag_badge(key, active, presentation)
        render PanelsUI::Badge.new(
          variant: active ? presentation.fetch(:variant) : :outline,
          size: :sm,
          shape: :circular,
          data: { slot: "stay-view-#{key}-indicator", state: active ? "on" : "off" },
          aria: { hidden: true }
        ) do
          helpers.app_icon(presentation.fetch(:icon), class: "size-3", aria: { hidden: true })
        end
      end

      def flag_details(key, active, presentation)
        tag.div(class: "space-y-1 text-left") do
          safe_join([
            tag.p(presentation.fetch(:label), class: "text-sm font-semibold text-foreground"),
            tag.p(active ? "Currently on" : "Currently off", class: "text-xs text-muted-foreground"),
            (tag.p(@room.priority_note, class: "break-words text-sm text-foreground") if key == :priority && @room.priority_note.present?)
          ].compact)
        end
      end

      def flag_form(key, active, presentation)
        helpers.form_with(
          scope: :room_status,
          url: helpers.hotel_stay_view_room_status_path(helpers.current_hotel, @room.room_type_id, @room.room_number),
          method: :patch,
          class: "space-y-3 text-left",
          data: {
            turbo_stream: true,
            controller: "stay-view--operational-flags",
            action: "turbo:submit-start->stay-view--operational-flags#preserveFocus",
            "stay-view--operational-flags-focus-id-value": "#{flag_id(key)}-trigger"
          }
        ) do |form|
          safe_join([
            tag.div do
              safe_join([
                tag.p(presentation.fetch(:label), class: "text-sm font-semibold text-foreground"),
                tag.p(flag_description(key), class: "text-xs text-muted-foreground")
              ])
            end,
            render(PanelsUI::Switch.new(
              form:,
              attribute: key,
              label: presentation.fetch(:label),
              description: active ? "Currently on" : "Currently off",
              checked: active,
              size: :sm
            )),
            (priority_note_field(form) if key == :priority),
            state_fields,
            helpers.hidden_field_tag(:flag_control, key),
            tag.div(class: "flex justify-end") do
              render PanelsUI::Button.new(as: :button, type: :submit, size: :sm) do
                "Apply"
              end
            end
          ].compact)
        end
      end

      def priority_note_field(form)
        render PanelsUI::FormField.new(
          form:,
          attribute: :priority_note,
          label: "Priority note",
          hint: "Optional cleaning or preparation instructions.",
          size: :sm
        ) do |field|
          field.with_text_area(rows: 3, value: @room.priority_note)
        end
      end

      def state_fields
        fields = @state.query.map { |key, value| helpers.hidden_field_tag(key, value) }
        fields << helpers.hidden_field_tag(:return_to, @state.return_path(helpers.current_hotel))
        safe_join(fields)
      end

      def flag_description(key)
        return "Applies only to the hotel's current business date." if key == :dnd

        "Marks this room for expedited cleaning or preparation."
      end

      def flag_id(key) = "#{@room.dom_id}-#{key}"

      def housekeeping_popover
        return if @room.housekeeping_alerts.empty?

        presentation = PRESENTATIONS.fetch(:housekeeping)
        count = @room.housekeeping_alerts.size
        label = helpers.pluralize(count, "active housekeeping request")
        render PanelsUI::Popover.new(
          id: "#{@room.dom_id}-housekeeping",
          placement: :bottom_end,
          class: "w-72 p-3",
          focus: true
        ) do |popover|
          popover.with_trigger(unstyled: true, aria_label: label, class: "inline-flex rounded-full") do
            render PanelsUI::Badge.new(
              variant: presentation.fetch(:variant),
              size: :sm,
              shape: :rounded,
              class: "gap-1",
              aria: { hidden: true }
            ) do
              safe_join([
                helpers.app_icon(presentation.fetch(:icon), class: "size-3", aria: { hidden: true }),
                tag.span(count)
              ])
            end
          end
          housekeeping_content
        end
      end

      def housekeeping_content
        tag.div(class: "space-y-3 text-left") do
          safe_join([
            dnd_warning,
            tag.div do
              safe_join([
                tag.p("Housekeeping", class: "text-sm font-semibold text-foreground"),
                tag.p("Current active requests", class: "text-xs text-muted-foreground")
              ])
            end,
            tag.ul(class: "max-h-64 space-y-2 overflow-y-auto", aria: { label: "Active housekeeping requests" }) do
              safe_join(@room.housekeeping_alerts.map { |alert| housekeeping_item(alert) })
            end
          ].compact)
        end
      end

      def dnd_warning
        return unless @room.operational_flags[:dnd]

        tag.div(class: "rounded-md border border-border bg-muted p-2", role: "alert") do
          safe_join([
            tag.p("Do not enter / do not clean", class: "text-sm font-semibold text-foreground"),
            tag.p("Do not service this room while DND is active.", class: "text-xs text-muted-foreground")
          ])
        end
      end

      def housekeeping_item(alert)
        tag.li(class: "rounded-md border border-border bg-muted p-2") do
          safe_join([
            tag.p(alert.details, class: "break-words text-sm text-foreground"),
            tag.p(
              [ alert.status.to_s.humanize, alert.assigned_to_name.presence || "Unassigned" ].join(" · "),
              class: "mt-1 text-xs text-muted-foreground"
            ),
            tag.time(
              alert.requested_at.to_fs(:short),
              datetime: alert.requested_at.iso8601,
              class: "mt-1 block text-xs text-muted-foreground"
            ),
            assignment_history(alert),
            housekeeping_item_actions(alert)
          ].compact)
        end
      end

      def assignment_history(alert)
        return if alert.assignment_history.empty?

        render PanelsUI::Collapsible.new(
          id: "#{@room.dom_id}-housekeeping-#{alert.request_id}-history",
          class: "mt-2",
          trigger_class: "text-xs font-medium text-foreground",
          content_class: "pt-2",
          region: true
        ) do |collapsible|
          collapsible.with_trigger { "Assignment history (#{alert.assignment_history.size})" }
          collapsible.with_body do
            tag.ol(class: "space-y-2", aria: { label: "Assignment history" }) do
              safe_join(alert.assignment_history.map { |event| assignment_event(event) })
            end
          end
        end
      end

      def assignment_event(event)
        action = event.assigned? ? "Assigned to #{event.assigned_to_name}" : "Unassigned"
        tag.li(class: "text-xs text-foreground") do
          safe_join([
            tag.p(action, class: "font-medium"),
            tag.p("by #{event.assigned_by_name}", class: "text-muted-foreground"),
            tag.time(event.timestamp.to_fs(:short), datetime: event.timestamp.iso8601, class: "text-muted-foreground")
          ])
        end
      end

      def housekeeping_item_actions(alert)
        return unless @state

        actions = helpers.stay_view_housekeeping_task_actions(alert, @room, @state)
        return if actions.empty?

        tag.div(class: "mt-2 flex flex-wrap gap-1.5") do
          safe_join(actions.map { |action| housekeeping_item_action(action) })
        end
      end

      def housekeeping_item_action(action)
        render PanelsUI::Button.new(href: action.fetch(:href), variant: :secondary, size: :xs, data: action.fetch(:data, {})) do
          safe_join([
            helpers.app_icon(action.fetch(:icon), class: "size-3.5", aria: { hidden: true }),
            tag.span(action.fetch(:label))
          ])
        end
      end
    end
  end
end
