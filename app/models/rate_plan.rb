class RatePlan < ApplicationRecord
  include HotelScopable

  has_many :room_type_rate_plans, dependent: :destroy
  has_many :room_types, through: :room_type_rate_plans
  has_many :room_rates, dependent: :destroy
  has_many :channel_room_rates, dependent: :destroy
  has_many :booking_rooms, dependent: :restrict_with_error
  has_many :rate_plan_age_bands, -> { order(:position, :min_age) }, dependent: :destroy
  has_one :channel_mapping, as: :mappable, dependent: :destroy
  has_many :rate_plan_agency_rules, dependent: :destroy
  has_many :rate_plan_stay_discounts, -> { order(:min_nights) }, dependent: :destroy, inverse_of: :rate_plan
  has_many :agency_rule_accounts, through: :rate_plan_agency_rules, source: :hotel_corporate_account

  accepts_nested_attributes_for :rate_plan_age_bands, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :rate_plan_stay_discounts, allow_destroy: true,
    reject_if: ->(attributes) { attributes.slice("min_nights", "value").values.all?(&:blank?) }

  KINDS = %w[standard walk_in corporate ota custom].freeze

  # Who may be sold each kind. Walk-in is front-desk only; corporate needs a
  # negotiated relationship; ota is distribution-only and sold by nobody here.
  # Every caller that filters plans by audience reads this rather than spelling
  # the list out — they drifted apart the last time they were written by hand.
  AUDIENCE_KINDS = {
    public: %w[standard custom],
    corporate: %w[standard custom corporate],
    staff: %w[standard custom walk_in corporate]
  }.freeze

  # Kinds a channel manager may carry. Not an audience: ota exists only to be
  # distributed, and walk-in/corporate must never leave the property.
  DISTRIBUTABLE_KINDS = %w[standard custom ota].freeze

  # Kinds that carry their own price but read restrictions off the category's
  # standard plan — stop-sell and CTA/CTD are properties of the night, not of
  # which desk sold it.
  ANCHORED_KINDS = %w[walk_in corporate].freeze

  # Which travel agencies see this plan in the corporate portal. Agencies are
  # named in rate_plan_agency_rules: excluded under "except", admitted under
  # "only". Only kinds the corporate audience may be sold are ever offered.
  TA_ACCESS = %w[hidden all except only].freeze
  TA_ACCESS_LABELS = {
    "hidden" => "Hidden from travel agents",
    "all" => "All travel agents",
    "except" => "All travel agents except…",
    "only" => "Only selected travel agents"
  }.freeze

  # Which market of travel agent a plan is for. "all" offers it to any agent the
  # access rule above admits; "local" or "international" offers it only to agents
  # the hotel has marked that way, so a local agent never sees an international
  # rate (and an agent with no market set sees only "all" plans).
  TA_MARKETS = %w[all local international].freeze
  TA_MARKET_LABELS = {
    "all" => "Local and international agents",
    "local" => "Local agents only",
    "international" => "International agents only"
  }.freeze

  validates :name, presence: true
  validates :ta_market, inclusion: { in: TA_MARKETS }
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :ta_access, inclusion: { in: TA_ACCESS }
  validate :agency_accounts_fit_access
  validates :sell_mode, presence: true, inclusion: { in: %w[per_room per_person] }
  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :single_supplement, numericality: { greater_than_or_equal_to: 0 }
  validates :child_price_multiplier, numericality: { greater_than_or_equal_to: 0 }
  validates :base_occupancy, numericality: { only_integer: true, greater_than: 0 }
  validates :extra_pax_charge, numericality: { greater_than_or_equal_to: 0 }
  validates :channex_children_fee, :channex_infant_fee,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :normalize_currency
  before_validation :inherit_sell_mode_from_hotel

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :for_audience, lambda { |audience|
    scope = active.where(kind: RatePlan.kinds_for(audience))
    audience.to_sym == :public ? scope.where(hidden_from_public: false) : scope
  }

  # The plans one agency may book, as a relation so callers can keep chaining.
  # "All except" is a list of agencies to leave out, so it only ever offers to
  # an agency it can check against that list -- with none, only "all" answers.
  scope :offered_to_agency, lambda { |relationship|
    # Only plans for the agent's market -- or for every market -- however the
    # access rule below admits them.
    markets = [ "all", relationship&.market ].compact
    in_market = where(ta_market: markets)
    open_to_all = in_market.for_audience(:corporate).where(ta_access: "all")
    next open_to_all if relationship.nil?

    named = RatePlanAgencyRule.where(hotel_corporate_account_id: relationship.id)
      .where(RatePlanAgencyRule.arel_table[:rate_plan_id].eq(arel_table[:id]))
      .arel.exists
    open_to_all
      .or(in_market.for_audience(:corporate).where(ta_access: "except").where.not(named))
      .or(in_market.for_audience(:corporate).where(ta_access: "only").where(named))
  }

  after_save :sync_agency_rules, if: -> { @agency_account_ids }
  after_commit :sync_with_channel_manager, on: [ :create, :update ]
  after_destroy_commit :delete_from_channel_manager, if: :synced_with_channel_manager?

  def self.sell_modes
    %w[per_room per_person]
  end

  def self.kinds_for(audience)
    AUDIENCE_KINDS.fetch(audience.to_sym)
  end

  def standard_rate?
    kind == "standard"
  end

  # Only a hotelier-created plan is deletable; every other kind is structural.
  def deletable?
    kind == "custom" && !booking_rooms.exists?
  end

  def anchored?
    kind.in?(ANCHORED_KINDS)
  end

  def bookable_by?(audience)
    return false if archived?
    return false unless kind.in?(self.class.kinds_for(audience))
    return false if audience.to_sym == :public && hidden_from_public?

    true
  end

  # The agencies a TA access rule names, as the editor submits them. Written
  # to rate_plan_agency_rules after save, and dropped when the access mode
  # names no one.
  def agency_account_ids
    @agency_account_ids || rate_plan_agency_rules.map(&:hotel_corporate_account_id)
  end

  def agency_account_ids=(ids)
    @agency_account_ids = Array(ids).compact_blank.map(&:to_i).uniq
  end

  # Plans made by the system keep their kind after a rename, so the name alone
  # doesn't say who can book them. Standard and custom are self-evident.
  KIND_LABELS = {
    "walk_in" => "Walk-in",
    "corporate" => "Corporate",
    "ota" => "OTA"
  }.freeze

  KIND_HINTS = {
    "walk_in" => "Walk-in plan: sold by front desk only.",
    "corporate" => "Corporate plan: sold to corporate accounts and front desk.",
    "ota" => "OTA plan: only sent to your channel manager."
  }.freeze

  def kind_label
    KIND_LABELS[kind]
  end

  def kind_hint
    KIND_HINTS[kind]
  end

  def ta_access_label
    TA_ACCESS_LABELS.fetch(ta_access)
  end

  def ta_market_label = TA_MARKET_LABELS.fetch(ta_market)

  # Whether this plan is meant for the agent's market (or for all of them).
  def in_market_for?(relationship)
    ta_market == "all" || (relationship&.market.present? && ta_market == relationship.market)
  end

  def agency_rules?
    ta_access.in?(%w[except only])
  end

  # Mirrors .offered_to_agency for a plan already in hand.
  def offered_to_agency?(relationship)
    return false unless bookable_by?(:corporate)
    return false unless in_market_for?(relationship)

    case ta_access
    when "all" then true
    when "except" then relationship.present? && !agency_named?(relationship)
    when "only" then agency_named?(relationship)
    else false
    end
  end

  def archived?
    archived_at.present?
  end

  # Walk-in and Corporate can be archived — nothing else reads their rows. The
  # Standard plan cannot: it is the price anchor every other plan resolves
  # against, the restriction row walk-in/corporate read, and the only plan the
  # booking paths fall back to. Archiving it leaves the room category unsellable.
  def archivable?
    !standard_rate?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def age_banded?
    sell_mode == "per_person" && rate_plan_age_bands.any?
  end

  def channex_capability(room_type: nil)
    ChannelManagers::ChannexRatePlanCapability.call(rate_plan: self, room_type: room_type)
  end

  def channex_syncable?(room_type: nil)
    channex_capability(room_type: room_type).supported?
  end

  def band_for_age(age)
    rate_plan_age_bands.find { |band| age.to_i.between?(band.min_age, band.max_age) }
  end

  private

  def agency_accounts_fit_access
    return if @agency_account_ids.nil?

    if ta_access == "only" && @agency_account_ids.empty?
      errors.add(:agency_account_ids, "must name at least one travel agent")
    elsif agency_rules? && hotel && hotel.hotel_corporate_accounts.where(id: @agency_account_ids).count != @agency_account_ids.size
      errors.add(:agency_account_ids, "must belong to this property")
    end
  end

  def sync_agency_rules
    wanted = agency_rules? ? @agency_account_ids : []
    rate_plan_agency_rules.where.not(hotel_corporate_account_id: wanted).destroy_all
    (wanted - rate_plan_agency_rules.pluck(:hotel_corporate_account_id)).each do |account_id|
      rate_plan_agency_rules.create!(hotel_corporate_account_id: account_id)
    end
    rate_plan_agency_rules.reset
    @agency_account_ids = nil
  end

  def agency_named?(relationship)
    return false if relationship.blank?

    if association(:rate_plan_agency_rules).loaded?
      rate_plan_agency_rules.any? { |rule| rule.hotel_corporate_account_id == relationship.id }
    else
      rate_plan_agency_rules.exists?(hotel_corporate_account_id: relationship.id)
    end
  end

  def normalize_currency
    self.currency = CurrencyCatalog.normalize(currency)
  end

  # The hotel decides how it sells; a rate plan only decides how much. Nothing
  # writes sell_mode directly any more — not the rate plan sheet, not the
  # callers that create Standard plans — so this is the single point where the
  # value is set, on create and on every update.
  def inherit_sell_mode_from_hotel
    self.sell_mode = hotel.sell_mode if hotel
  end

  def sync_with_channel_manager
    return if Thread.current[:skip_ari_sync]
    return if hotel.preferred_channel_manager.blank?
    room_ids = room_type_rate_plans.pluck(:room_type_id)
    return if room_ids.empty?

    ChannelManagers::SyncRatePlanAri.call(rate_plan: self, room_type_ids: room_ids)
  end

  def delete_from_channel_manager
    ChannelManagers::SyncStructureJob.perform_later(self.class.name, nil, "delete", hotel_id: hotel_id, external_id: channel_mapping.external_id)
  end

  def synced_with_channel_manager?
    hotel.preferred_channel_manager.present? && channel_mapping.present? && !channel_mapping.external_id.to_s.start_with?("pending")
  end
end
