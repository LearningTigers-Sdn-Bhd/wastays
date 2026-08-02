# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Sheet-based "post folio transaction". One controller serves the four
      # posting kinds — payment, refund, charge, adjustment — which differ only
      # in their form fields and their permission slug.
      #
      # Business rules live in Folios::Transactions::PostStaffTransaction; this
      # controller only orchestrates authorization, input, rendering, and
      # completion.
      class TransactionsController < BaseController
        # The slug for a posting is derived from what is actually being posted,
        # so it cannot be declared once on the class.
        FOLIO_POSTING_PERMISSIONS = {
          [ "charge", "other" ] => "post_folio_charges",
          [ "payment", "" ] => "post_folio_payments",
          [ "payment", "cash" ] => "post_folio_payments",
          [ "payment", "booking_payment" ] => "post_folio_payments",
          [ "payment", "gateway_payment" ] => "post_folio_payments",
          [ "payment", "refund" ] => "execute_folio_refunds",
          [ "adjustment", "adjustment" ] => "post_folio_adjustments",
          [ "adjustment", "discount" ] => "post_folio_adjustments",
          [ "adjustment", "other" ] => "post_folio_adjustments",
          [ "adjustment", "correction" ] => "post_folio_corrections",
          [ "adjustment", "write_off" ] => "post_folio_write_offs"
        }.freeze

        def show
          return create if request.post?

          @active_folio = default_folio
          @open_folios = @booking.booking_folios.open.order(is_primary: :desc, folio_sequence: :asc, folio_number: :asc, id: :asc).to_a
          @transaction_type = requested_transaction_type
          @category = params[:category].presence
          @amount = checkout_settlement? ? checkout_settlement_payload[:amount] : params[:amount]
          @checkout_settlement = checkout_settlement_kind
          @description = checkout_settlement_description if checkout_settlement?
          assign_form_config
          render :show, layout: false
        end

        private

        # Two questions, two answers: opening a form is gated on the posting
        # *kind*, posting is gated on the concrete category being written. They
        # read from different places because a GET carries the kind in the query
        # string and a POST carries the category in the payload.
        def authorize_folio_action!
          permitted = request.post? ? permitted_to_post? : permitted_to_open_form?
          raise Pundit::NotAuthorizedError unless permitted
        end

        def permitted_to_open_form?
          case [ requested_transaction_type, requested_category ]
          when [ "payment", "refund" ] then current_user.has_permission?("execute_folio_refunds", hotel: current_hotel)
          when [ "payment", "" ]       then current_user.has_permission?("post_folio_payments", hotel: current_hotel)
          when [ "charge", "" ]        then current_user.has_permission?("post_folio_charges", hotel: current_hotel)
          when [ "adjustment", "" ]    then adjustment_category_options.any?
          else false
          end
        end

        def permitted_to_post?
          slug = posting_permission_slug
          slug.present? && current_user.has_permission?(slug, hotel: current_hotel)
        end

        def posting_permission_slug
          type = requested_transaction_type
          category = requested_category
          return "execute_folio_refunds" if type == "payment" && category == "refund"
          return "post_folio_payments" if type == "payment" && folio_transaction_params[:payment_source].present?
          return "post_folio_payments" if type == "payment" && category != "refund"
          return "post_folio_charges" if type == "charge"

          FOLIO_POSTING_PERMISSIONS.fetch([ type, category ], nil)
        end

        def requested_transaction_type
          (request.post? ? folio_transaction_params[:transaction_type] : params[:transaction_type]).to_s
        end

        def requested_category
          (request.post? ? folio_transaction_params[:category] : params[:category]).to_s
        end

        def create
          if checkout_settlement? && !valid_checkout_settlement_request?
            return render_checkout_settlement_error("Checkout settlement type does not match the requested transaction.")
          end

          target_folio = posting_folio

          unless target_folio
            message = folio_transaction_params[:booking_folio_id].present? ? "Selected folio is not available for this booking." : "Booking has no folio."
            return checkout_settlement? ? render_checkout_settlement_error(message) : complete_action(alert: message)
          end

          result = checkout_settlement? ? post_locked_checkout_settlement(target_folio) : post_staff_transaction(target_folio)

          return checkout_settlement? ? render_checkout_settlement_error(result.error) : complete_action(alert: result.error) unless result.success?

          return complete_checkout_settlement if checkout_settlement?

          complete_action(notice: "Folio transaction posted.")
        end

        def default_folio
          if checkout_settlement?
            return scoped_booking_folios.open.find_by(id: checkout_settlement_payload[:folio_id])
          end

          selected = scoped_booking_folios.open.find_by(id: params[:active_folio_id]) if params[:active_folio_id].present?
          selected ||
            @booking.booking_folio&.then { |folio| folio.open? ? folio : nil } ||
            scoped_booking_folios.open.order(:folio_sequence, :folio_number, :id).first
        end

        def posting_folio
          if checkout_settlement?
            return scoped_booking_folios.open.find_by(id: checkout_settlement_payload[:folio_id])
          end

          if folio_transaction_params[:booking_folio_id].present?
            scoped_booking_folios.open.find_by(id: folio_transaction_params[:booking_folio_id])
          else
            @booking.booking_folio
          end
        end

        def scoped_booking_folios
          @booking.booking_folios.where(hotel_id: current_hotel.id)
        end

        def assign_form_config
          case [ @transaction_type, @category.to_s ]
          when [ "payment", "refund" ]
            @form_title = "Issue refund"
            @form_description = "Enter a positive refund amount. It will be recorded as a negative refund payment."
            @refund_source_options = ::Folios::Payments::RefundSource.options
            @signed_amount = false
            @submit_label = "Issue refund"
          when [ "payment", "" ]
            @form_title = "Post payment"
            @form_description = "Record a staff-posted payment against the selected folio."
            @payment_source_options = ::Folios::Payments::PaymentSource.options
            @signed_amount = false
            @submit_label = "Post payment"
          when [ "charge", "" ]
            @form_title = "Add charge"
            @form_description = "Record a manual charge using a transaction code preset."
            @transaction_code_options = current_hotel.transaction_codes.active.charge.order(:code)
            @signed_amount = false
            @submit_label = "Add charge"
          when [ "adjustment", "" ]
            @form_title = "Post adjustment"
            @form_description = "Record an authorized adjustment, correction, discount, write-off, or other adjustment."
            @category_options = adjustment_category_options
            @signed_amount = true
            @submit_label = "Post adjustment"
          else
            @form_title = "Post folio transaction"
            @form_description = "Record a folio transaction against the selected folio."
            @category_options = []
            @signed_amount = false
            @submit_label = "Post transaction"
          end

          return unless checkout_settlement?

          @form_title = @checkout_settlement == "refund" ? "Settle checkout refund" : "Settle checkout payment"
          @form_description = "Post the exact folio balance, then return to checkout."
          @submit_label = @checkout_settlement == "refund" ? "Issue checkout refund" : "Post checkout payment"
        end

        def checkout_settlement_kind
          value = checkout_settlement_payload&.dig(:kind).to_s
          value if value.in?(%w[payment refund])
        end

        def checkout_settlement?
          params[:settlement_token].present?
        end

        def posting_amount
          return folio_transaction_params[:amount] unless checkout_settlement?

          checkout_settlement_payload[:amount]
        end

        def valid_checkout_settlement_request?
          return requested_transaction_type == "payment" && requested_category == "refund" if checkout_settlement_kind == "refund"

          requested_transaction_type == "payment" && requested_category.blank?
        end

        def checkout_settlement_payload
          return @checkout_settlement_payload if defined?(@checkout_settlement_payload)
          return @checkout_settlement_payload = nil if params[:settlement_token].blank?

          payload = ::Checkouts::SettlementToken.verify(params[:settlement_token])
          raise ActiveRecord::RecordNotFound if @booking.present? && payload[:booking_id].to_i != @booking.id

          @checkout_settlement_payload = payload
        rescue ActiveSupport::MessageVerifier::InvalidSignature
          raise ActiveRecord::RecordNotFound
        end

        def post_locked_checkout_settlement(folio)
          result = nil
          error = nil

          folio.with_lock do
            folio.reload
            expected_balance = checkout_settlement_balance(folio) + checkout_settlement_payload[:adjustment].to_d
            token_amount = checkout_settlement_payload[:amount].to_d
            valid_direction = checkout_settlement_kind == "payment" ? expected_balance.positive? : expected_balance.negative?
            unless valid_direction && token_amount == expected_balance.abs
              error = "Folio balance changed. Return to checkout and reopen the settlement."
              next
            end

            result = post_staff_transaction(folio)
          end

          return ::Folios::Transactions::TransactionResult.failure(error) if error.present?

          result
        end

        def post_staff_transaction(folio)
          ::Folios::Transactions::PostStaffTransaction.call(
            folio: folio,
            user: current_user,
            transaction_type: folio_transaction_params[:transaction_type],
            category: folio_transaction_params[:category],
            amount: posting_amount,
            description: checkout_settlement? ? checkout_settlement_description : folio_transaction_params[:description],
            posting_date: folio_transaction_params[:posting_date],
            transaction_code_id: folio_transaction_params[:transaction_code_id],
            options: posting_options
          )
        end

        def checkout_settlement_balance(folio)
          business_date = current_hotel.current_business_date
          early_lines = if business_date < @booking.check_out.to_date
            ::Folios::Charges::PostEarlyCheckoutCharges.pending_preview(
              booking: @booking,
              folio: @booking.booking_folio,
              departure_date: business_date,
              original_check_out: @booking.check_out
            )
          else
            []
          end
          sheet = HotelPortal::Bookings::Actions::Checkouts::SheetPresenter.new(
            booking: @booking,
            hotel: current_hotel,
            user: current_user,
            early_checkout_lines: early_lines,
            early_checkout: business_date < @booking.check_out.to_date
          )
          sheet.folio_rows.find { |row| row.folio.id == folio.id }&.balance.to_d
        end

        def checkout_settlement_description
          action = checkout_settlement_kind == "refund" ? "refund" : "payment"
          "Checkout #{action} for #{posting_folio&.display_name || 'folio'}"
        end

        def complete_checkout_settlement
          respond_to do |format|
            format.turbo_stream do
              render body: helpers.turbo_stream_action_tag(:complete_sheet, target: requesting_sheet_frame), content_type: Mime[:turbo_stream]
            end
            format.html { redirect_to @return_to, notice: "Folio settlement posted.", status: :see_other }
          end
        end

        def render_checkout_settlement_error(error)
          @active_folio = posting_folio
          @open_folios = scoped_booking_folios.open.order(is_primary: :desc, folio_sequence: :asc, folio_number: :asc, id: :asc).to_a
          @transaction_type = requested_transaction_type
          @category = requested_category.presence
          @amount = posting_amount
          @checkout_settlement = checkout_settlement_kind
          @description = checkout_settlement_description
          @transaction_error = error
          assign_form_config
          render :show, formats: :html, layout: false, status: :unprocessable_content
        end

        def adjustment_category_options
          options = []
          options += %w[adjustment discount other] if current_user.has_permission?("post_folio_adjustments", hotel: current_hotel)
          options << "correction" if current_user.has_permission?("post_folio_corrections", hotel: current_hotel)
          options << "write_off" if current_user.has_permission?("post_folio_write_offs", hotel: current_hotel)
          options
        end

        def posting_options
          options = {}
          options[:require_transaction_code] = true if folio_transaction_params[:transaction_type].to_s == "charge"
          if folio_transaction_params[:transaction_type].to_s == "payment" && !refund_transaction?
            options[:payment_source] = folio_transaction_params[:payment_source].to_s.strip
          end

          metadata = {}
          metadata[:reference] = folio_transaction_params[:reference].to_s.strip if folio_transaction_params[:reference].present?
          metadata[:note] = folio_transaction_params[:note].to_s.strip if folio_transaction_params[:note].present?
          options[:routing_override_reason] = folio_transaction_params[:routing_override_reason].to_s.strip if folio_transaction_params[:routing_override_reason].present?
          if refund_transaction? && folio_transaction_params[:refund_source].present?
            metadata[:refund_source] = folio_transaction_params[:refund_source].to_s.strip
          end
          options[:metadata] = metadata if metadata.any?

          options
        end

        def refund_transaction?
          folio_transaction_params[:transaction_type].to_s == "payment" &&
            folio_transaction_params[:category].to_s == "refund"
        end

        def folio_transaction_params
          @folio_transaction_params ||= params.fetch(:folio_transaction, ActionController::Parameters.new).permit(
            :transaction_type,
            :category,
            :transaction_code_id,
            :amount,
            :description,
            :posting_date,
            :reference,
            :note,
            :payment_source,
            :refund_source,
            :booking_folio_id,
            :routing_override_reason
          )
        end
      end
    end
  end
end
