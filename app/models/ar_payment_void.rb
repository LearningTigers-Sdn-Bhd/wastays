# frozen_string_literal: true

class ArPaymentVoid < ApplicationRecord
  belongs_to :ar_payment
  belongs_to :voided_by, class_name: "User"

  validates :reason, :voided_at, presence: true
  validates :ar_payment_id, uniqueness: true
  validates :metadata, exclusion: { in: [ nil ] }

  before_update :prevent_update
  before_destroy :prevent_destroy

  private

  def prevent_update
    errors.add(:base, "AR payment voids are immutable.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "AR payment voids are immutable and cannot be deleted.")
    throw :abort
  end
end
