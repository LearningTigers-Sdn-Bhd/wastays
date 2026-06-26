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
      hotel.update(tax_params)
    end

    private

    def tax_params
      params.require(:hotel).permit(:tourism_tax_enabled, :tourism_tax_amount, :sst_enabled)
    end
  end
end
