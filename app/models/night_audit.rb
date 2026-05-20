class NightAudit < ApplicationRecord
  belongs_to :hotel
  belongs_to :performed_by_user, class_name: "User", optional: true
  has_many :night_audit_logs, dependent: :destroy
  has_many :financial_audit_events, dependent: :restrict_with_error
  has_one :financial_summary, class_name: "NightAuditFinancialSummary", dependent: :destroy

  STATUSES = %w[pending running completed blocked failed].freeze
  TRIGGER_MODES = %w[manual scheduled].freeze

  validates :business_date, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :trigger_mode, presence: true, inclusion: { in: TRIGGER_MODES }
  validates :hotel_id, uniqueness: { scope: :business_date }

  scope :recent_first, -> { order(business_date: :desc, created_at: :desc) }
  scope :completed, -> { where(status: "completed") }

  def self.closed_for_date?(hotel_id, date)
    Hotel.find(hotel_id).date_closed?(date)
  end

  def completed?
    status == "completed"
  end

  def blocked?
    status == "blocked"
  end

  def failed?
    status == "failed"
  end

  def running?
    status == "running"
  end
end
