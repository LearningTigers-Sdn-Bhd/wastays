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

        def quote
          folio = scoped_booking_folios.open.find_by(id: params[:booking_folio_id]) || default_folio
          extra_charge = current_hotel.hotel_extra_charges.active.includes(transaction_code: :transaction_code_taxes)
            .find_by(id: params[:hotel_extra_charge_id])
          return render json: { error: "Select an available extra charge." }, status: :unprocessable_content if folio.blank? || extra_charge.blank?

          result = ::ExtraCharges::ForecastQuote.call(
            extra_charge: extra_charge,
            folio: folio,
            booking: @booking,
            starts_on: params[:starts_on],
            ends_on: params[:ends_on],
            unit_rate: params[:unit_rate]
          )
          return render json: { error: result.error, allowed_dates: Array(result.allowed_dates).map(&:iso8601) }, status: :unprocessable_content unless result.success?

          render json: schedule_quote_json(result)
        end

        def discount_quote
          folio = scoped_booking_folios.open.find_by(id: params[:booking_folio_id]) || default_folio
          discount = current_hotel.hotel_discounts.active.includes(:transaction_code, :applicable_transaction_codes).find_by(id: params[:hotel_discount_id])
          return render json: { error: "Select an available discount." }, status: :unprocessable_content if folio.blank? || discount.blank?

          result = ::Discounts::Quote.call(
            discount:, folio:, posting_date: params[:posting_date].presence || current_hotel.current_business_date,
            requested_amount: params[:amount], preview: true
          )
          status = result.success? ? :ok : :unprocessable_content
          render json: {
            error: result.error, amount: result.amount&.to_d&.to_s("F"),
            calculated_amount: result.calculated_amount&.to_d&.to_s("F"),
            base_amount: result.base_amount&.to_d&.to_s("F"), fingerprint: result.fingerprint
          }.compact, status:
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
          return current_user.has_permission?("post_folio_charges", hotel: current_hotel) if action_name == "quote"
          return current_user.has_permission?("post_folio_adjustments", hotel: current_hotel) if action_name == "discount_quote"

          case [ requested_transaction_type, requested_category ]
          when [ "payment", "refund" ] then current_user.has_permission?("execute_folio_refunds", hotel: current_hotel)
          when [ "payment", "" ]       then current_user.has_permission?("post_folio_payments", hotel: current_hotel)
          when [ "charge", "" ]        then current_user.has_permission?("post_folio_charges", hotel: current_hotel)
          when [ "adjustment", "discount" ] then current_user.has_permission?("post_folio_adjustments", hotel: current_hotel)
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
          return "post_folio_payments" if type == "payment" && folio_transaction_params[:hotel_payment_method_id].present?
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

          unless result.success?
            return render_transaction_error(result.error) if @extra_charge_posting_error || @discount_posting_error
            return checkout_settlement? ? render_checkout_settlement_error(result.error) : complete_action(alert: result.error)
          end

          return complete_checkout_settlement if checkout_settlement?

          complete_action(notice: @extra_charge_scheduled ? "Extra charge scheduled." : "Folio transaction posted.")
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
            PaymentMethods::EnsureDefaults.call(current_hotel)
            @payment_method_options = current_hotel.hotel_payment_methods.active
              .includes(:transaction_code, surcharge_extra_charge: { transaction_code: :transaction_code_taxes })
              .ordered.to_a
            @payment_method_config = build_payment_method_config
            @signed_amount = false
            @submit_label = "Post payment"
          when [ "charge", "" ]
            @form_title = "Add charge"
            @form_description = "Select an extra charge and review its calculated amount before posting."
            Financials::EnsureDefaultExtraCharges.call(current_hotel)
            @extra_charge_options = current_hotel.hotel_extra_charges.active.includes(:transaction_code).ordered.to_a
            @extra_charge_config = build_extra_charge_config
            @signed_amount = false
            @submit_label = "Add charge"
          when [ "adjustment", "discount" ]
            @form_title = "Apply discount"
            @form_description = "Select a configured discount and review the eligible posted charges."
            Discounts::EnsureDefaults.call(current_hotel)
            @discount_options = current_hotel.hotel_discounts.active.includes(:transaction_code, :applicable_transaction_codes).ordered.to_a
            @signed_amount = false
            @submit_label = "Apply discount"
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
          if folio_transaction_params[:transaction_type].to_s == "adjustment" && folio_transaction_params[:category].to_s == "discount"
            discount = current_hotel.hotel_discounts.active.includes(:transaction_code, :applicable_transaction_codes)
              .find_by(id: folio_transaction_params[:hotel_discount_id])
            unless discount
              @discount_posting_error = true
              return ::Discounts::Post::Result.failure("Select an available discount.")
            end
            result = ::Discounts::Post.call(
              discount:, folio:, user: current_user,
              posting_date: folio_transaction_params[:posting_date], requested_amount: folio_transaction_params[:amount],
              expected_fingerprint: folio_transaction_params[:discount_pricing_fingerprint],
              description: folio_transaction_params[:description], reference: folio_transaction_params[:reference], note: folio_transaction_params[:note]
            )
            unless result.success?
              @discount_posting_error = true
              @amount = result.quote&.amount
              @discount_pricing_fingerprint = result.quote&.fingerprint
            end
            return result
          end

          extra_charge = nil
          quote = nil
          if folio_transaction_params[:transaction_type].to_s == "charge"
            extra_charge = current_hotel.hotel_extra_charges.active
              .includes(transaction_code: :transaction_code_taxes)
              .find_by(id: folio_transaction_params[:hotel_extra_charge_id])
            unless extra_charge
              @extra_charge_posting_error = true
              return ::Folios::Transactions::TransactionResult.failure("Select an available extra charge.")
            end


            if extra_charge.fixed? && extra_charge.nightly?
              scheduled = ::ExtraCharges::CreateForecasts.call(
                extra_charge: extra_charge,
                folio: folio,
                booking: @booking,
                user: current_user,
                starts_on: folio_transaction_params[:starts_on],
                ends_on: folio_transaction_params[:ends_on],
                unit_rate: folio_transaction_params[:unit_rate],
                expected_fingerprint: folio_transaction_params[:pricing_fingerprint],
                description: folio_transaction_params[:description],
                reference: folio_transaction_params[:reference],
                note: folio_transaction_params[:note]
              )
              unless scheduled.success?
                @extra_charge_posting_error = true
                @pricing_fingerprint = scheduled.quote&.fingerprint
                return ::Folios::Transactions::TransactionResult.failure(scheduled.error)
              end

              @extra_charge_scheduled = true

              return ::Folios::Transactions::TransactionResult.success(
                transaction: nil,
                transactions: [],
                tax_transactions: []
              )
            end

            quote = ::ExtraCharges::Quote.call(
              extra_charge: extra_charge,
              folio: folio,
              booking: @booking,
              requested_amount: folio_transaction_params[:amount],
              quantity: folio_transaction_params[:quantity],
              expected_fingerprint: folio_transaction_params[:pricing_fingerprint]
            )
            unless quote.success?
              @extra_charge_posting_error = true
              @amount = quote.amount
              @pricing_fingerprint = quote.fingerprint
              return ::Folios::Transactions::TransactionResult.failure(quote.error)
            end
          end

          options = posting_options
          options[:metadata] = options.fetch(:metadata, {}).merge(quote.metadata) if quote
          description = if extra_charge
            ::ExtraCharges::Description.call(
              extra_charge: extra_charge,
              currency: folio.currency,
              amount: quote.amount,
              calculated_amount: quote.calculated_amount,
              quantity: quote.quantity,
              base_amount: quote.base_amount,
              submitted_description: folio_transaction_params[:description]
            )
          else
            checkout_settlement? ? checkout_settlement_description : folio_transaction_params[:description]
          end
          return ::Folios::Payments::PostConfiguredPayment.call(
            folio: folio,
            user: current_user,
            payment_method_id: folio_transaction_params[:hotel_payment_method_id],
            base_amount: posting_amount,
            description: checkout_settlement? ? checkout_settlement_description : folio_transaction_params[:description],
            posting_date: folio_transaction_params[:posting_date],
            options: posting_options
          ) if payment_with_configured_method?

          ::Folios::Transactions::PostStaffTransaction.call(
            folio: folio,
            user: current_user,
            transaction_type: folio_transaction_params[:transaction_type],
            category: folio_transaction_params[:category],
            amount: quote&.amount || posting_amount,
            description: description,
            posting_date: folio_transaction_params[:posting_date],
            transaction_code_id: extra_charge&.transaction_code_id || folio_transaction_params[:transaction_code_id],
            options: options
          )
        end

        def render_transaction_error(error)
          @active_folio = posting_folio
          @open_folios = scoped_booking_folios.open.order(is_primary: :desc, folio_sequence: :asc, folio_number: :asc, id: :asc).to_a
          @transaction_type = requested_transaction_type
          @category = requested_category.presence
          @description = folio_transaction_params[:description]
          @transaction_error = error
          assign_form_config
          render :show, formats: :html, layout: false, status: :unprocessable_content
        end

        def build_extra_charge_config
          folios = @open_folios.presence || [ @active_folio ].compact
          @extra_charge_options.to_h do |extra_charge|
            bases = folios.to_h do |folio|
              preview = ::ExtraCharges::Quote.call(
                extra_charge: extra_charge,
                folio: folio,
                booking: @booking,
                quantity: 1,
                preview: true
              )
              [ folio.id.to_s, {
                amount: preview.amount&.to_d&.to_s("F"),
                base_amount: preview.base_amount&.to_d&.to_s("F"),
                quantity: preview.quantity&.to_d&.to_s("F"),
                fingerprint: preview.fingerprint
              } ]
            end
            [ extra_charge.id.to_s, {
              name: extra_charge.name,
              pricing_type: extra_charge.pricing_type,
              rate_value: extra_charge.rate_value&.to_d&.to_s("F"),
              charging_unit: extra_charge.charging_unit,
              allow_amount_override: extra_charge.allow_amount_override?,
              nightly: extra_charge.fixed? && extra_charge.nightly?,
              bases: bases
            } ]
          end
        end

        def build_payment_method_config
          @payment_method_options.to_h do |payment_method|
            extra_charge = payment_method.surcharge_extra_charge
            taxes = if extra_charge
              ::Folios::Routing::EffectiveTaxRules.call(booking: @booking, transaction_code: extra_charge.transaction_code)
                .select(&:enabled_for_posting?)
                .map { |rule| { name: rule.display_name, rate_type: rule.rate_type, amount: rule.amount.to_d.to_s("F") } }
            else
              []
            end
            [ payment_method.id.to_s, {
              name: payment_method.name,
              surcharge_posting_type: payment_method.surcharge_posting_type,
              surcharge_value: payment_method.surcharge_value&.to_d&.to_s("F"),
              taxes: taxes
            } ]
          end
        end


        def schedule_quote_json(result)
          {
            allowed_dates: result.allowed_dates.map(&:iso8601),
            starts_on: result.starts_on.iso8601,
            ends_on: result.ends_on.iso8601,
            unit_rate: result.unit_rate.to_s("F"),
            configured_rate: result.configured_rate.to_s("F"),
            base_total: result.base_total.to_s("F"),
            tax_total: result.tax_total.to_s("F"),
            grand_total: result.grand_total.to_s("F"),
            fingerprint: result.fingerprint,
            dates: result.dates.map do |row|
              row.merge(
                date: row[:date].iso8601,
                unit_rate: row[:unit_rate].to_s("F"),
                base_amount: row[:base_amount].to_s("F"),
                tax_total: row[:tax_total].to_s("F"),
                total: row[:total].to_s("F"),
                taxes: row[:taxes].map { |tax| tax.merge(amount: tax[:amount].to_s("F"), rate: tax[:rate].to_s("F")) }
              )
            end
          }
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
          options += %w[adjustment other] if current_user.has_permission?("post_folio_adjustments", hotel: current_hotel)
          options << "correction" if current_user.has_permission?("post_folio_corrections", hotel: current_hotel)
          options << "write_off" if current_user.has_permission?("post_folio_write_offs", hotel: current_hotel)
          options
        end

        def posting_options
          options = {}
          options[:require_transaction_code] = true if folio_transaction_params[:transaction_type].to_s == "charge"
          if folio_transaction_params[:transaction_type].to_s == "payment" && !refund_transaction?
            if folio_transaction_params[:hotel_payment_method_id].present?
              options[:hotel_payment_method_id] = folio_transaction_params[:hotel_payment_method_id]
            else
              options[:payment_source] = folio_transaction_params[:payment_source].to_s.strip
            end
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

        def payment_with_configured_method?
          folio_transaction_params[:transaction_type].to_s == "payment" &&
            !refund_transaction? && folio_transaction_params[:hotel_payment_method_id].present?
        end

        def folio_transaction_params
          @folio_transaction_params ||= params.fetch(:folio_transaction, ActionController::Parameters.new).permit(
            :transaction_type,
            :category,
            :transaction_code_id,
            :hotel_extra_charge_id,
            :hotel_discount_id,
            :discount_pricing_fingerprint,
            :quantity,
            :starts_on,
            :ends_on,
            :unit_rate,
            :pricing_fingerprint,
            :amount,
            :description,
            :posting_date,
            :reference,
            :note,
            :payment_source,
            :hotel_payment_method_id,
            :refund_source,
            :booking_folio_id,
            :routing_override_reason
          )
        end
      end
    end
  end
end
