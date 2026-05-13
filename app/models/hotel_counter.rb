# frozen_string_literal: true

class HotelCounter < ApplicationRecord
  belongs_to :hotel

  TYPES = %w[reservation folio receipt guest_registration].freeze

  validates :counter_type, inclusion: { in: TYPES }

  # Returns the next sequential number for the given hotel + type.
  # Uses a DB advisory lock to prevent race conditions.
  def self.increment!(hotel:, type:)
    counter = find_or_create_by!(hotel: hotel, counter_type: type)
    counter.with_lock do
      counter.increment!(:last_value)
    end
    counter.last_value
  end
end
