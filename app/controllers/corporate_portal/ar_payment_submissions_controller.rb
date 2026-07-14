# frozen_string_literal: true

module CorporatePortal
  class ArPaymentSubmissionsController < CorporatePortal::BaseController
    def index
      @submissions = corporate_ar_payment_submissions
        .includes(:hotel, :ar_payment, hotel_corporate_account: :corporate_account)
        .order(created_at: :desc)
    end

    def new
      @ar_payment_submission = ArPaymentSubmission.new(
        currency: corporate_hotel_corporate_accounts.first&.credit_currency,
        payment_method: "bank_transfer",
        received_at: Date.current
      )
    end

    def create
      hotel_corporate_account = corporate_hotel_corporate_accounts.find_by(id: submission_params[:hotel_corporate_account_id])

      unless hotel_corporate_account
        return redirect_to new_corporate_ar_payment_submission_path, alert: "Select a hotel to submit this payment for."
      end

      @ar_payment_submission = hotel_corporate_account.ar_payment_submissions.build(
        submission_params.except(:hotel_corporate_account_id).merge(hotel: hotel_corporate_account.hotel, submitted_by: current_user)
      )

      if @ar_payment_submission.save
        redirect_to corporate_ar_payment_submissions_path, notice: "Payment submitted for hotel review."
      else
        flash.now[:alert] = @ar_payment_submission.errors.full_messages.to_sentence
        render :new, status: :unprocessable_content
      end
    end

    private

    def corporate_ar_payment_submissions
      ArPaymentSubmission.joins(:hotel_corporate_account)
        .where(hotel_corporate_accounts: { corporate_account_id: current_user.account_id })
    end

    def corporate_hotel_corporate_accounts
      @corporate_hotel_corporate_accounts ||= current_user.account.hotel_corporate_accounts.active.includes(:hotel)
    end
    helper_method :corporate_hotel_corporate_accounts

    def submission_params
      params.require(:ar_payment_submission).permit(:hotel_corporate_account_id, :amount, :currency, :reference_number, :received_at, :payment_method, :notes, :slip)
    end
  end
end
