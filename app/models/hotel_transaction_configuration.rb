# frozen_string_literal: true

class HotelTransactionConfiguration < ApplicationRecord
  ROOM_REVENUE_TAX_RULE_APPLICATIONS = {
    new_bookings_only: "new_bookings_only",
    open_folio_forecasts: "open_folio_forecasts"
  }.freeze

  belongs_to :hotel

  enum :room_revenue_tax_rule_application, ROOM_REVENUE_TAX_RULE_APPLICATIONS, validate: true

  validates :hotel_id, uniqueness: true
end
