# frozen_string_literal: true

module HotelPortal
  class TaxSettingsForm
    include ActiveModel::Model

    attr_reader :hotel, :params

    def initialize(hotel, params)
      @hotel = hotel
      @params = params
    end

    def save
      if hotel.update(tax_params)
        if (hotel.saved_changes.keys & %w[sst_enabled tourism_tax_enabled]).any?
          Financials::EnsureDefaultTransactionCodes.call(hotel)
        end
        true
      else
        false
      end
    end

    private

    def tax_params
      params.require(:hotel).permit(
        :tourism_tax_enabled, :tourism_tax_amount, :tourism_tax_registration_number,
        :sst_enabled, :sst_registration_number
      )
    end
  end
end
