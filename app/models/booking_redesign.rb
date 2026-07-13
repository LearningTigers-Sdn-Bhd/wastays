# frozen_string_literal: true

module BookingRedesign
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("BOOKING_REDESIGN_BACKEND_ENABLED", false))
  end
end
