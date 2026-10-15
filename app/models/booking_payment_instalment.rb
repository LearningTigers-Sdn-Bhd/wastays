# frozen_string_literal: true

# One stage of an agent booking's payment schedule, written when the booking is
# created. The schedule is a snapshot: it keeps what the agent was promised even
# if the hotel later changes its terms. Money itself lives in the folio -- an
# instalment only records which stage a folio payment or refund settled.
class BookingPaymentInstalment < ApplicationRecord
  KINDS = %w[deposit balance full].freeze
  STATUSES = %w[pending paid refunded waived].freeze
  STAGE_LABELS = { "deposit" => "Deposit", "balance" => "Balance", "full" => "Full payment" }.freeze

  belongs_to :booking, inverse_of: :payment_instalments
  belongs_to :paid_by, class_name: "User", optional: true
  belongs_to :refunded_by, class_name: "User", optional: true
  belongs_to :payment_folio_transaction, class_name: "FolioTransaction", optional: true
  belongs_to :refund_folio_transaction, class_name: "FolioTransaction", optional: true

  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :status, STATUSES.index_by(&:itself), validate: true, prefix: true

  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :booking_id }
  validates :amount, numericality: { greater_than: 0 }
  validates :due_at, presence: true

  scope :pending, -> { where(status: "pending") }

  def stage_label = STAGE_LABELS.fetch(kind)
end
