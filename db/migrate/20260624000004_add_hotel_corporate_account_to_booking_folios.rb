# frozen_string_literal: true

class AddHotelCorporateAccountToBookingFolios < ActiveRecord::Migration[8.0]
  def change
    add_reference :booking_folios, :hotel_corporate_account, foreign_key: true, index: true
  end
end
