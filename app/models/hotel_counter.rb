# frozen_string_literal: true

class HotelCounter < ApplicationRecord
  belongs_to :hotel

  TYPES = %w[reservation folio receipt guest_registration invoice ar_invoice tourism_tax_voucher].freeze

  validates :counter_type, inclusion: { in: TYPES }

  # Returns the next sequential number for the given hotel + type.
  # Uses a row lock to prevent race conditions.
  #
  # `floor` guards against a stale counter: if bulk-loaded data (a snapshot,
  # seed, or demo reseed) leaves the counter behind the real max of its backing
  # column, pass that max as `floor` and the next value is guaranteed to exceed
  # it. The counter is only ever advanced, never rewound.
  def self.increment!(hotel:, type:, floor: nil)
    counter = find_or_create_by!(hotel: hotel, counter_type: type)
    counter.with_lock do
      counter.update!(last_value: [ counter.last_value, floor.to_i ].max + 1)
    end
    counter.last_value
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
