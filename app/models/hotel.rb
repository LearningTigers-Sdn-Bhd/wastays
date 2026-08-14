class Hotel < ApplicationRecord
  include AccountScopable
  extend FriendlyId
  friendly_id :name, use: :slugged

  encrypts :ai_provider_key

  enum :ai_provider_name, {
    openai: "openai",
    claude: "claude",
    deepseek: "deepseek",
    gemini: "gemini"
  }, prefix: true, validate: { allow_nil: true }

  enum :ai_concierge_tone, {
    basic: "basic",
    business: "business",
    cheerful: "cheerful"
  }, prefix: true, validate: true

  AI_CONCIERGE_MODEL_NAMES = {
    "openai" => "gpt-4o-mini",
    "claude" => "claude-haiku-4-5",
    "deepseek" => "deepseek-chat",
    "gemini" => "gemini-2.5-flash"
  }.freeze

  validates :ai_provider_name, presence: true, if: :ai_provider_enabled?
  validates :ai_provider_key, presence: true, if: :ai_provider_enabled?

  has_many_attached :photos
  has_many :user_hotel_accesses, dependent: :destroy
  has_many :users, through: :user_hotel_accesses
  has_many :invitations, dependent: :destroy
  has_many :staff_invitations, -> { staff }, class_name: "StaffInvitation"
  has_many :corporate_invitations, -> { corporate }, class_name: "CorporateInvitation"
  has_many :hotel_corporate_accounts, dependent: :destroy
  has_many :corporate_accounts, through: :hotel_corporate_accounts
  has_many :introduced_hotels, class_name: "Hotel", foreign_key: "salesperson_id", dependent: :nullify
  belongs_to :salesperson, class_name: "User", optional: true
  belongs_to :training_completed_by, class_name: "User", optional: true
  belongs_to :plan, optional: true
  has_one :property_policy, dependent: :destroy
  accepts_nested_attributes_for :property_policy
  has_many :room_types, dependent: :destroy
  has_many :room_groups, dependent: :destroy
  has_many :rate_plans, dependent: :destroy
  has_many :knowledge_documents, class_name: "HotelKnowledgeDocument", dependent: :destroy
  has_many :knowledge_diagnostics, class_name: "HotelKnowledgeDiagnostic", dependent: :destroy
  has_many :nearby_attractions, dependent: :destroy
  has_many :pricing_rules, class_name: "HotelPricingRule", dependent: :destroy
  has_many :inventory_audit_logs, dependent: :destroy
  has_many :payment_settings, as: :settable, dependent: :destroy
  has_many :bookings, dependent: :destroy
  has_many :channel_settlements, dependent: :restrict_with_error
  has_many :channel_settlement_receipts, dependent: :restrict_with_error
  has_many :channel_settlement_allocations, through: :channel_settlements
  has_many :ota_financial_snapshots, dependent: :restrict_with_error
  has_many :ota_financial_component_mappings, dependent: :restrict_with_error
  has_one :ota_rate_variance_policy, dependent: :restrict_with_error
  has_many :guest_registration_cards, dependent: :restrict_with_error
  has_many :guest_registration_note_templates, dependent: :destroy
  has_many :group_bookings, dependent: :restrict_with_error
  has_many :booking_folios, dependent: :restrict_with_error
  has_many :ar_invoices, dependent: :restrict_with_error
  has_many :invoices, dependent: :restrict_with_error
  has_many :receivables, class_name: "Receivable", dependent: :restrict_with_error
  has_many :ar_payments, dependent: :restrict_with_error
  has_many :ar_payment_submissions, dependent: :restrict_with_error
  has_many :folio_routing_rules, dependent: :destroy
  has_many :deposits, dependent: :restrict_with_error
  has_many :deposit_movements, through: :deposits
  has_many :hotel_taxes, dependent: :destroy
  has_many :transaction_codes, dependent: :destroy
  has_many :hotel_extra_charges, dependent: :destroy
  has_many :hotel_discounts, dependent: :destroy
  has_many :hotel_payment_methods, dependent: :destroy
  has_many :hotel_reservation_policies, dependent: :destroy
  has_many :hotel_ota_credentials, dependent: :destroy
  has_one :hotel_transaction_configuration, dependent: :destroy
  has_one :hotel_boat_setting, dependent: :destroy
  accepts_nested_attributes_for :hotel_boat_setting
  has_many :hotel_boat_schedules, dependent: :destroy
  has_many :hotel_counters, dependent: :destroy
  has_many :prospects, dependent: :destroy
  has_many :night_audits, dependent: :destroy
  has_many :hotel_business_dates, dependent: :destroy
  has_many :hotel_general_ledger_maps, dependent: :destroy
  has_many :journal_batches, dependent: :destroy
  has_many :financial_audit_events, dependent: :restrict_with_error
  has_many :folio_operation_logs, dependent: :restrict_with_error
  has_many :booking_quotes, dependent: :destroy
  has_many :payout_batches, dependent: :destroy
  has_many :onboarding_sessions, dependent: :destroy
  has_many :onboarding_sections, class_name: "HotelOnboardingSection", dependent: :destroy
  has_many :onboarding_audit_events, dependent: :destroy
  has_many :onboarding_submissions, dependent: :destroy
  has_many :onboarding_staff_drafts, dependent: :destroy
  has_many :onboarding_corporate_drafts, dependent: :destroy
  has_one :channel_mapping, as: :mappable, dependent: :destroy
  has_many :room_rates, through: :room_types
  has_many :room_locks, dependent: :destroy
  has_many :room_statuses, dependent: :destroy
  has_many :room_operational_audit_logs, dependent: :destroy
  has_many :room_blocks, dependent: :destroy
  has_many :notification_configs, dependent: :destroy
  has_many :notification_deliveries, dependent: :destroy
  has_many :channel_derived_settings, dependent: :destroy
  has_many :channel_availability_rules, dependent: :destroy


  validates :name, presence: true
  validates :unique_id, presence: true, uniqueness: { case_sensitive: false }
  validate :unique_id_is_immutable, on: :update, if: :will_save_change_to_unique_id?
  before_validation :assign_unique_id, on: :create
  validates :hotel_prefix, uniqueness: { case_sensitive: false }, allow_blank: true,
                           length: { in: 3..6 },
                           format: { with: /\A[A-Z0-9]+\z/, message: "must be uppercase letters and numbers only" },
                           if: -> { hotel_prefix.present? }
  has_many :hotel_prefix_histories, dependent: :destroy
  validate :hotel_prefix_has_not_been_used_by_another_hotel

  before_validation :normalize_default_currency
  before_validation :normalize_hotel_prefix
  before_validation :normalize_registration_numbers
  before_validation :assign_hotel_prefix, on: :create
  after_save :record_hotel_prefix_history, if: :saved_change_to_hotel_prefix?
  validates :slug, presence: true, uniqueness: true
  validates :status, presence: true
  validates :status, inclusion: { in: ->(_) { STATUSES } }, allow_blank: true
  validates :training_data_decision, inclusion: { in: %w[keep reset] }, allow_nil: true
  validates :training_reset_state, inclusion: { in: %w[queued processing failed] }, allow_nil: true
  validates :city, presence: true, unless: :setup?
  validates :country, presence: true, unless: :setup?
  validates :business_starts_at, :business_ends_at, presence: true
  validates :arrival_grace_period, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :default_currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :sell_mode, presence: true
  validates :sell_mode, inclusion: { in: ->(_) { RatePlan.sell_modes } }, allow_blank: true
  validate :photos_limit_not_exceeded
  validate :featured_photo_attachment_belongs_to_hotel
  validate :amenities_must_be_from_list
  validate :account_must_be_hotel_kind
  validate :sell_mode_is_immutable, on: :update, if: :will_save_change_to_sell_mode?

  # Operator-facing wording for the property's sell mode. The stored values
  # match rate_plans.sell_mode, but "per room"/"per person" is engine
  # vocabulary — staff and admins think in terms of what the property sells.
  def self.sell_mode_options
    [ [ "Room — one price per room, extra guest charges on top", "per_room" ],
      [ "Guest — one price per guest", "per_person" ] ]
  end

  def sells_per_person?
    sell_mode == "per_person"
  end

  # Navbar badge wording. Short enough to sit beside the property name, and
  # phrased as a statement about the property rather than as the choice itself
  # — sell_mode_options spells out the trade-off for whoever is picking it.
  def sell_mode_label
    sells_per_person? ? "Sells per person" : "Sells per room"
  end

  def self.const_missing(const_name)
    case const_name
    when :HOTEL_AMENITIES
      Amenity.hotel.ordered.map(&:to_h)
    when :CATEGORIZED_HOTEL_AMENITIES
      Amenity.categorized(:hotel)
    when :ROOM_AMENITIES
      Amenity.room.ordered.map(&:to_h)
    when :CATEGORIZED_ROOM_AMENITIES
      Amenity.categorized(:room)
    when :HOTEL_AMENITIES_MAP
      Amenity.lookup_map(:hotel)
    when :ROOM_AMENITIES_MAP
      Amenity.lookup_map(:room)
    when :AMENITIES
      (HOTEL_AMENITIES + ROOM_AMENITIES).uniq { |a| a[:id] }
    else
      super
    end
  end

  def account_must_be_hotel_kind
    return if account.blank? || account.hotel?

    errors.add(:account, "must be a hotel account")
  end

  def normalize_default_currency
    self.default_currency = CurrencyCatalog.normalize(default_currency)
  end

  scope :search, ->(query) {
    return all if query.blank?
    q = "%#{sanitize_sql_like(query.to_s.downcase)}%"
    where("LOWER(hotels.name) LIKE :q OR LOWER(hotels.city) LIKE :q OR LOWER(hotels.unique_id) LIKE :q", q: q)
  }

  # The onboarding lifecycle. A property is in `setup` until its owner submits it,
  # `pending_review` while WAStays looks at it, `ready_to_launch` once approved,
  # and `live` after the owner decides what to do with training activity.
  STATUSES = %w[
    setup
    pending_review
    ready_to_launch
    live
    suspended
  ].freeze
  MAX_PHOTOS = 20

  # The public identifier: a plain number, issued in order, starting here. Hotels quote
  # it down a phone line and sort by it in spreadsheets, which is what earned it the
  # switch from a random token. It has no fixed width — it grows past five digits.
  UNIQUE_ID_FLOOR = 10_101

  # Arbitrary but fixed: the advisory-lock key that serialises code issuance. Nothing
  # else in the app takes it, so it never contends with anything but itself.
  UNIQUE_ID_LOCK_KEY = 8_231_101

  # The numbers a hotel quotes on its documents. The first two identify the business
  # itself; the other two identify it to the authority behind each statutory tax.
  REGISTRATION_NUMBER_ATTRIBUTES = %i[
    tin
    ssm_number
    sst_registration_number
    tourism_tax_registration_number
  ].freeze

  # Resolves the identifier that appears in URLs. `unique_id` is canonical; `slug` is
  # kept as a permanent legacy read path so bookmarks and printed concierge QR codes
  # issued before the codes existed keep resolving. There is deliberately no `id`
  # branch: a hotel is addressed by the code it was issued, never by its row id.
  def self.locate(key, scope: all)
    key = key.to_s.strip
    return nil if key.blank?

    scope.find_by(unique_id: key.upcase) || scope.find_by(slug: key)
  end

  def self.locate!(key, scope: all)
    locate(key, scope: scope) || raise(ActiveRecord::RecordNotFound, "Couldn't find Hotel with identifier #{key.inspect}")
  end

  # Codes are issued in order, so the next one is the highest already issued plus one.
  # The advisory lock is what makes that safe when two hotels are created at once —
  # without it both reads see the same maximum and the unique index rejects the loser.
  # It is transaction-scoped and released on commit, and the only caller runs inside the
  # transaction `save` opens. The regexp guard keeps the cast away from any row still
  # holding a pre-numbering code.
  def self.next_unique_id
    # `execute`, not `select_value`: the lock function returns void, and asking the
    # result for a typed value only earns an "unknown OID" warning on every create.
    connection.execute("SELECT pg_advisory_xact_lock(#{connection.quote(UNIQUE_ID_LOCK_KEY)})")
    highest = connection.select_value("SELECT MAX(unique_id::bigint) FROM hotels WHERE unique_id ~ '^[0-9]+$'").to_i

    [ highest, UNIQUE_ID_FLOOR - 1 ].max.succ.to_s
  end

  def to_param
    unique_id
  end

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

  def setup?
    status == "setup"
  end

  def active?
    status == "live"
  end

  def training_mode?
    status.in?(%w[pending_review ready_to_launch]) && training_started_at.present?
  end

  def training_reset_in_progress?
    training_reset_state.in?(%w[queued processing])
  end

  def publicly_bookable?
    active? && plan&.slug != "easy"
  end

  def concierge_available?
    active? && concierge_enabled?
  end

  def plan_feature_map
    @plan_feature_map ||= if plan_id
      PlanFeature.where(plan_id: plan_id)
          .joins(:feature)
          .pluck("features.slug", :enabled, :level, :addon)
          .each_with_object({}) { |(slug, enabled, level, addon), h|
            h[slug] = { enabled: enabled, level: level, addon: addon }
          }
    else
      {}
    end
  end

  def feature_enabled?(slug)
    !!plan_feature_map.dig(slug.to_s, :enabled)
  end

  def feature_level(slug)
    row = plan_feature_map[slug.to_s]
    return nil unless row && row[:enabled]
    row[:level]
  end

  def feature_addon?(slug)
    !!plan_feature_map.dig(slug.to_s, :addon)
  end

  def hotel_time_zone
    Time.find_zone(time_zone.presence || User::DEFAULT_TIME_ZONE) || Time.zone
  end

  def arrival_grace_period_hours
    (arrival_grace_period || 0) / 3600
  end

  def arrival_grace_period_hours=(hours)
    self.arrival_grace_period = hours.to_i * 3600
  end

  def business_starts_at
    read_attribute(:business_starts_at)&.utc
  end

  def business_starts_at=(value)
    if value.is_a?(String) && value.present?
      write_attribute(:business_starts_at, Time.find_zone("UTC").parse(value))
    else
      super
    end
  end

  def business_ends_at
    read_attribute(:business_ends_at)&.utc
  end

  def business_ends_at=(value)
    if value.is_a?(String) && value.present?
      write_attribute(:business_ends_at, Time.find_zone("UTC").parse(value))
    else
      super
    end
  end

  def business_date_for(time = Time.current)
    local_time = time.in_time_zone(hotel_time_zone)
    date = local_time.to_date

    return date if business_day_window_for(date).cover?(local_time)
    return date - 1.day if business_day_window_for(date - 1.day).cover?(local_time)

    date
  end

  def current_business_date_record
    hotel_business_dates.current.order(:business_date, :id).first
  end

  def current_business_date
    current_business_date_record&.business_date
  end

  def date_closed?(date, _reference_time = Time.current)
    date = date.to_date
    record = hotel_business_dates.find_by(business_date: date)

    record.nil? || record.closed_like?
  end

  def can_audit_date?(business_date, time = Time.current)
    local_time = time.in_time_zone(hotel_time_zone)
    window = business_day_window_for(business_date)

    return false if local_time < window.end

    local_time >= window.end + 5.minutes
  end

  def latest_closable_business_date(time = Time.current)
    local_time = time.in_time_zone(hotel_time_zone)
    current_biz_date = business_date_for(local_time)

    candidate = current_biz_date - 1.day
    candidate_end = business_day_window_for(candidate).end

    if local_time >= candidate_end + 30.minutes
      candidate
    else
      candidate - 1.day
    end
  end

  def business_day_window_for(business_date)
    date = business_date.to_date
    start_at = hotel_time_zone.local(date.year, date.month, date.day, business_starts_at.hour, business_starts_at.min)
    end_date = business_day_crosses_midnight? ? date + 1.day : date
    end_at = hotel_time_zone.local(end_date.year, end_date.month, end_date.day, business_ends_at.hour, business_ends_at.min)

    start_at...end_at
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

  def ai_concierge_enabled?
    ai_provider_enabled?
  end

  def ai_concierge_ready?
    ai_concierge_enabled? && ai_provider_name.present? && ai_provider_key.present?
  end

  def ai_concierge_provider
    case ai_provider_name
    when "claude"
      :anthropic
    else
      ai_provider_name&.to_sym
    end
  end

  def ai_concierge_model_name
    AI_CONCIERGE_MODEL_NAMES.fetch(ai_provider_name)
  end

  def ai_concierge_api_key
    ai_provider_key
  end

  def ai_concierge_structured_output_supported?
    ai_provider_name != "deepseek"
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

  def business_day_crosses_midnight?
    # Compare hours and minutes directly to avoid zone issues on the 'time' column
    start_total_mins = (business_starts_at.hour * 60) + business_starts_at.min
    end_total_mins = (business_ends_at.hour * 60) + business_ends_at.min

    end_total_mins <= start_total_mins
  end

  def seconds_since_midnight(time)
    (time.hour * 3600) + (time.min * 60) + time.sec
  end

  def onboarding?
    status == "setup"
  end

  def ready_for_review?
    property_profile_ready? && property_photos_ready? && rooms_ready? && inventory_ready?
  end

  def property_profile_ready?
    name.present? &&
      city.present? &&
      country.present? &&
      address.present?
  end

  # Photos are their own setup step, so they answer for themselves. One photo is
  # enough; it is featured automatically, so there is nothing else to check.
  def property_photos_ready?
    featured_photo_attachment_id.present?
  end

  def rooms_ready?
    room_types.exists? && room_types.all? { |rt| rt.name.present? && rt.quantity.positive? }
  end

  def inventory_ready?
    setup_coverage.complete?
  end

  # Memoized because the audit walks a year of inventory per room type and the
  # readiness views ask more than once per render. Scoped to this instance, so a
  # save that changes rates gets a fresh audit on the next request.
  def setup_coverage
    @setup_coverage ||= Rates::SetupCoverage.call(hotel: self)
  end

  def tourism_tax_applicable_for?(country)
    return false unless tourism_tax_enabled?
    return false if country.blank?

    !country.casecmp("Malaysia").zero?
  end

  def tourism_tax_amount_for(country)
    tourism_tax_applicable_for?(country) ? tourism_tax_amount : 0
  end

  def transaction_configuration
    hotel_transaction_configuration || build_hotel_transaction_configuration
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
    feature_first_photo

    PhotoUploadResult.new(
      attached_count: photos_to_attach.size,
      trimmed_count: photo_files.size - photos_to_attach.size
    )
  end

  # A property with photos always has a featured one. Nobody has to think about
  # choosing the first one, and the setup step can ask for a photo rather than
  # for a photo plus a separate decision about it. Picking a different featured
  # photo later still works — this only fills a gap, it never overrides a choice.
  def feature_first_photo
    return if featured_photo_attachment_id.present?

    first_photo = photos.attachments.order(:id).first
    return if first_photo.blank?

    update_column(:featured_photo_attachment_id, first_photo.id)
  end

  def payout_batches_for_reports(start_date: nil, end_date: nil)
    payout_batches.order(period_end: :desc).period_between(start_date, end_date)
  end

  def upcoming_payout_amount(cutoff_date)
    bookings.unbatched_upcoming(cutoff_date).sum("COALESCE(net_amount, 0)")
  end

  def onboarding_completion_date
    return nil unless status == "live"
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

  def mtd_bookings
    bookings.revenue_generating.where(created_at: Time.current.all_month)
  end

  def gross_revenue_mtd
    mtd_bookings.sum(:total_amount)
  end

  def wastays_margin_mtd
    mtd_bookings.sum("COALESCE(margin_amount, 0)")
  end

  def hotel_net_earnings_mtd
    mtd_bookings.sum("COALESCE(net_amount, 0)")
  end

  def booking_count_mtd
    mtd_bookings.count
  end

  def active_setup_fee
    SetupFeeRule.active.find_by(settable: self) ||
      SetupFeeRule.active.where(settable_id: nil).find_by(settable_type: [ nil, "" ])
  end

  def setup_fee_source
    if SetupFeeRule.active.find_by(settable: self)
      "Hotel Override"
    elsif SetupFeeRule.active.where(settable_id: nil).find_by(settable_type: [ nil, "" ]).present?
      "Global Default"
    else
      "Not Configured"
    end
  end

  def booking_snapshot
    as_json(except: %i[
      ai_provider_enabled
      ai_provider_name
      ai_provider_key
      ai_concierge_tone
    ])
  end

  def latitude
    extract_coordinate("3d", /@(-?\d+\.\d+)/)
  end

  def longitude
    extract_coordinate("4d", /@(?:-?\d+\.\d+),(-?\d+\.\d+)/)
  end

  # Only ever on create. A slug that followed the hotel name would invalidate every
  # link to the property each time it was renamed; `unique_id` is the canonical param
  # now, so the slug's one remaining job is to keep old URLs alive forever.
  def should_generate_new_friendly_id?
    slug.blank?
  end


  private

  def assign_unique_id
    return if unique_id.present?

    self.unique_id = self.class.next_unique_id
  end

  def unique_id_is_immutable
    errors.add(:unique_id, "cannot be changed after the hotel is created")
  end

  def hotel_prefix_has_not_been_used_by_another_hotel
    return if hotel_prefix.blank?
    return unless HotelPrefixHistory.where(prefix: hotel_prefix).where.not(hotel_id: id).exists?

    errors.add(:hotel_prefix, "has already been used by another hotel")
  end

  def record_hotel_prefix_history
    return if hotel_prefix.blank?

    hotel_prefix_histories.where.not(prefix: hotel_prefix).where(retired_at: nil).update_all(retired_at: Time.current, updated_at: Time.current)
    history = hotel_prefix_histories.find_or_initialize_by(prefix: hotel_prefix)
    history.retired_at = nil
    history.save!
  end

  def assign_hotel_prefix
    return if hotel_prefix.present?
    self.hotel_prefix = generate_unique_prefix
  end

  def normalize_hotel_prefix
    self.hotel_prefix = nil if hotel_prefix.blank?
  end

  # Tidied, never validated for shape. SST numbers have already changed format
  # once and the state levies follow no convention at all, so a regex here would
  # only lock properties out of recording a number they legitimately hold.
  def normalize_registration_numbers
    REGISTRATION_NUMBER_ATTRIBUTES.each do |attribute|
      value = self[attribute].to_s.strip.upcase.gsub(/\s+/, " ")
      self[attribute] = value.presence
    end
  end

  PREFIX_MIN_LENGTH = 3
  PREFIX_MAX_LENGTH = 4

  def generate_unique_prefix
    base = build_prefix_base
    candidate = base
    counter = 2
    while Hotel.exists?(hotel_prefix: candidate) || HotelPrefixHistory.exists?(prefix: candidate)
      candidate = "#{base}#{counter}"
      counter += 1
    end
    candidate
  end

  def build_prefix_base
    cleaned = name.to_s.upcase.gsub(/[^A-Z\s]/, "").strip
    words = cleaned.split(/\s+/).reject(&:empty?)
    return "WAS" if words.empty?

    base =
      if words.length >= PREFIX_MIN_LENGTH
        words.map { |w| w[0] }.join.first(PREFIX_MAX_LENGTH)
      elsif words.length == 2
        first, last = words
        "#{first[0]}#{first[1] || last[1] || 'X'}#{last[0]}"
      else
        words.first.first(PREFIX_MAX_LENGTH)
      end

    base.length >= PREFIX_MIN_LENGTH ? base : base.ljust(PREFIX_MIN_LENGTH, "X")
  end

  def self.allowed_amenity_slugs
    @allowed_amenity_slugs ||= Amenity.hotel.pluck(:slug)
  end

  def amenities_must_be_from_list
    return if amenities.blank?

    allowed_ids = self.class.allowed_amenity_slugs
    invalid_amenities = amenities - allowed_ids

    if invalid_amenities.any?
      errors.add(:amenities, "contains invalid options: #{invalid_amenities.join(', ')}")
    end
  end

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

  def extract_coordinate(prefix, fallback_regex)
    return nil if google_map_link.blank?

    matches = google_map_link.scan(/!#{prefix}(-?\d+\.\d+)/).flatten
    return matches.last.to_f if matches.any?

    google_map_link[fallback_regex, 1]&.to_f
  end

  # The charging model determines the shape and meaning of every price stored
  # for the property, so it is chosen once at creation and never transitioned in
  # place — regardless of status, bookings, or channel connections. Correcting a
  # mistaken choice is a data-recovery operation, not a settings change.
  def sell_mode_is_immutable
    errors.add(:sell_mode, "cannot be changed after the hotel is created")
  end

  def ensure_current_business_date
    HotelBusinessDate.initialize_for_hotel!(hotel: self, date: business_date_for(Time.current))
  end

  def ensure_default_gl_maps
    Financials::EnsureDefaultGlMaps.call(self)
  end

  def ensure_default_transaction_codes
    Financials::EnsureDefaultTransactionCodes.call(self)
  end

  def saved_change_to_primary_tax_settings?
    saved_change_to_sst_enabled? || saved_change_to_tourism_tax_enabled?
  end

  def sync_primary_tax_transaction_codes
    Financials::EnsureDefaultTransactionCodes.call(self)
  end
end
