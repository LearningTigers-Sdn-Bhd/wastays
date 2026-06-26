# frozen_string_literal: true

class ArPaymentAllocationReversal < ApplicationRecord
  belongs_to :ar_payment_allocation
  belongs_to :reversed_by, class_name: "User"

  validates :reason, :reversed_at, presence: true
  validates :ar_payment_allocation_id, uniqueness: true
  validates :metadata, exclusion: { in: [ nil ] }

  before_update :prevent_update
  before_destroy :prevent_destroy

  private

  def prevent_update
    errors.add(:base, "AR payment allocation reversals are immutable.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "AR payment allocation reversals are immutable and cannot be deleted.")
    throw :abort
  end
end
