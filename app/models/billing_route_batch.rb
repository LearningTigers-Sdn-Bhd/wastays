# frozen_string_literal: true

class BillingRouteBatch < ApplicationRecord
  belongs_to :hotel
  belongs_to :booking
  belongs_to :actor, class_name: "User", optional: true

  validates :idempotency_key, presence: true, uniqueness: { scope: :booking_id }
end
