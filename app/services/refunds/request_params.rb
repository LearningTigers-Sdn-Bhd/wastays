# frozen_string_literal: true

module Refunds
  # The refund form's params, as Refunds::SubmitRequest reads them.
  #
  # A guest whose bank is not listed picks "Other bank" and types the name in
  # other_bank_name. The request stores the name, never "Other".
  class RequestParams
    FIELDS = %i[reason refund_amount bank_name other_bank_name account_holder_name account_number account_type].freeze

    def initialize(params)
      @params = params
    end

    def call
      permitted = @params.fetch(:refund_request, {}).permit(*FIELDS)
      other_name = permitted.delete(:other_bank_name)
      permitted[:bank_name] = other_name.to_s.strip if permitted[:bank_name] == BankCatalog::OTHER
      permitted
    end
  end
end
