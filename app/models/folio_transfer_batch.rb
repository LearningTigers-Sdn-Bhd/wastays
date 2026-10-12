# frozen_string_literal: true

class FolioTransferBatch < ApplicationRecord
  belongs_to :hotel

  validates :idempotency_key, :request_fingerprint, presence: true
  validates :idempotency_key, uniqueness: { scope: :hotel_id }
end
