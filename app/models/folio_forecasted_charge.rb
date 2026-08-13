class FolioForecastedCharge < ApplicationRecord
  belongs_to :booking_folio
  belongs_to :actualizing_transaction, class_name: "FolioTransaction", optional: true

  STATUSES = %w[forecast actualized superseded].freeze
  CHARGE_KINDS = %w[accommodation tax ota_fee ota_service ota_discount extra_charge extra_charge_tax].freeze

  validates :stay_date, :charge_kind, :identity, :amount, :description, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :charge_kind, inclusion: { in: CHARGE_KINDS }
  validates :amount, numericality: { other_than: 0 }

  scope :forecast, -> { where(status: "forecast") }
  scope :actualized, -> { where(status: "actualized") }
  scope :superseded, -> { where(status: "superseded") }
  scope :for_date, ->(date) { where(stay_date: date) }
  scope :nightly_room, -> { where(charge_kind: %w[accommodation tax]) }
  scope :nightly_financial, -> { where(charge_kind: %w[accommodation tax ota_fee ota_service ota_discount]) }
  scope :scheduled_extra_charges, -> { where(charge_kind: %w[extra_charge extra_charge_tax]) }

  def actualize!(transaction:)
    update!(status: "actualized", actualizing_transaction: transaction)
  end

  def supersede!
    update!(status: "superseded")
  end

  def self.supersede_all!
    forecast.update_all(status: "superseded")
  end
end
