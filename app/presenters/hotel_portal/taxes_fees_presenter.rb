# frozen_string_literal: true

module HotelPortal
  class TaxesFeesPresenter
    attr_reader :hotel, :current_user, :hotel_tax, :primary_edit

    def initialize(hotel:, current_user:, hotel_tax: nil, primary_edit: nil)
      @hotel = hotel
      @current_user = current_user
      @hotel_tax = hotel_tax
      @primary_edit = primary_edit
    end

    def hotel_taxes
      @hotel_taxes ||= hotel.hotel_taxes.order(:name)
    end

    def editing_tourism_tax?
      primary_edit == "tourism_tax"
    end

    def new_hotel_tax
      @new_hotel_tax ||= hotel_tax || hotel.hotel_taxes.build
    end
  end
end
