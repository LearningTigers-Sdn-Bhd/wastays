# frozen_string_literal: true

class Booking < ApplicationRecord
  include Bookings::StatusLifecycle

  TOURISM_TAX_KEYS = %w[tourism_tax ttx].freeze

  belongs_to :booking_quote, optional: true
  belongs_to :hotel
  belongs_to :payout_batch, optional: true
  has_many :booking_rooms, dependent: :destroy
  accepts_nested_attributes_for :booking_rooms
  has_many :booking_notes, dependent: :destroy
  has_many :booking_guests, dependent: :destroy
  has_many :guests, through: :booking_guests
  has_one :pre_checkin, dependent: :destroy
  has_one :refund_request, dependent: :destroy
  has_one :booking_folio, dependent: :destroy
  has_many :deposits, dependent: :restrict_with_error
  has_one_attached :id_front
  has_one_attached :id_back
  has_many :housekeeping_requests, dependent: :destroy
  has_many :complaint_requests, dependent: :destroy
  has_many :check_out_requests, dependent: :destroy
  has_many :notification_deliveries, dependent: :destroy
  has_many :payment_transactions, dependent: :destroy
  has_many :room_operational_audit_logs, dependent: :nullify
  attr_accessor :estimated_arrival_time, :existing_guest_id, :guest_update_intent, :status_transition_event

  def online?
    source.present? && source != "walk_in" && guarantee_method != "manual_at_hotel"
  end

  def check_in=(value)
    value = Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: value, kind: :check_in) if hotel && value.present?
    super(value)
  end

  def check_out=(value)
    value = Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: value, kind: :check_out) if hotel && value.present?
    super(value)
  end

  def room_type_summary
    booking_rooms.includes(:room_type).map { |br| br.room_type.name }.uniq.to_sentence
  end

  def guest_government_id
    @guest_government_id.presence ||
      pre_checkin&.metadata&.dig("guest_government_id").presence ||
      primary_guest&.government_id
  end

  def guest_government_id=(value)
    @guest_government_id = value
  end

  STATUSES = %w[pending confirmed review_no_show checked_in review_due_out checkout_required cancelled completed overbooked no_show].freeze
  PAYMENT_STATUSES = %w[pending authorized partial captured failed refunded].freeze
  PAYOUT_STATUSES = %w[pending processing paid].freeze

  PRE_CHECKIN_STATUSES = %w[not_started pending in_progress completed failed].freeze
  GUARANTEE_METHODS = %w[none pre_checkin_completed manual_at_hotel card_authorization_document charge_now].freeze
  DEPOSIT_STATUSES = %w[not_required pending_at_hotel authorized collected released failed].freeze
  DOCUMENT_TYPES = [
    [ "Identity Card (IC)", "ic" ],
    [ "Passport", "passport" ]
  ].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :status_transition_must_be_allowed, if: :status_changed_on_persisted_record?
  validate :check_cta_ctd_restrictions
  validates :no_show_review_business_date, presence: true, if: -> { status == "review_no_show" }
  validates :payment_status, presence: true, inclusion: { in: PAYMENT_STATUSES }
  validates :pre_checkin_status, inclusion: { in: PRE_CHECKIN_STATUSES, allow_nil: true }
  validates :guarantee_method, inclusion: { in: GUARANTEE_METHODS, allow_blank: true }
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
  scope :checkout_required, -> { where(status: "checkout_required") }
  scope :completed, -> { where(status: "completed") }
  scope :no_show, -> { where(status: "no_show") }
  scope :active, -> { where(status: [ "confirmed", "review_no_show", "checked_in", "review_due_out", "checkout_required" ]) }
  scope :revenue_generating, -> { where(status: [ "confirmed", "review_no_show", "checked_in", "review_due_out", "checkout_required", "completed", "no_show" ]) }
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
  scope :checking_in_on, ->(date, zone = Time.zone) { where(check_in: date.to_date.in_time_zone(zone).all_day) }
  scope :checking_out_on, ->(date, zone = Time.zone) { where(check_out: date.to_date.in_time_zone(zone).all_day) }
  scope :checking_in_between, ->(start_date, end_date, zone = Time.zone) {
    where(check_in: start_date.to_date.in_time_zone(zone).beginning_of_day..end_date.to_date.in_time_zone(zone).end_of_day)
  }
  scope :checking_out_between, ->(start_date, end_date, zone = Time.zone) {
    where(check_out: start_date.to_date.in_time_zone(zone).beginning_of_day..end_date.to_date.in_time_zone(zone).end_of_day)
  }

  scope :unbatched_upcoming, ->(cutoff_date) {
    completed.where(payout_batch_id: nil).where("checked_out_at > ?", cutoff_date)
  }

  def self.analytics_summary(start_date, end_date, query: nil, base_scope: nil)
    base = base_scope || revenue_generating
    base = base.created_between(start_date, end_date).search(query)

    # Reconcile to FolioTransaction SSOT
    transactions = FolioTransaction.joins(booking_folio: :booking)
                                   .where(bookings: { id: base.select(:id) })
                                   .where(transaction_type: %w[charge adjustment])

    total_gross = transactions.sum(:amount)
    # Proportional margin calculation based on booking snapshots
    total_margin = base.sum("COALESCE(margin_amount, 0)")
    total_net = total_gross - total_margin

    {
      total_revenue: total_gross,
      total_margin: total_margin,
      total_net: total_net,
      booking_count: base.count,
      active_hotels_count: base.distinct.count(:hotel_id)
    }
  end

  def self.daily_analytics(start_date, end_date, query: nil, base_scope: nil)
    base = base_scope || revenue_generating
    base = base.created_between(start_date, end_date).search(query).includes(booking_folio: :folio_transactions)

    base.group_by { |booking| booking.created_at.to_date }
      .sort
      .map do |date, bookings|
        # Sum gross from transactions for these specific bookings
        gross = FolioTransaction.joins(booking_folio: :booking)
                                .where(bookings: { id: bookings.map(&:id) })
                                .where(transaction_type: %w[charge adjustment])
                                .sum(:amount)
        margin = bookings.sum { |b| b.margin_amount || 0 }
        {
          date: date,
          booking_count: bookings.count,
          revenue: gross,
          margin: margin,
          net: gross - margin
        }
      end
  end

  def self.daily_revenue_data(bookings)
    # Reconcile to ledger
    bookings.group_by { |b| b.created_at.to_date }
            .transform_values do |bs|
              FolioTransaction.joins(booking_folio: :booking)
                              .where(bookings: { id: bs.map(&:id) })
                              .where(transaction_type: %w[charge adjustment])
                              .sum(:amount)
            end
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
         .includes(booking_folio: :folio_transactions)
         .created_between(start_date, end_date)
         .search(query)
         .order(created_at: :desc)
  end

  def checked_in?
    status == "checked_in"
  end

  def checkout_required?
    status == "checkout_required"
  end

  def checked_out?
    status == "completed"
  end

  def payout_eligible?
    status == "completed" && payout_status == "pending"
  end

  before_save :set_payout_status, if: :status_changed?
  after_create_commit :enqueue_receipt_email, if: -> { status == "confirmed" }
  after_create_commit :enqueue_whatsapp_receipt, if: -> { status == "confirmed" }

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

  delegate :folio_number, to: :booking_folio, allow_nil: true
  delegate :invoice_number, to: :booking_folio, allow_nil: true

  def pre_checkin_completed?
    pre_checkin_display_status == "completed"
  end

  def tourism_tax?
    tourism_tax_total.positive?
  end

  def tourism_tax_total
    snapshot_total = self.class.tourism_tax_total_from_posting_snapshot(tax_posting_snapshot)
    return snapshot_total if snapshot_total.positive?

    tax_line_total = self.class.tourism_tax_total_for(tax_lines)
    return tax_line_total if tax_line_total.positive?

    tourism_tax_amount.to_d.round(2)
  end

  def folio_outstanding_balance
    booking_folio&.outstanding_balance || 0.0
  end

  def transition_status_to!(new_status, event:, attributes: {})
    self.status_transition_event = event
    update!(attributes.merge(status: new_status))
  ensure
    self.status_transition_event = nil
  end

  def tax_total
    Array(tax_lines).sum { |t| t["amount"].to_f }.round(2)
  end

  def non_tourism_tax_total
    self.class.non_tourism_tax_total_for(tax_lines)
  end

  def tax_lines_for(type)
    Array(tax_lines).select { |t| t["type"] == type.to_s }
  end

  def self.tourism_tax_total_for(lines)
    Array(lines).select { |line| tourism_tax_line?(line) }.sum { |line| tax_line_amount(line) }.round(2)
  end

  def self.non_tourism_tax_total_for(lines)
    Array(lines).reject { |line| tourism_tax_line?(line) }.sum { |line| tax_line_amount(line) }.round(2)
  end

  def self.tourism_tax_total_from_posting_snapshot(snapshot)
    snapshot.to_h.values.flatten.select { |line| tourism_tax_line?(line) }.sum { |line| tax_line_amount(line) }.round(2)
  end

  def self.tourism_tax_line?(line)
    line = line.to_h
    type = line["type"].presence || line[:type]
    primary_key = line["primary_tax_key"].presence || line[:primary_tax_key]

    type.to_s.in?(TOURISM_TAX_KEYS) || primary_key.to_s.in?(TOURISM_TAX_KEYS)
  end

  def self.tax_line_amount(line)
    line = line.to_h
    (line["amount"].presence || line[:amount]).to_d
  end

  def formatted_reservation_number
    format_number(reservation_number, type_code: 1)
  end

  def formatted_receipt_number
    format_number(receipt_number, type_code: 5)
  end

  def formatted_folio_number
    format_number(folio_number, type_code: 3)
  end

  def formatted_invoice_number
    format_number(invoice_number, type_code: 3)
  end

  def formatted_guest_registration_number
    format_number(guest_registration_number, type_code: 2)
  end

  def room_numbers
    booking_rooms.pluck(:room_number).compact.join(", ")
  end

  def self.lookup_by_phone(phone)
    suffix = PhoneIdentity.booking_lookup_suffix(phone)
    return none if suffix.blank?

    where("regexp_replace(guest_phone, '\D', '', 'g') LIKE ?", "%#{suffix}")
  end

  private

  def status_changed_on_persisted_record?
    persisted? && will_save_change_to_status?
  end

  def status_transition_must_be_allowed
    from = status_in_database
    to = status
    event = status_transition_event

    return if Bookings::StatusLifecycle.valid_transition?(from: from, to: to, event: event)

    errors.add(:status, Bookings::StatusLifecycle.transition_error(from: from, to: to, event: event))
  end

  DOCUMENT_NUMBER_PAD_LENGTH = 7

  def format_number(number, type_code:)
    return nil unless number
    prefix = hotel&.hotel_prefix.presence || "WS"
    padded = number.to_s.rjust(DOCUMENT_NUMBER_PAD_LENGTH, "0")
    "#{prefix}-#{type_code}#{padded}"
  end

  def set_payout_status
    self.payout_status = "pending" if status == "completed" && payout_status.blank?
  end

  def enqueue_receipt_email
    SendReceiptEmailJob.perform_later(id)
  end

  def enqueue_whatsapp_receipt
    SendWhatsappReceiptJob.perform_later(id)
  end

  def enqueue_invoice_email
    SendInvoiceEmailJob.perform_later(id)
  end

  CONFIRMATION_TOKEN_CHARSET = (("A".."Z").to_a + ("2".."9").to_a - %w[I O L]).freeze
  CONFIRMATION_TOKEN_LENGTH = 6

  def generate_confirmation_token
    return if confirmation_token.present?

    loop do
      candidate = Array.new(CONFIRMATION_TOKEN_LENGTH) { CONFIRMATION_TOKEN_CHARSET.sample }.join
      next if Booking.exists?(confirmation_token: candidate)

      self.confirmation_token = candidate
      break
    end
  end

  def normalize_guest_data
    self.guest_email = guest_email&.downcase&.strip
    self.guest_country = guest_country&.split&.map(&:capitalize)&.join(" ") if guest_country.present?
  end

  def check_cta_ctd_restrictions
    return unless %w[pending confirmed review_no_show checked_in review_due_out checkout_required].include?(status)
    return unless new_record? || check_in_changed? || check_out_changed?
    return if new_record? && booking_rooms.target.empty?

    room_types = booking_rooms.map(&:room_type).compact
    return if room_types.empty?

    room_types.each do |room_type|
      rate_plan_ids = [ nil ]
      if booking_rooms.present?
        rate_plan_ids += booking_rooms.map(&:rate_plan_id).compact
      end
      if rate_plan_ids.include?(nil)
        standard_plan = room_type.rate_plans.first
        rate_plan_ids << standard_plan.id if standard_plan
      end
      rate_plan_ids.uniq!

      # CTA Check on check-in date
      if check_in.present?
        room_rates_at_check_in = RoomRate.where(
          room_type_id: room_type.id,
          date: check_in.to_date,
          rate_plan_id: rate_plan_ids
        )

        if room_rates_at_check_in.any?(&:closed_to_arrival?)
          errors.add(:check_in, "date (#{check_in.to_date}) is closed to arrival (CTA) for this rate plan.")
        end
      end

      # CTD Check on check_out date
      if check_out.present?
        room_rates_at_check_out = RoomRate.where(
          room_type_id: room_type.id,
          date: check_out.to_date,
          rate_plan_id: rate_plan_ids
        )

        if room_rates_at_check_out.any?(&:closed_to_departure?)
          errors.add(:check_out, "date (#{check_out.to_date}) is closed to departure (CTD) for this rate plan.")
        end
      end
    end
  end
end
