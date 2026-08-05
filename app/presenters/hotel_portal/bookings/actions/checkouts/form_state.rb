# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      module Checkouts
        # Presentation-only state for the checkout Sheet. GET requests receive
        # calculated defaults; failed POST requests receive the submitted values,
        # including intentional blanks, so the resolver can reopen unchanged.
        class FormState
          DEFAULT_PAYMENT_METHOD = "cash"

          attr_reader :selected_booking_ids

          def initialize(anchor_booking:, bookings:, sheets:, checked_out_at_default:, params:, submitted:, group:)
            @anchor_booking = anchor_booking
            @bookings = bookings
            @sheets = sheets
            @checked_out_at_default = checked_out_at_default
            @params = normalize_params(params)
            @submitted = submitted
            @group = group
            @selected_booking_ids = resolve_selected_booking_ids
          end

          def checked_out_at
            submitted_value("booking", "checked_out_at", default: @checked_out_at_default)
          end

          def selected?(booking)
            selected_booking_ids.include?(booking.id.to_s)
          end

          def selected_count
            selected_booking_ids.size
          end

          def folio_values(booking, row)
            prefix = [ "checkout_bookings", booking.id.to_s, "folios", row.folio.id.to_s ]

            {
              action: submitted_value(*prefix, "action", default: row.default_action),
              amount: submitted_value(*prefix, "amount", default: format("%.2f", row.balance.to_d)),
              payment_method: submitted_value(*prefix, "payment_method", default: DEFAULT_PAYMENT_METHOD),
              payment_reference: submitted_value(*prefix, "payment_reference", default: nil),
              reason: submitted_value(*prefix, "reason", default: nil),
              credit_override: submitted_value(*prefix, "credit_override", default: "0"),
              credit_override_reason: submitted_value(*prefix, "credit_override_reason", default: nil)
            }
          end

          def early_departure_values(booking)
            prefix = [ "early_departures", booking.id.to_s ]

            {
              apply_charge: submitted_value(*prefix, "apply_charge", default: "false"),
              charge_source: submitted_value(*prefix, "charge_source", default: "policy"),
              type: submitted_value(*prefix, "type", default: "amount"),
              value: submitted_value(*prefix, "value", default: nil),
              charge_amount: submitted_value(*prefix, "charge_amount", default: "0.00")
            }
          end

          def collect_now_total
            total_for("pay_now")
          end

          def direct_bill_total
            total_for("direct_bill")
          end

          def keep_open_count
            selected_rows.count do |booking, row|
              SheetPresenter::EXCEPTION_ACTIONS.include?(folio_values(booking, row)[:action])
            end
          end

          private

          def resolve_selected_booking_ids
            return [ @anchor_booking.id.to_s ] unless @group

            # On GET the whole eligible group is pre-selected so the server render
            # agrees with the group rail (which checks every eligible booking) —
            # otherwise non-anchor rows render disabled/greyed and the summary
            # totals disagree with the rail on first paint.
            return @bookings.map { |booking| booking.id.to_s } unless @submitted

            Array(value_at("booking_ids", default: [])).reject(&:blank?).map(&:to_s)
          end

          def selected_rows
            @bookings.select { |booking| selected?(booking) }.flat_map do |booking|
              @sheets.fetch(booking).folio_rows.map { |row| [ booking, row ] }
            end
          end

          def total_for(action)
            selected_rows.sum do |booking, row|
              values = folio_values(booking, row)
              values[:action] == action ? values[:amount].to_d.abs : 0.to_d
            end
          end

          def submitted_value(*path, default:)
            return default unless @submitted

            value_at(*path, default: default)
          end

          def value_at(*path, default:)
            value = @params
            path.each do |key|
              return default unless value.is_a?(Hash) && value.key?(key.to_s)

              value = value[key.to_s]
            end
            value
          end

          def normalize_params(params)
            hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
            hash.deep_stringify_keys
          end
        end
      end
    end
  end
end
