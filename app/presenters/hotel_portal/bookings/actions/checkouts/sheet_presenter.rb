# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      module Checkouts
        # View-model for the Sheet-based checkout, scoped to the booking action
        # so settlement presentation stays isolated from other folio concerns.
        #
        # Early-checkout preview lines are attributed to the folio they *route*
        # to via the `target_folio_id` tagged by the folios service. Routing
        # lives in Folios::Charges::PostEarlyCheckoutCharges; this presenter only reads
        # the tag.
        class SheetPresenter
          include Rails.application.routes.url_helpers

          EXCEPTION_ACTIONS = %w[keep_open manager_review write_off_approval].freeze
          DIRECT_BILL_ACTION = "direct_bill"
          INPUT_ACTIONS = %w[pay_now direct_bill keep_open manager_review write_off_approval].freeze

          FolioRow = Struct.new(
            :folio,
            :name,
            :payer_label,
            :balance,
            :status_label,
            :status_tone,
            :action_options,
            :default_action,
            :requires_input,
            :requires_payment,
            :requires_reason,
            :ledger_path,
            keyword_init: true
          )

          attr_reader :booking, :hotel, :user, :early_checkout_lines

          def initialize(booking:, hotel:, user:, early_checkout_lines: [])
            @booking = booking
            @hotel = hotel
            @user = user
            @early_checkout_lines = Array(early_checkout_lines)
          end

          def currency
            booking.currency.presence || hotel.default_currency.presence || "MYR"
          end

          def folios
            @folios ||= booking.booking_folios
              .includes(:folio_transactions, :folio_forecasted_charges, hotel_corporate_account: :corporate_account)
              .order(is_primary: :desc, folio_sequence: :asc, folio_number: :asc, id: :asc)
              .to_a
          end

          def folio_rows
            @folio_rows ||= folios.map { |folio| row_for(folio) }
          end

          def settlement_rows
            folio_rows.select(&:requires_input)
          end

          def payment_method_options
            ::Checkouts::PaymentMethods.settlement_options
          end

          def security_deposit_release_method_options
            ::Checkouts::PaymentMethods.release_options
          end

          def booking_balance
            folio_rows.sum { |row| row.balance.to_d }
          end

          def total_charges
            folios.sum { |folio| folio.total_charges.to_d } + early_checkout_lines.sum { |line| line[:amount].to_d }
          end

          def total_payments
            folios.sum { |folio| folio.total_payments.to_d }
          end

          def folio_count_label
            "#{open_folio_count} Open / #{closed_folio_count} Closed"
          end

          def deposit_status_label
            (booking.deposit_status.presence || "not_required").titleize
          end

          def held_deposits
            @held_deposits ||= booking.deposits.kind_security.where(status: "held").includes(:deposit_movements)
          end

          def held_deposit_total
            held_deposits.sum(&:available_amount)
          end

          def can_submit?
            folios.any?
          end

          def money(amount)
            "#{currency} #{format('%.2f', amount.to_d)}"
          end

          private

          def row_for(folio)
            balance = balance_for(folio)
            action_options = action_options_for(folio, balance)
            default_action = action_options.first&.last

            FolioRow.new(
              folio: folio,
              name: folio.display_name,
              payer_label: payer_label_for(folio),
              balance: balance,
              status_label: status_label_for(folio, balance),
              status_tone: status_tone_for(folio, balance),
              action_options: action_options,
              default_action: default_action,
              requires_input: INPUT_ACTIONS.include?(default_action),
              requires_payment: default_action == "pay_now",
              requires_reason: EXCEPTION_ACTIONS.include?(default_action),
              ledger_path: hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)
            )
          end

          # During an early checkout the future forecasts are truncated and the
          # early-checkout lines are posted instead, each to its routed folio. So
          # every folio's preview balance is its posted balance plus the early
          # lines that route to it (never its soon-to-be-truncated forecasts).
          def balance_for(folio)
            if early_checkout_lines.any?
              folio.outstanding_balance.to_d + early_total_for(folio)
            else
              folio.projected_outstanding_balance.to_d
            end
          end

          def early_total_for(folio)
            early_checkout_lines
              .select { |line| line[:target_folio_id].to_i == folio.id }
              .sum { |line| line[:amount].to_d }
          end

          def action_options_for(folio, balance)
            return [ [ "Closed", "closed" ] ] if folio.closed?
            return [ [ "Voided", "voided" ] ] if folio.voided?

            case folio_kind(folio)
            when :guest
              guest_action_options(balance)
            when :company
              company_action_options(folio, balance)
            else
              custom_action_options(balance)
            end
          end

          def guest_action_options(balance)
            return [ [ "Pay Now", "pay_now" ] ] if balance.positive?
            return [ [ "Close", "close" ] ] if balance.zero?

            [ [ "Refund / Credit Handling", "refund_credit_handling" ] ]
          end

          def company_action_options(folio, balance)
            if balance.positive?
              options = []
              options << [ "Direct Bill", DIRECT_BILL_ACTION ] if direct_bill_enabled?(folio)
              options << [ "Pay Now", "pay_now" ]
              options << [ "Keep Open", "keep_open" ]
              return options
            end
            return [ [ "Close", "close" ] ] if balance.zero?

            [ [ "Refund / Credit Handling", "refund_credit_handling" ], [ "Keep Open", "keep_open" ] ]
          end

          def custom_action_options(balance)
            return [ [ "Close", "close" ] ] if balance.zero?

            [
              [ "Keep Open", "keep_open" ],
              [ "Manager Review", "manager_review" ],
              [ "Write Off Approval", "write_off_approval" ]
            ]
          end

          def folio_kind(folio)
            return :guest if folio.folio_type == "guest" && folio.payer_type == "guest"
            return :company if folio.payer_type == "company"

            :custom
          end

          def direct_bill_enabled?(folio)
            relationship = folio.hotel_corporate_account
            relationship.present? && relationship.active? && relationship.direct_bill_enabled?
          end

          # Who is responsible for settling this folio — a concrete party rather
          # than the folio type, so the folio card reads "WS-…/1 · Faiz Hakim"
          # (guest) or "· Acme Sdn Bhd" (company) instead of echoing the title.
          def payer_label_for(folio)
            return "Hotel" if folio.folio_type_house?
            return "Agent" if folio.hotel_corporate_account&.account_type == "travel_agent"

            case folio.payer_type
            when "company"
              folio.hotel_corporate_account&.corporate_account&.name.presence || folio.payer_display_label
            when "guest"
              booking.guest_name.presence || folio.payer_display_label
            else
              folio.payer_display_label
            end
          end

          def status_label_for(folio, balance)
            return folio.status.to_s.humanize unless folio.open?
            return "Ready" if balance.zero?
            return "Needs Pay" if folio_kind(folio) == :guest && balance.positive?

            "Needs Action"
          end

          def status_tone_for(folio, balance)
            return "slate" unless folio.open?
            return "emerald" if balance.zero?
            return "amber" if balance.positive?

            "rose"
          end

          def open_folio_count
            folios.count(&:open?)
          end

          def closed_folio_count
            folios.count(&:closed?)
          end
        end
      end
    end
  end
end
