# frozen_string_literal: true

class Booking < ApplicationRecord
  belongs_to :booking_quote, optional: true
  belongs_to :hotel
  belongs_to :payout_batch, optional: true
  has_many :booking_rooms, dependent: :destroy
  has_many :booking_notes, dependent: :destroy
  has_many :booking_guests, dependent: :destroy
  has_many :guests, through: :booking_guests
  has_one :pre_checkin, dependent: :destroy
  has_one :refund_request, dependent: :destroy
  has_many :housekeeping_requests, dependent: :destroy
  has_many :complaint_requests, dependent: :destroy
  attr_accessor :estimated_arrival_time
  attr_accessor :guest_government_id

  STATUSES = %w[pending confirmed checked_in cancelled completed overbooked].freeze
  PAYMENT_STATUSES = %w[pending authorized captured failed refunded].freeze
  PAYOUT_STATUSES = %w[pending processing paid].freeze

  PRE_CHECKIN_STATUSES = %w[not_started pending in_progress completed failed].freeze
  GUARANTEE_METHODS = %w[none pre_checkin_completed manual_at_hotel card_authorization_document charge_now].freeze
  DEPOSIT_STATUSES = %w[not_required pending_at_hotel authorized collected released failed].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :payment_status, presence: true, inclusion: { in: PAYMENT_STATUSES }
  validates :pre_checkin_status, inclusion: { in: PRE_CHECKIN_STATUSES, allow_nil: true }
  validates :guarantee_method, inclusion: { in: GUARANTEE_METHODS, allow_nil: true }
  validates :deposit_status, inclusion: { in: DEPOSIT_STATUSES, allow_nil: true }

  def primary_guest
    booking_guests.find_by(is_primary: true)&.guest
  end

  validates :guest_name, :guest_email, :guest_phone, presence: true
  validates :check_in, :check_out, :adults, :total_amount, :confirmation_token, presence: true
  validates :confirmation_token, uniqueness: true

  before_validation :generate_confirmation_token, on: :create
  before_validation :normalize_guest_data

  scope :recent_first, -> { order(created_at: :desc) }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :checked_in, -> { where(status: "checked_in") }
  scope :completed, -> { where(status: "completed") }
  scope :active, -> { where(status: [ "confirmed", "checked_in" ]) }
  scope :revenue_generating, -> { where(status: [ "confirmed", "checked_in", "completed" ]) }
  scope :payout_eligible, -> { completed.where(payout_status: "pending") }

  scope :search, ->(query) {
    return all if query.blank?
    q = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.downcase)}%"
    joins(:hotel).where(
      "hotels.name ILIKE :q OR guest_name ILIKE :q OR confirmation_token ILIKE :q OR guest_email ILIKE :q OR guest_phone ILIKE :q",
      q: q
    )
  }

  scope :created_between, ->(start_date, end_date) {
    where(created_at: start_date.beginning_of_day..end_date.end_of_day)
  }

  scope :unbatched_upcoming, ->(cutoff_date) {
    completed.where(payout_batch_id: nil).where("checked_out_at > ?", cutoff_date)
  }

  def self.analytics_summary(start_date, end_date, query: nil, base_scope: nil)
    base = base_scope || revenue_generating
    base = base.created_between(start_date, end_date).search(query)

    {
      total_revenue: base.sum(:total_amount) || 0,
      total_margin: base.sum("COALESCE(margin_amount, 0)"),
      total_net: base.sum("COALESCE(net_amount, 0)"),
      booking_count: base.count,
      active_hotels_count: base.distinct.count(:hotel_id)
    }
  end

  def self.daily_analytics(start_date, end_date, query: nil, base_scope: nil)
    base = base_scope || revenue_generating
    base.created_between(start_date, end_date)
      .search(query)
      .group_by { |booking| booking.created_at.to_date }
      .sort
      .map do |date, bookings|
        {
          date: date,
          booking_count: bookings.count,
          revenue: bookings.sum(&:total_amount),
          margin: bookings.sum { |b| b.margin_amount || 0 },
          net: bookings.sum { |b| b.net_amount || 0 }
        }
      end
  end

  def self.daily_revenue_data(bookings)
    bookings.group_by { |b| b.created_at.to_date }
            .transform_values { |bs| bs.sum(&:total_amount) }
            .sort.to_h
  end
  def self.last_friday
    date = Date.current
    date -= 1 while !date.friday?
    date
  end

  def self.payout_summary_by_hotel(bookings)
    bookings.group_by(&:hotel_id).map do |hotel_id, bs|
      hotel = Hotel.find(hotel_id)
      {
        hotel: hotel,
        booking_count: bs.count,
        total_net: bs.sum { |b| b.net_amount || 0 }
      }
    end
  end

  def self.for_financial_breakdown(hotel, start_date, end_date, query)
    hotel.bookings.revenue_generating
         .created_between(start_date, end_date)
         .search(query)
         .order(created_at: :desc)
  end

  def checked_in?
    status == "checked_in"
  end

  def checked_out?
    status == "completed"
  end

  def payout_eligible?
    status == "completed" && payout_status == "pending"
  end

  before_save :set_payout_status, if: :status_changed?
  after_create_commit :enqueue_invoice_email, if: -> { status == "confirmed" }
  after_create_commit :enqueue_whatsapp_invoice, if: -> { status == "confirmed" }

  def pre_checkin_display_status
    metadata = pre_checkin&.metadata || {}
    has_real_pre_checkin_data = pre_checkin.present? && (
      pre_checkin.completed_at.present? ||
      metadata["submitted_at"].present? ||
      metadata["guest_government_id"].present? ||
      metadata["estimated_arrival_time"].present?
    )

    return "not_started" if status == "completed" && !has_real_pre_checkin_data
    return "completed" if has_real_pre_checkin_data && (pre_checkin_status == "completed" || pre_checkin&.completed?)
    return "failed" if has_real_pre_checkin_data && (pre_checkin_status == "failed" || pre_checkin&.status == "failed")
    return "pending" if status == "confirmed"
    return "not_started" unless has_real_pre_checkin_data

    pre_checkin_status.presence || pre_checkin&.status.presence || "not_started"
  end

  def tourism_tax?
    tourism_tax_applied && tourism_tax_amount.positive?
  end

  private

  def set_payout_status
    self.payout_status = "pending" if status == "completed" && payout_status.blank?
  end

  def enqueue_invoice_email
    SendInvoiceEmailJob.perform_later(id)
  end

  def enqueue_whatsapp_invoice
    SendWhatsappInvoiceJob.perform_later(id)
  end

  def generate_confirmation_token
    self.confirmation_token ||= "WS-#{SecureRandom.alphanumeric(8).upcase}"
  end

  def normalize_guest_data
    self.guest_email = guest_email&.downcase&.strip
    self.guest_country = guest_country&.split&.map(&:capitalize)&.join(" ") if guest_country.present?
  end
end
