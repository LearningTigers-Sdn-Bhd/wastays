# frozen_string_literal: true

module HotelPortal
  class EInvoiceSubmissionsController < HotelPortal::BaseController
    before_action :set_hotel
    before_action :set_submission, only: [ :show, :pdf, :refresh_status, :cancel, :retry ]
    before_action :set_booking, only: [ :create, :update_payment_receiver ]

    def index
      @submissions = current_hotel.e_invoice_submissions
                                  .includes(:booking)
                                  .order(created_at: :desc)
                                  .page(params[:page]).per(20)
      @setting = current_hotel.e_invoice_setting || current_hotel.build_e_invoice_setting
      all_submissions = current_hotel.e_invoice_submissions
      @summary_counts = {
        pending: all_submissions.where(status: %w[pending submitted]).count,
        rejected: all_submissions.where(status: "invalid").count,
        valid: all_submissions.where(status: "valid").count,
        guest_requested_attention: all_submissions.where(status: "invalid", requested_by_guest: true).count
      }
      @missing_config = missing_e_invoice_config(@setting)
    end

    def show
      @booking = @submission.booking
    end

    def pdf
      pdf_bytes = EInvoicePdfService.new(@submission.booking, submission: @submission).generate
      send_data pdf_bytes,
        filename: "wastays-e-invoice-#{@submission.internal_id || @submission.booking.confirmation_token}.pdf",
        type: "application/pdf",
        disposition: "inline"
    end

    def create
      requested_by_guest = ActiveModel::Type::Boolean.new.cast(params[:requested_by_guest])

      unless current_hotel.e_invoice_setting&.enabled?
        return redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
          alert: "E-invoice is turned off. Turn it on first in Settings → E-Invoice."
      end

      unless @booking.payment_concluded?
        return redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
          alert: "This booking's payment has not been fully concluded yet."
      end

      # Policy: Unrequested low-value bookings (< RM10,000) should only be
      # handled through consolidated monthly submission, not individual manual submission.
      # Hotel can still manually submit if requested_by_guest is true or amount >= RM10,000.
      if unrequested_low_value_booking?(@booking, requested_by_guest: requested_by_guest)
        return redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
          alert: "This booking is below RM10,000 and was not requested by the guest. " \
                "It will be included in the monthly consolidated submission."
      end

      scenario = guest_document_scenario(@booking)
      guest_submissions = @booking.e_invoice_submissions.guest_facing.recent_first
      already_validated_submission = guest_submissions.valid.first

      if already_validated_submission
        return redirect_to hotel_e_invoice_submission_path(current_hotel, already_validated_submission),
          alert: "A guest e-invoice has already been successfully sent for this booking."
      end

      context = EInvoice::SubmissionContext.for(@booking)
      submission, already_processing = prepare_submission!(scenario, context, requested_by_guest: requested_by_guest)

      if already_processing
        return redirect_to hotel_e_invoice_submission_path(current_hotel, submission),
          alert: "This e-invoice is already being prepared or has already been sent to LHDN."
      end

      EInvoice::SubmitJob.perform_later(submission.id)

      redirect_to hotel_e_invoice_submission_path(current_hotel, submission),
        notice: "E-invoice is being prepared and will be sent to LHDN shortly."
    rescue EInvoice::SubmissionContext::ConfigurationError => e
      redirect_back fallback_location: hotel_folio_path(current_hotel, @booking), alert: e.message
    end

    HIGH_VALUE_THRESHOLD = 10_000

    def unrequested_low_value_booking?(booking, requested_by_guest: false)
      return false if booking.total_amount.to_d >= HIGH_VALUE_THRESHOLD
      return false if requested_by_guest
      return false if booking.e_invoice_submissions.guest_facing.where(requested_by_guest: true).exists?

      true
    end

    def update_payment_receiver
      unless current_hotel.e_invoice_setting&.enabled?
        return redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
          alert: "E-invoice is turned off. Turn it on first in Settings → E-Invoice."
      end

      receiver = params.require(:booking).permit(:fund_collector)[:fund_collector]

      unless %w[wastays hotel].include?(receiver)
        return redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
          alert: "Please choose whether WAStays or the hotel received the guest payment."
      end

      # Check for non-consolidated or guest-requested submissions - these are real e-invoices
      # and we should NOT allow payment receiver changes
      blocking_submission = @booking.e_invoice_submissions.guest_facing
        .where("consolidated = ? OR requested_by_guest = ?", false, true)
        .where(status: %w[pending submitted valid])
        .first

      if blocking_submission
        return redirect_to hotel_e_invoice_submission_path(current_hotel, blocking_submission),
          alert: "You cannot change who received the payment after the e-invoice process has started."
      end

      # Handle existing consolidated unrequested pending placeholders when receiver changes
      existing_consolidated = @booking.e_invoice_submissions.guest_facing
        .where(status: "pending", consolidated: true, requested_by_guest: false)
        .first

      old_receiver = @booking.resolved_fund_collector

      # Only handle placeholder if receiver actually changes and affects scenario
      if existing_consolidated && receiver != old_receiver
        scenario_for_receiver = receiver == "hotel" ? "hotel_intermediary_guest_invoice" : "guest_invoice"
        current_scenario = existing_consolidated.document_scenario

        # If scenario would change, cancel the old placeholder
        if scenario_for_receiver != current_scenario
          existing_consolidated.update!(status: "cancelled", error_details: { receiver_changed: true })
          # New placeholder will be created by AutoIssueJob if needed
        end
      end

      @booking.update!(fund_collector: receiver)

      if @booking.total_amount.to_d < HIGH_VALUE_THRESHOLD
        @booking.create_pending_consolidated_submission!
      end

      redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
        notice: "Saved. The system will now treat this booking as paid to #{receiver == "hotel" ? "the hotel" : "WAStays"}."
    end

    def refresh_status
      result = EInvoice::RefreshStatus.call(@submission)

      if result[:success]
        redirect_to hotel_e_invoice_submission_path(current_hotel, @submission),
          notice: "Status refreshed: #{@submission.reload.status_label}."
      else
        redirect_to hotel_e_invoice_submission_path(current_hotel, @submission),
          alert: result[:error]
      end
    end

    def cancel
      result = EInvoice::Cancel.call(@submission, reason: params[:reason])

      if result[:success]
        redirect_to hotel_e_invoice_submission_path(current_hotel, @submission),
          notice: result[:message]
      else
        redirect_to hotel_e_invoice_submission_path(current_hotel, @submission),
          alert: result[:error]
      end
    end

    def retry
      unless @submission.retryable?
        return redirect_to hotel_e_invoice_submission_path(current_hotel, @submission),
          alert: "This e-invoice cannot be retried right now."
      end

      EInvoice::SubmitJob.perform_later(@submission.id)

      redirect_to hotel_e_invoice_submission_path(current_hotel, @submission),
        notice: "E-invoice retry queued. We will try sending it to LHDN again shortly."
    end

    private

    def set_hotel
      @hotel = current_hotel
    end

    def set_booking
      @booking = current_hotel.bookings.find(params[:booking_id])
    end

    def set_submission
      @submission = current_hotel.e_invoice_submissions.find(params[:id])
    end

    def guest_document_scenario(booking)
      booking.direct_hotel_payment? ? "hotel_intermediary_guest_invoice" : "guest_invoice"
    end

    def prepare_submission!(scenario, context, requested_by_guest: false)
      requested_by_guest = !!requested_by_guest
      booking = @booking
      hotel = current_hotel

      EInvoiceSubmission.transaction do
        booking.with_lock do
          if requested_by_guest
            booking.e_invoice_submissions.guest_facing
              .where(status: "pending", consolidated: true, requested_by_guest: false)
              .update_all(status: "cancelled", error_details: { converted_to_individual: true })
          end

          submission = booking.e_invoice_submissions.where.not(status: "cancelled").find_or_initialize_by(
            booking_id: booking.id,
            document_scenario: scenario
          )

          return [ submission, true ] if submission.persisted? && submission.status.in?(%w[pending submitted])

          submission.assign_attributes(
            hotel: hotel,
            document_type: "01",
            document_scenario: scenario,
            submission_mode: context.submission_mode,
            fund_collector: context.fund_collector,
            supplier_name: context.supplier_name,
            supplier_tin: context.supplier_tin,
            represented_taxpayer_tin: context.represented_taxpayer_tin,
            status: "pending",
            consolidated: false,
            requested_by_guest: requested_by_guest,
            requested_at: requested_by_guest ? Time.current : nil,
            payment_concluded_at: booking.payment_concluded_at,
            uuid: nil,
            long_id: nil,
            submission_uid: nil,
            submitted_at: nil,
            validated_at: nil,
            cancelled_at: nil,
            raw_response: {},
            error_details: {}
          )
          submission.save!
          [ submission, false ]
        end
      end
    rescue ActiveRecord::RecordNotUnique
      [
        booking.e_invoice_submissions.where.not(status: "cancelled").find_by!(
        booking_id: booking.id,
        document_scenario: scenario
        ),
        true
      ]
    end

    def missing_e_invoice_config(setting)
      return [] unless setting.enabled? && setting.intermediary_enabled?

      checks = [
        [ "Hotel tax number (TIN)", setting.hotel_tin.present? ],
        [ "Business registration number (BRN / SSM)", setting.hotel_brn.present? ],
        [ "MSIC code", setting.supplier_msic_code.present? ],
        [ "Business description", setting.supplier_business_description.present? ],
        [ "Hotel contact phone", setting.supplier_contact_phone.present? ],
        [ "Hotel contact email", setting.supplier_contact_email.present? ],
        [ "Address line 1", setting.supplier_address_line1.present? ],
        [ "City", setting.supplier_city.present? ],
        [ "Postal code", setting.supplier_postal_code.present? ],
        [ "State code", setting.supplier_state_code.present? ]
      ]

      checks.reject { |_, ready| ready }.map(&:first)
    end
  end
end
