# frozen_string_literal: true

module HotelPortal
  class BankingDetailsForm
    include ActiveModel::Model

    attr_reader :account, :params

    def initialize(account, params)
      @account = account
      @params = params
    end

    def save
      account.update(account_params)
    end

    private

    def account_params
      params.require(:account).permit(
        banking_detail_attributes: [ :id, :account_holder_name, :bank_name, :account_number ]
      )
    end
  end
end
