# frozen_string_literal: true

module HotelPortal
  module NightAuditRuns
    class SheetPresenter
      Step = Data.define(:key, :label, :state)
      Action = Data.define(:key, :label, :variant)
      Item = Data.define(:type, :label, :description, :details, :booking_id, :booking_status, :actions)

      BOOKING_KEYS = %w[
        due_out_not_checked_out checked_in_missing_timestamp completed_missing_timestamp
        missed_arrival_not_resolved detection_failures
      ].freeze
      FINANCIAL_KEYS = %w[
        missing_folio missing_nightly_charges outstanding_folio_balance folio_balance_exceptions
        captured_payment_not_synced refund_not_synced
      ].freeze
      STEP_LABELS = {
        bookings: "Bookings",
        payments_charges: "Payments & charges",
        review: "Confirm"
      }.freeze
      ITEM_COPY = {
        "due_out_not_checked_out" => [ "Departure needs attention", "Choose what happened with this guest's departure." ],
        "missed_arrival_not_resolved" => [ "Arrival needs attention", "Choose what happened with this guest's arrival." ],
        "checked_in_missing_timestamp" => [ "Check-in time missing", "Add the guest's actual check-in date and time." ],
        "completed_missing_timestamp" => [ "Checkout time missing", "Add the guest's actual checkout date and time." ],
        "detection_failures" => [ "Booking check needs attention", "Refresh the booking checks to try again." ],
        "missing_folio" => [ "Guest bill missing", "Create a guest bill before closing the date." ],
        "missing_nightly_charges" => [ "Room charges need attention", "Add the missing room charges to the guest bill." ],
        "outstanding_folio_balance" => [ "Balance still due", "Record a payment or open the guest bill." ],
        "folio_balance_exceptions" => [ "Guest bill needs attention", "Open the guest bill before closing the date." ],
        "captured_payment_not_synced" => [ "Payment missing from guest bill", "Add the captured payment to the guest bill." ],
        "refund_not_synced" => [ "Refund missing from guest bill", "Add the completed refund to the guest bill." ]
      }.freeze

      attr_reader :hotel, :business_date, :evaluation, :night_audit

      def initialize(hotel:, business_date:, evaluation:, night_audit: nil)
        @hotel = hotel
        @business_date = business_date.to_date
        @evaluation = evaluation.to_h
        @night_audit = night_audit
      end

      def processing? = night_audit&.status.in?(%w[pending running])
      def failed? = night_audit&.failed?
      def next_business_date = business_date + 1.day
      def closable? = hotel.can_audit_date?(business_date)

      def review_started?
        return false unless night_audit
        return true unless night_audit.preparing?

        night_audit.trigger_mode == "manual" && night_audit.performed_by_user_id.present?
      end

      def booking_items = items_for_keys(BOOKING_KEYS)
      def financial_items = items_for_keys(FINANCIAL_KEYS)
      def blockers = booking_items + financial_items
      def blocker_count = blockers.size
      def warning_count = warnings.size

      def warnings
        exception_details.flat_map do |key, items|
          Array(items).map { |item| item.to_h.stringify_keys.merge("type" => key) }
        end
      end

      def current_step
        return :bookings if booking_items.any?
        return :payments_charges if financial_items.any?

        :review
      end

      def steps
        keys = STEP_LABELS.keys
        current_index = keys.index(current_step)
        keys.map.with_index do |key, index|
          state = if index < current_index
            :complete
          elsif index == current_index
            :current
          else
            :upcoming
          end
          Step.new(key:, label: STEP_LABELS.fetch(key), state:)
        end
      end

      def ready? = !processing? && !failed? && blockers.empty?
      def ready_to_run? = review_started? && ready? && !detection_needed?

      def detection_needed?
        return false unless review_started?

        booking_items.any? { |item| item.booking_status.in?(%w[confirmed checked_in]) && item.type.in?(%w[due_out_not_checked_out missed_arrival_not_resolved]) }
      end

      def review_result_message
        review = night_audit&.summary.to_h["manual_review"].to_h
        return if review.empty?

        due_outs = review["due_outs_detected_count"].to_i
        arrivals = review["missed_arrivals_detected_count"].to_i
        failures = review["detection_failure_count"].to_i
        message = "#{due_outs} #{'departure'.pluralize(due_outs)} and #{arrivals} missed #{'arrival'.pluralize(arrivals)} found."
        failures.positive? ? "#{message} #{failures} #{'booking'.pluralize(failures)} still need attention." : message
      end

      def availability_message
        window = hotel.business_day_window_for(business_date)
        "You can close this date and move the hotel to #{next_business_date.strftime('%d %b %Y')} after #{window.end.strftime('%I:%M %p')} hotel time."
      end

      def failure_message
        night_audit&.night_audit_logs&.where(action_type: "failed")&.order(:id)&.last&.metadata.to_h["error"].presence ||
          "The previous run did not complete. Fix the items that need attention and try again."
      end

      private

      def blocked_details = evaluation.fetch(:blocked_details, evaluation.fetch("blocked_details", {})).to_h.stringify_keys
      def exception_details = evaluation.fetch(:exceptions, evaluation.fetch("exceptions", {})).to_h.stringify_keys

      def items_for_keys(keys)
        keys.flat_map do |type|
          Array(blocked_details[type]).map { |details| build_item(type, details.to_h.stringify_keys) }
        end
      end

      def build_item(type, details)
        booking_id = details["booking_id"]
        status = booking_id.present? ? live_booking_statuses[booking_id.to_i] : nil
        status ||= details["status"]
        label, description = ITEM_COPY.fetch(type, [ "Item needs attention", "Fix this item before closing the date." ])

        Item.new(
          type:,
          label:,
          description:,
          details:,
          booking_id:,
          booking_status: status,
          actions: actions_for(type, status)
        )
      end

      def live_booking_statuses
        @live_booking_statuses ||= begin
          ids = BOOKING_KEYS.flat_map { |key| Array(blocked_details[key]).filter_map { |item| item.to_h.stringify_keys["booking_id"] } }.uniq
          ids.empty? ? {} : hotel.bookings.where(id: ids).pluck(:id, :status).to_h
        end
      end

      def actions_for(type, status)
        case type
        when "due_out_not_checked_out"
          case status
          when "due_out_detected" then [ action(:late_checkout, "Handle late checkout") ]
          when "checkout_required" then [ action(:checkout, "Complete checkout") ]
          when "checked_in" then [ action(:refresh, "Refresh booking checks", :secondary) ]
          else [ action(:open_booking, "Open booking", :secondary) ]
          end
        when "missed_arrival_not_resolved"
          case status
          when "no_show_detected"
            [
              action(:backdated_check_in, "Record an earlier check-in"),
              action(:mark_no_show, "Mark as no-show", :destructive),
              action(:open_booking, "Open booking", :secondary)
            ]
          when "confirmed" then [ action(:refresh, "Refresh booking checks", :secondary) ]
          else [ action(:open_booking, "Open booking", :secondary) ]
          end
        when "checked_in_missing_timestamp" then [ action(:booking_timestamp, "Add check-in time") ]
        when "completed_missing_timestamp" then [ action(:booking_timestamp, "Add checkout time") ]
        when "detection_failures" then [ action(:refresh, "Refresh booking checks", :secondary) ]
        when "missing_folio" then [ action(:create_folio, "Create folio") ]
        when "missing_nightly_charges"
          [ action(:add_room_charges, "Add missing room charges"), action(:open_folio, "Open folio", :secondary) ]
        when "outstanding_folio_balance"
          [ action(:record_payment, "Record payment"), action(:open_folio, "Open folio", :secondary) ]
        when "captured_payment_not_synced" then [ action(:add_payment, "Add payment to guest bill") ]
        when "refund_not_synced" then [ action(:add_refund, "Add refund to guest bill") ]
        else [ action(:open_folio, "Open folio", :secondary) ]
        end
      end

      def action(key, label, variant = :primary) = Action.new(key:, label:, variant:)
    end
  end
end
