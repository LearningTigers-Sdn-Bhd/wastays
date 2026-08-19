# frozen_string_literal: true

module EInvoice
  class SubmissionContext
    class ConfigurationError < StandardError; end

    Context = Struct.new(
      :booking,
      :hotel,
      :setting,
      :fund_collector,
      :submission_mode,
      :supplier_name,
      :supplier_tin,
      :represented_taxpayer_tin,
      keyword_init: true
    ) do
      def intermediary?
        submission_mode == "intermediary"
      end
    end

    def self.for(booking, document_scenario: nil)
      new(booking, document_scenario: document_scenario).for_booking
    end

    def self.for_submission(submission)
      Context.new(
        booking: submission.booking,
        hotel: submission.hotel,
        setting: submission.hotel.e_invoice_setting,
        fund_collector: submission.fund_collector,
        submission_mode: submission.submission_mode,
        supplier_name: submission.supplier_name,
        supplier_tin: submission.supplier_tin,
        represented_taxpayer_tin: submission.represented_taxpayer_tin
      )
    end

    def initialize(booking, document_scenario: nil)
      @booking = booking
      @hotel = booking.hotel
      @setting = @hotel.e_invoice_setting
      @document_scenario = document_scenario
    end

    # WAStays is under the RM1m threshold and so does not issue e-invoices as a
    # supplier. The hotel is the supplier on every guest e-invoice and files
    # under its own LHDN registration; WAStays only operates the submission.
    #
    # Because the hotel files either way, who collected the guest's money no
    # longer decides who issues. fund_collector still drives payouts, but it no
    # longer blocks a guest e-invoice.
    #
    # The intermediary path stays for when WAStays crosses the threshold and
    # registers to file on a hotel's behalf.
    def for_booking
      return payout_self_billed_context if @document_scenario == "payout_self_billed_invoice"

      raise ConfigurationError, "Hotel e-invoice settings have not been set up yet." unless @setting

      # The scenario on the record says which kind of filing this is; the flag
      # only says whether the hotel has opted into WAStays filing for them.
      return intermediary_context if @document_scenario == "hotel_intermediary_guest_invoice"

      ensure_hotel_can_file!

      Context.new(
        booking: @booking,
        hotel: @hotel,
        setting: @setting,
        fund_collector: @booking.resolved_fund_collector,
        submission_mode: "taxpayer",
        supplier_name: @setting.supplier_name,
        supplier_tin: @setting.hotel_tin,
        represented_taxpayer_tin: nil
      )
    end

    private

    def payout_self_billed_context
      raise ConfigurationError, "Hotel e-invoice settings have not been set up yet." unless @setting
      raise ConfigurationError, "Complete the hotel's e-invoice details before generating hotel payout records." unless @setting.supplier_profile_ready?

      creds = Rails.application.credentials.myinvois.to_h
      tin = creds[:tin].to_s.presence || raise(ConfigurationError, "WAStays e-invoice account details are incomplete.")

      Context.new(
        booking: @booking,
        hotel: @hotel,
        setting: @setting,
        fund_collector: "wastays",
        submission_mode: "taxpayer",
        supplier_name: @setting.supplier_name,
        supplier_tin: @setting.hotel_tin,
        represented_taxpayer_tin: nil
      )
    end

    def intermediary_context
      ensure_intermediary_ready!

      Context.new(
        booking: @booking,
        hotel: @hotel,
        setting: @setting,
        fund_collector: @booking.resolved_fund_collector,
        submission_mode: "intermediary",
        supplier_name: @setting.supplier_name,
        supplier_tin: @setting.hotel_tin,
        represented_taxpayer_tin: @setting.hotel_tin
      )
    end

    def ensure_hotel_can_file!
      unless @setting.api_credentials_ready?
        raise ConfigurationError,
          "This hotel has not connected its LHDN account yet. Add the hotel's MyInvois credentials in Settings > E-Invoice."
      end

      return if @setting.supplier_profile_ready?

      raise ConfigurationError,
        "Complete the hotel's tax, business and contact details in Settings > E-Invoice before filing."
    end

    def ensure_intermediary_ready!
      return if @setting.intermediary_ready?

      raise ConfigurationError,
        "Hotel-issued e-invoices are not ready yet. Turn on hotel-issued e-invoices and complete the hotel's tax, business, and contact details first."
    end
  end
end
