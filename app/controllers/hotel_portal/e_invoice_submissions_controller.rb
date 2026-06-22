# frozen_string_literal: true

module HotelPortal
  class EInvoiceSubmissionsController < HotelPortal::BaseController
    before_action :set_hotel
    before_action :set_submission, only: [ :show, :refresh_status, :cancel ]
    before_action :set_booking, only: [ :create, :update_payment_receiver ]

    def index
      @submissions = current_hotel.e_invoice_submissions
                                  .includes(:booking)
                                  .order(created_at: :desc)
                                  .page(params[:page]).per(20)
    end

    def show
      @booking = @submission.booking
    end

    def create
      unless current_hotel.e_invoice_setting&.enabled?
        return redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
          alert: "E-invoice is turned off. Turn it on first in Settings → E-Invoice."
      end

      unless @booking.booking_folio&.status == "closed"
        return redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
          alert: "This booking must have a closed folio before you can send its e-invoice."
      end

      scenario = guest_document_scenario(@booking)
      guest_submissions = @booking.e_invoice_submissions.guest_facing.recent_first
      already_validated_submission = guest_submissions.valid.first

      if already_validated_submission
        return redirect_to hotel_e_invoice_submission_path(current_hotel, already_validated_submission),
          alert: "A guest e-invoice has already been successfully sent for this booking."
      end

      context = EInvoice::SubmissionContext.for(@booking)
      submission, already_processing = prepare_submission!(scenario, context)

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

      existing_sent_submission = @booking.e_invoice_submissions.guest_facing.where(status: %w[pending submitted valid]).recent_first.first

      if existing_sent_submission
        return redirect_to hotel_e_invoice_submission_path(current_hotel, existing_sent_submission),
          alert: "You cannot change who received the payment after the guest e-invoice has already been prepared or sent."
      end

      @booking.update!(fund_collector: receiver)

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

    def prepare_submission!(scenario, context)
      booking = @booking
      hotel = current_hotel

      EInvoiceSubmission.transaction do
        booking.with_lock do
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
  end
end
