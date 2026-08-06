# frozen_string_literal: true

class AddNoShowReviewBusinessDateToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :no_show_review_business_date, :date
    add_index :bookings, [ :hotel_id, :status, :no_show_review_business_date ],
      name: "index_bookings_on_hotel_status_no_show_review_date"
  end
end
