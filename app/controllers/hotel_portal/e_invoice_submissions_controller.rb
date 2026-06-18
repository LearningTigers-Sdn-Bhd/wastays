# frozen_string_literal: true

module HotelPortal
  class EInvoiceSubmissionsController < HotelPortal::BaseController
    before_action :set_hotel
    before_action :set_submission, only: [ :show, :refresh_status, :cancel ]

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
      @booking = current_hotel.bookings.find(params[:booking_id])

      unless current_hotel.e_invoice_setting&.enabled?
        return redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
          alert: "E-Invoice is not enabled. Configure it in Settings → E-Invoice."
      end

      unless @booking.booking_folio&.status == "closed"
        return redirect_back fallback_location: hotel_folio_path(current_hotel, @booking),
          alert: "Booking does not have a closed folio."
      end

      if @booking.e_invoice_submission&.validated?
        return redirect_to hotel_e_invoice_submission_path(current_hotel, @booking.e_invoice_submission),
          alert: "E-Invoice has already been submitted and validated."
      end

      submission = @booking.e_invoice_submission || EInvoiceSubmission.new(
        hotel:         current_hotel,
        booking:       @booking,
        document_type: "01"
      )

      submission.assign_attributes(
        status:         "pending",
        uuid:           nil,
        long_id:        nil,
        submission_uid: nil,
        submitted_at:   nil,
        validated_at:   nil,
        cancelled_at:   nil,
        raw_response:   {},
        error_details:  {}
      )
      submission.save!

      EInvoice::SubmitJob.perform_later(@booking.id)

      redirect_to hotel_e_invoice_submission_path(current_hotel, submission),
        notice: "E-Invoice submission queued. It will be sent to MyInvois shortly."
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

    def set_submission
      @submission = current_hotel.e_invoice_submissions.find(params[:id])
    end
  end
end
