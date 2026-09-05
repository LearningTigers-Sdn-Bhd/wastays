# frozen_string_literal: true

module EInvoice
  # Asks LHDN whether a TIN actually belongs to the identity given alongside it.
  #
  # A TIN is typed or read off a document by a human. One wrong digit is
  # accepted silently today, filed into an e-invoice, and rejected by LHDN days
  # later - by which time the guest has checked out and someone has to chase
  # them to correct a tax document. Checking at the point of capture turns that
  # into a correction while the guest is still at the desk.
  #
  # This is advisory on purpose. LHDN being slow or unreachable must never stop
  # a check-in, so anything other than a clear "no" is reported as unknown.
  class ValidateTin
    ID_TYPES = {
      "ic" => "NRIC",
      "nric" => "NRIC",
      "passport" => "PASSPORT",
      "army" => "ARMY",
      "brn" => "BRN"
    }.freeze
    DEFAULT_ID_TYPE = "BRN"

    Result = Struct.new(:status, :message, keyword_init: true) do
      def valid? = status == :valid
      def invalid? = status == :invalid
      def unknown? = status == :unknown
    end

    def self.call(...) = new(...).call

    def initialize(tin:, id_value:, document_type: nil, passport_number: nil, country: nil, setting: nil)
      @tin = tin.to_s.strip
      @identity = EInvoice::GuestIdentityResolver.from_values(
        document_type: document_type,
        document_number: id_value,
        passport_number: passport_number,
        country: country
      )
      @id_value = @identity.document_number.to_s.gsub(/[^A-Za-z0-9]/, "")
      @document_type = @identity.document_type
      @setting = setting
    end

    def call
      return unknown("Enter a tax number to check it.") if @tin.blank?
      if @identity.missing_passport?
        return unknown("Enter the guest's passport number before issuing an individual e-invoice.")
      end
      return unknown("Enter the guest's IC, passport or business registration number to check the tax number.") if @id_value.blank?
      return unknown("Connect this hotel's LHDN account before checking tax numbers.") unless checkable?

      response = client.validate_tin(@tin, id_type: id_type, id_value: @id_value)
      interpret(response)
    rescue MyInvois::Client::ApiError => e
      # A 404 from this endpoint is LHDN's way of saying the pairing is wrong,
      # which is a real answer. Anything else says nothing about the TIN.
      return invalid_result if e.code.to_s == "404"

      Rails.logger.info("[ValidateTin] #{e.class}: #{e.message}")
      unknown("Could not reach LHDN to check this tax number. It will be checked again when the e-invoice is filed.")
    rescue StandardError => e
      Rails.logger.error("[ValidateTin] #{e.class}: #{e.message}")
      unknown("Could not check this tax number right now.")
    end

    private

    def checkable?
      MyInvois::ClientFactory.mock?(@setting) || @setting&.api_credentials_ready?
    end

    def client
      MyInvois::ClientFactory.build(mode: :taxpayer, setting: @setting)
    end

    def id_type
      ID_TYPES.fetch(@document_type.to_s.downcase, DEFAULT_ID_TYPE)
    end

    # LHDN's real preprod answer to this endpoint is a 200 with an empty body
    # for a match, and a 404 (already turned into invalid_result above) for a
    # mismatch - there is no "status" field on a genuine response. Reaching
    # here at all means the client didn't raise, i.e. LHDN said yes. An
    # explicit "invalid" status is kept as a fallback in case a future or
    # differently-configured endpoint ever sends one.
    def interpret(response)
      status = response.is_a?(Hash) ? response["status"].to_s.downcase : ""
      return invalid_result if status == "invalid"

      Result.new(status: :valid, message: "Tax number matches this #{id_type_label}.")
    end

    def invalid_result
      Result.new(
        status: :invalid,
        message: "LHDN does not recognise this tax number for the #{id_type_label} given. Check both before continuing."
      )
    end

    def unknown(message)
      Result.new(status: :unknown, message: message)
    end

    def id_type_label
      case id_type
      when "NRIC" then "IC number"
      when "PASSPORT" then "passport number"
      when "ARMY" then "army number"
      else "business registration number"
      end
    end
  end
end
