# frozen_string_literal: true

module HotelPortal
  class FolioTransactionsController < BaseController
    include OffcanvasTransactionCompletion

    before_action :set_booking

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

    def new
      @active_folio = sheet_folio
      return redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "folio_operations"), alert: "Booking has no open folio." if @active_folio.blank?

      @open_folios = @booking.booking_folios.open.order(is_primary: :desc, folio_sequence: :asc, folio_number: :asc, id: :asc).to_a
      @transaction_type = params[:transaction_type].to_s
      @category = params[:category].presence
      @amount = params[:amount]
      @redirect_to_folio = params[:redirect_to_folio] == "true"
      @redirect_to_checkout = params[:redirect_to_checkout] == "true"
      @folio_origin = params[:folio_origin].presence
      assign_sheet_config
      return redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "folio_operations", folio_id: @active_folio.id), alert: "You do not have permission to post this folio transaction." unless allowed_to_view_posting_sheet?

      render "hotel_portal/folios/transactions/offcanvas"
    end

    def create
      target_folio = posting_folio

      unless target_folio
        message = folio_transaction_params[:booking_folio_id].present? ? "Selected folio is not available for this booking." : "Booking has no folio."
        return redirect_after_post(alert: message)
      end
      return redirect_after_post(alert: "You do not have permission to post this folio transaction.") unless allowed_to_post_folio_transaction?

      result = ::Folios::PostStaffTransaction.call(
        folio: target_folio,
        user: current_user,
        transaction_type: folio_transaction_params[:transaction_type],
        category: folio_transaction_params[:category],
        amount: folio_transaction_params[:amount],
        description: folio_transaction_params[:description],
        posting_date: folio_transaction_params[:posting_date],
        transaction_code_id: folio_transaction_params[:transaction_code_id],
        options: posting_options
      )

      if result.success?
        redirect_after_post(notice: "Folio transaction posted.", active_folio_id: target_folio.id)
      else
        redirect_after_post(alert: result.error, active_folio_id: target_folio.id)
      end
    end

    def move_form
      return redirect_after_post(alert: "You do not have permission to move folio transactions.") unless allowed_to_manage_folio_movements?

      @transaction = booking_transaction_scope.includes(:transaction_code).find(params[:id])
      @source_folio = @transaction.booking_folio
      @open_folios = @booking.booking_folios.open.order(is_primary: :desc, folio_sequence: :asc, folio_number: :asc, id: :asc).to_a
      @target_folios = @open_folios.reject { |folio| folio.id == @source_folio.id }
      @tax_transactions = attached_tax_transactions(@transaction)
      @folio_origin = params[:folio_origin].presence || params[:origin].presence

      render "hotel_portal/folios/transactions/move/offcanvas"
    end

    def reverse
      unless @booking.booking_folio
        return redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "folio_operations"), alert: "Booking has no folio."
      end

      transaction = booking_transaction_scope.find(params[:id])
      policy = ::Folios::TransactionActionPolicy.new(
        transaction: transaction,
        user: current_user,
        posting_date: current_hotel.current_business_date
      )
      return redirect_after_post(alert: policy.reverse_error) unless policy.reverse_allowed?

      result = ::Folios::ReverseTransaction.call(
        transaction: transaction,
        user: current_user,
        correction_reason: reversal_params[:correction_reason],
        correction_note: reversal_params[:correction_note],
        posting_date: current_hotel.current_business_date
      )

      if result.success?
        redirect_after_post(notice: "Folio transaction reversed.", active_folio_id: transaction.booking_folio_id)
      else
        redirect_after_post(alert: result.error, active_folio_id: transaction.booking_folio_id)
      end
    end

    def move
      transaction = booking_transaction_scope.find(params[:id])
      target_folio = @booking.booking_folios.find(folio_operation_params[:target_folio_id])
      result = ::Folios::MoveTransaction.call(
        transaction: transaction,
        target_folio: target_folio,
        user: current_user,
        reason: folio_operation_params[:reason],
        posting_date: current_hotel.current_business_date,
        tax_routes: tax_route_params
      )

      if result.success?
        redirect_after_post(notice: "Folio transaction moved.", active_folio_id: target_folio.id)
      else
        redirect_after_post(alert: result.error, active_folio_id: transaction.booking_folio_id)
      end
    end

    def split
      transaction = booking_transaction_scope.find(params[:id])
      target_folio = @booking.booking_folios.find(folio_operation_params[:target_folio_id])
      result = ::Folios::SplitTransaction.call(
        transaction: transaction,
        target_folio: target_folio,
        user: current_user,
        reason: folio_operation_params[:reason],
        amount: folio_operation_params[:amount],
        percent: folio_operation_params[:percent],
        posting_date: current_hotel.current_business_date
      )

      if result.success?
        redirect_after_post(notice: "Folio transaction split.", active_folio_id: target_folio.id)
      else
        redirect_after_post(alert: result.error, active_folio_id: transaction.booking_folio_id)
      end
    end

    private

    def redirect_after_post(options = {})
      active_folio_id = options.delete(:active_folio_id)
      destination = if params[:redirect_to_checkout] == "true"
        hotel_booking_transaction_check_out_path(current_hotel, @booking)
      elsif params[:folio_origin] == "booking_control_panel"
        hotel_booking_control_panel_path(current_hotel, @booking, tab: "folio_operations", folio_id: active_folio_id)
      elsif params[:redirect_to_folio] == "true"
        hotel_booking_control_panel_path(current_hotel, @booking, tab: "folio_operations", folio_id: active_folio_id)
      else
        hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")
      end

      respond_to do |format|
        format.turbo_stream do
          flash[:notice] = options[:notice] if options[:notice].present?
          flash[:alert] = options[:alert] if options[:alert].present?
          render_offcanvas_completion(destination)
        end
        format.html { redirect_to destination, options }
      end
    end

    def folio_origin_params
      params[:folio_origin] == "folios" ? { origin: "folios" } : {}
    end

    def set_booking
      @booking = current_hotel.bookings.find(params[:booking_id] || params[:folio_booking_id])
    end

    def folio_transaction_params
      params.require(:folio_transaction).permit(
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

    def sheet_folio
      selected = scoped_booking_folios.open.find_by(id: params[:active_folio_id]) if params[:active_folio_id].present?
      selected || @booking.booking_folio&.then { |folio| folio.open? ? folio : nil } || scoped_booking_folios.open.order(:folio_sequence, :folio_number, :id).first
    end

    def posting_folio
      if folio_transaction_params[:booking_folio_id].present?
        scoped_booking_folios.open.find_by(id: folio_transaction_params[:booking_folio_id])
      else
        @booking.booking_folio
      end
    end

    def scoped_booking_folios
      @booking.booking_folios.where(hotel_id: current_hotel.id)
    end

    def assign_sheet_config
      case [ @transaction_type, @category.to_s ]
      when [ "payment", "refund" ]
        @sheet_title = "Issue Refund"
        @sheet_description = "Enter a positive refund amount. It will be recorded as a negative refund payment."
        @refund_source_options = ::Folios::RefundSource.options
        @signed_amount = false
        @submit_label = "Issue Refund"
      when [ "payment", "" ]
        @sheet_title = "Post Payment"
        @sheet_description = "Record a staff-posted payment against the selected folio."
        @payment_source_options = ::Folios::PaymentSource.options
        @signed_amount = false
        @submit_label = "Post Payment"
      when [ "charge", "" ]
        @sheet_title = "Add Charge"
        @sheet_description = "Record a manual charge using a transaction code preset."
        @transaction_code_options = current_hotel.transaction_codes.active.charge.order(:code)
        @signed_amount = false
        @submit_label = "Add Charge"
      when [ "adjustment", "" ]
        @sheet_title = "Post Adjustment"
        @sheet_description = "Record an authorized adjustment, correction, discount, write-off, or other adjustment."
        @category_options = adjustment_category_options
        @signed_amount = true
        @submit_label = "Post Adjustment"
      else
        @sheet_title = "Post Folio Transaction"
        @sheet_description = "Record a folio transaction against the selected folio."
        @category_options = []
        @signed_amount = false
        @submit_label = "Post Transaction"
      end
    end

    def adjustment_category_options
      options = []
      options += %w[adjustment discount other] if current_user.has_permission?("post_folio_adjustments", hotel: current_hotel)
      options << "correction" if current_user.has_permission?("post_folio_corrections", hotel: current_hotel)
      options << "write_off" if current_user.has_permission?("post_folio_write_offs", hotel: current_hotel)
      options
    end

    def allowed_to_view_posting_sheet?
      case [ @transaction_type, @category.to_s ]
      when [ "payment", "refund" ]
        current_user.has_permission?("execute_folio_refunds", hotel: current_hotel)
      when [ "payment", "" ]
        current_user.has_permission?("post_folio_payments", hotel: current_hotel)
      when [ "charge", "" ]
        current_user.has_permission?("post_folio_charges", hotel: current_hotel)
      when [ "adjustment", "" ]
        adjustment_category_options.any?
      else
        false
      end
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

    def allowed_to_post_folio_transaction?
      slug = posting_permission_slug
      slug.present? && current_user.has_permission?(slug, hotel: current_hotel)
    end

    def allowed_to_manage_folio_movements?
      current_user.respond_to?(:superadmin?) && current_user.superadmin? ||
        current_user.has_permission?("manage_folio_movements", hotel: current_hotel)
    end

    def posting_permission_slug
      type = folio_transaction_params[:transaction_type].to_s
      category = folio_transaction_params[:category].to_s
      return "execute_folio_refunds" if type == "payment" && category == "refund"
      return "post_folio_payments" if type == "payment" && folio_transaction_params[:payment_source].present?
      return "post_folio_payments" if type == "payment" && category != "refund"
      return "post_folio_charges" if type == "charge"

      FOLIO_POSTING_PERMISSIONS.fetch([ type, category ], nil)
    end

    def reversal_params
      params.require(:folio_transaction).permit(
        :correction_reason,
        :correction_note
      )
    end

    def folio_operation_params
      params.require(:folio_operation).permit(:target_folio_id, :reason, :amount, :percent, tax_routes: [ :transaction_id, :target_folio_id ])
    end

    def tax_route_params
      folio_operation_params[:tax_routes].to_h.values.each_with_object({}) do |attributes, routes|
        attributes = attributes.to_h.with_indifferent_access
        transaction_id = attributes[:transaction_id].presence
        next if transaction_id.blank?

        routes[transaction_id.to_s] = attributes[:target_folio_id].presence
      end
    end

    def booking_transaction_scope
      FolioTransaction.joins(:booking_folio).where(booking_folios: { booking_id: @booking.id, hotel_id: current_hotel.id })
    end

    def generated_tax_children(transaction)
      attached_tax_transactions(transaction)
    end

    def attached_tax_transactions(transaction)
      ::Folios::AttachedTaxTransactions.call(transaction)
    end
  end
end
