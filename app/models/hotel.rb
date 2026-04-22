class Hotel < ApplicationRecord
  include AccountScopable

  has_many_attached :photos
  has_many :user_hotel_accesses, dependent: :destroy
  has_many :users, through: :user_hotel_accesses
  belongs_to :salesperson, class_name: "User", optional: true
  has_one :property_policy, dependent: :destroy
  has_many :room_types, dependent: :destroy
  has_many :pricing_rules, class_name: "HotelPricingRule", dependent: :destroy
  has_many :inventory_audit_logs, dependent: :destroy
  has_many :payment_settings, as: :settable, dependent: :destroy
  has_many :bookings, dependent: :destroy
  has_many :booking_quotes, dependent: :destroy
  has_many :payout_batches, dependent: :destroy
  has_many :onboarding_sessions, dependent: :destroy

  validates :name, presence: true
  validates :status, presence: true
  validates :city, presence: true
  validates :country, presence: true
  validate :photos_limit_not_exceeded
  validate :featured_photo_attachment_belongs_to_hotel

  STATUSES = %w[
    registered
    email_verified
    profile_incomplete
    rooms_incomplete
    inventory_incomplete
    pending_review
    approved
    live
    suspended
  ].freeze
  MAX_PHOTOS = 20

  PhotoUploadResult = Struct.new(:attached_count, :trimmed_count, keyword_init: true) do
    def trimmed?
      trimmed_count.positive?
    end

    def alert_message
      if attached_count.positive?
        "Only the first #{attached_count} photo#{attached_count == 1 ? '' : 's'} were uploaded. Extra files were ignored."
      else
        "This hotel already has #{Hotel::MAX_PHOTOS} photos. Remove some before uploading more."
      end
    end
  end

  def active?
    %w[approved live].include?(status)
  end

  def effective_payment_setting(gateway)
    # 1. Check hotel-level override
    setting = payment_settings.active.find_by(gateway: gateway)
    return setting if setting

    # 2. Check account-level setting
    setting = account.payment_settings.active.find_by(gateway: gateway)
    return setting if setting

    # 3. Check credential-level default for this gateway
    Payments::CredentialSetting.for_gateway(gateway)
  end

  def checkout_payment_setting
    payment_settings.active.order(updated_at: :desc).first ||
      account.payment_settings.active.order(updated_at: :desc).first ||
      Payments::CredentialSetting.default
  end

  def checkout_payment_gateway
    checkout_payment_setting&.gateway&.downcase
  end

  def effective_margin_rate(room_type = nil)
    # 1. Check room-type override
    if room_type
      rule = MarginRule.active.find_by(settable: room_type)
      return rule.rate if rule
    end

    # 2. Check hotel-level override
    rule = MarginRule.active.find_by(settable: self)
    return rule.rate if rule

    # 3. Check global default (where settable is nil)
    rule = MarginRule.active.where(settable_id: nil).find_by(settable_type: [ nil, "" ])
    rule&.rate || 10.0 # Default to 10% if nothing set
  end

  def effective_setup_fee
    override = SetupFeeRule.active.find_by(settable: self)
    return override.amount.to_f if override

    default_rule = SetupFeeRule.active.where(settable_id: nil).find_by(settable_type: [ nil, "" ])
    default_rule&.amount&.to_f || 0.0
  end

  def onboarding?
    %w[registered email_verified profile_incomplete rooms_incomplete inventory_incomplete].include?(status)
  end

  def profile_completed?
    !status.in?([ "registered", "email_verified" ])
  end

  def policies_completed?
    !status.in?([ "registered", "email_verified", "profile_incomplete" ])
  end

  def rooms_completed?
    !status.in?([ "registered", "email_verified", "profile_incomplete", "rooms_incomplete" ])
  end

  def ready_for_review?
    status == "inventory_incomplete"
  end

  def complete_profile!
    update(status: "profile_incomplete") if status == "registered"
  end

  def complete_policies!
    update(status: "rooms_incomplete") if status == "profile_incomplete"
  end

  def complete_rooms!
    update(status: "inventory_incomplete") if status == "rooms_incomplete"
  end

  def submit_for_review!
    update(status: "pending_review") if ready_for_review?
  end

  def tourism_tax_applicable_for?(country)
    return false unless tourism_tax_enabled?
    return false if country.blank?

    !country.casecmp("Malaysia").zero?
  end

  def tourism_tax_amount_for(country)
    tourism_tax_applicable_for?(country) ? tourism_tax_amount : 0
  end

  def featured_photo_attachment
    return nil if featured_photo_attachment_id.blank?

    photos.attachments.find_by(id: featured_photo_attachment_id)
  end

  def ordered_photo_attachments
    attachments = photos.attachments.to_a
    featured = featured_photo_attachment
    return attachments if featured.blank?

    [ featured ] + attachments.reject { |attachment| attachment.id == featured.id }
  end

  def attach_photos_with_limit(photo_files)
    photo_files = Array(photo_files).reject(&:blank?)
    remaining_slots = [ MAX_PHOTOS - photos.count, 0 ].max
    photos_to_attach = photo_files.first(remaining_slots)

    photos.attach(photos_to_attach) if photos_to_attach.any?

    PhotoUploadResult.new(
      attached_count: photos_to_attach.size,
      trimmed_count: photo_files.size - photos_to_attach.size
    )
  end

  def payout_batches_for_reports(start_date: nil, end_date: nil)
    payout_batches.order(period_end: :desc).period_between(start_date, end_date)
  end

  def upcoming_payout_amount(cutoff_date)
    bookings.unbatched_upcoming(cutoff_date).sum("COALESCE(net_amount, 0)")
  end

  def onboarding_completion_date
    return nil unless [ "approved", "live" ].include?(status)
    final_onboarding_session&.completed_at
  end

  def onboarding_start_date
    saved = self[:onboarding_start_date]
    return saved if saved.present?

    onboarding_period_record&.scheduled_at&.to_date || created_at.to_date
  end

  def onboarding_end_date
    saved = self[:onboarding_end_date]
    return saved if saved.present?

    onboarding_period_record&.completed_at&.to_date || Date.current
  end

  def onboarding_duration
    saved_start = self[:onboarding_start_date]
    saved_end = self[:onboarding_end_date]
    if saved_start.present? && saved_end.present?
      saved_end - saved_start
    else
      rec = onboarding_period_record
      return nil unless rec

      rec.completed_at - rec.scheduled_at
    end
  end

  def onboarding_duration_days
    saved_start = self[:onboarding_start_date]
    saved_end = self[:onboarding_end_date]

    if saved_start.present? && saved_end.present?
      (saved_end.to_date - saved_start.to_date).to_f
    else
      rec = onboarding_period_record
      return nil unless rec&.scheduled_at.present? && rec&.completed_at.present?

      ((rec.completed_at - rec.scheduled_at) / 1.day).to_f
    end
  end

  private

  def photos_limit_not_exceeded
    return unless photos.attached?

    errors.add(:photos, "cannot exceed #{MAX_PHOTOS} photos") if photos.count > MAX_PHOTOS
  end

  def featured_photo_attachment_belongs_to_hotel
    return if featured_photo_attachment_id.blank?
    return if photos.attachments.any? { |a| a.id == featured_photo_attachment_id }

    errors.add(:featured_photo_attachment_id, "must belong to this hotel")
  end

  def onboarding_period_record
    final_onboarding_session
  end

  def final_onboarding_session
    onboarding_sessions.completed.where(notes: "FINAL_ONBOARDING_COMPLETION").order(completed_at: :desc).first ||
      onboarding_sessions.where(notes: "FINAL_ONBOARDING_COMPLETION").order(updated_at: :desc).first
  end
end
