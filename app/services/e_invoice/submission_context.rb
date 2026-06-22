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

    def for_booking
      return payout_self_billed_context if @document_scenario == "payout_self_billed_invoice"

      collector = @booking.fund_collector == "unknown" ? "unknown" : @booking.resolved_fund_collector

      if collector == "unknown"
        raise ConfigurationError,
          "Please confirm whether the guest paid WAStays or paid the hotel directly before sending this e-invoice."
      end

      if collector == "hotel"
        raise ConfigurationError, "Hotel e-invoice settings have not been set up yet." unless @setting

        ensure_intermediary_ready!

        Context.new(
          booking: @booking,
          hotel: @hotel,
          setting: @setting,
          fund_collector: collector,
          submission_mode: "intermediary",
          supplier_name: @setting.supplier_name,
          supplier_tin: @setting.hotel_tin,
          represented_taxpayer_tin: @setting.hotel_tin
        )
      else
        creds = Rails.application.credentials.myinvois.to_h
        tin = creds[:tin].to_s.presence || raise(ConfigurationError, "WAStays e-invoice account details are incomplete.")
        name = creds[:name].to_s.presence || "Jesselton Pixel Sdn Bhd"

        Context.new(
          booking: @booking,
          hotel: @hotel,
          setting: @setting,
          fund_collector: collector,
          submission_mode: "taxpayer",
          supplier_name: name,
          supplier_tin: tin,
          represented_taxpayer_tin: nil
        )
      end
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

    def ensure_intermediary_ready!
      return if @setting.intermediary_ready?

      raise ConfigurationError,
        "Hotel-issued e-invoices are not ready yet. Turn on hotel-issued e-invoices and complete the hotel's tax, business, and contact details first."
    end
  end
end
