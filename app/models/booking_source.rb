# frozen_string_literal: true

class BookingSource < ApplicationRecord
  KINDS = %w[manual ota other_channel system].freeze
  KIND_LABELS = {
    "manual" => "Manual / Direct",
    "ota" => "Online Travel Agency",
    "other_channel" => "Other Channel",
    "system" => "System (hidden from dropdowns)"
  }.freeze
  ALLOWED_LOGO_TYPES = %w[image/png image/jpeg image/webp image/svg+xml].freeze
  CACHE_KEY = "booking_sources/registry/v1"
  ICONS_PATH = Rails.root.join("app/assets/svg/icons/lucide/outline")

  DEFAULT_SOURCES = [
    { key: "internal", label: "Internal", kind: "manual", icon: "building-2", position: 0 },
    { key: "walk_in", label: "Walk-in", kind: "manual", icon: "user", position: 1 },
    { key: "phone", label: "Phone", kind: "manual", icon: "phone", position: 2 },
    { key: "email", label: "Email", kind: "manual", icon: "mail", position: 3 },
    { key: "whatsapp", label: "WhatsApp", kind: "manual", icon: "message-circle", position: 4 },

    { key: "booking_com", label: "Booking.com", kind: "ota", icon: "globe", badge_color: "#003580", badge_text_color: "#FFFFFF", badge_initial: "B", position: 0 },
    { key: "agoda", label: "Agoda", kind: "ota", icon: "globe", badge_color: "#5392F9", badge_text_color: "#FFFFFF", badge_initial: "A", position: 1 },
    { key: "expedia", label: "Expedia", kind: "ota", icon: "globe", badge_color: "#FFC72C", badge_text_color: "#111827", badge_initial: "E", position: 2 },
    { key: "traveloka", label: "Traveloka", kind: "ota", icon: "globe", badge_color: "#37A9E1", badge_text_color: "#FFFFFF", badge_initial: "T", position: 3 },
    { key: "airbnb", label: "Airbnb", kind: "ota", icon: "globe", badge_color: "#FF5A5F", badge_text_color: "#FFFFFF", badge_initial: "A", position: 4 },

    { key: "channel_manager", label: "Channel Manager", kind: "other_channel", icon: "globe", position: 0 },

    { key: "staff", label: "Staff", kind: "system", icon: "building-2", position: 0 },
    { key: "direct", label: "Direct", kind: "system", icon: "building-2", position: 1 },
    { key: "manual_at_hotel", label: "Manual at Hotel", kind: "system", icon: "building-2", position: 2 },
    { key: "channex", label: "Channel Manager", kind: "system", icon: "globe", position: 3 },
    { key: "ota", label: "Other OTA", kind: "system", icon: "globe", position: 4 }
  ].freeze

  has_one_attached :logo
  has_many :booking_billing_parties, dependent: :restrict_with_error
  has_many :channel_settlements, dependent: :restrict_with_error
  has_many :channel_settlement_receipts, dependent: :restrict_with_error

  before_validation :normalize_key
  before_validation :normalize_colors

  validates :key, presence: true, uniqueness: true
  validates :label, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :badge_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a hex color like #003580" }, allow_blank: true
  validates :badge_text_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/, message: "must be a hex color like #FFFFFF" }, allow_blank: true
  validates :badge_initial, length: { maximum: 2 }, allow_blank: true
  validates :icon, inclusion: { in: ->(_) { available_icon_names }, message: "must be a valid Lucide icon name (see lucide.dev/icons)" }, allow_blank: true
  validate :logo_is_an_image

  scope :ordered, -> { order(:kind, :position, :label) }

  after_commit :bust_registry_cache

  def self.normalize(source)
    source.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  # All sources (active and inactive), keyed by normalized `key`, for display lookups
  # (a historical booking must keep rendering correctly even after its source is deactivated).
  #
  # Memoized per-process on top of Rails.cache: this is looked up once per booking
  # row on hot render paths (Stay View board, front desk lists), and even a cache
  # hit still costs a round trip to the cache backend (a real query against
  # solid_cache_entries in production, and no caching at all in test's :null_store)
  # — so without this, query/lookup count would scale with row count instead of
  # staying flat. reset_registry_cache! clears both layers on every write.
  def self.registry
    @registry ||= Rails.cache.fetch(CACHE_KEY) do
      includes(logo_attachment: :blob).ordered.index_by(&:key)
    end
  end

  def self.find_by_source(source)
    registry[normalize(source)]
  end

  def self.options_for(kind)
    registry.values.select { |record| record.kind == kind && record.active? }.map { |record| [ record.label, record.key ] }
  end

  def self.manual_options = options_for("manual")
  def self.ota_options = options_for("ota")
  def self.other_channel_options = options_for("other_channel")

  def self.seed_defaults!
    DEFAULT_SOURCES.each do |attrs|
      record = find_or_initialize_by(key: attrs.fetch(:key))
      record.assign_attributes(attrs)
      record.save!
    end
  end

  def self.kind_label(kind)
    KIND_LABELS.fetch(kind.to_s, kind.to_s.humanize)
  end

  # Valid Lucide icon names vendored on disk by the rails_icons gem, for the
  # admin form's <datalist> reference (there are ~1,700, no built-in picker UI).
  def self.available_icon_names
    @available_icon_names ||= Dir.glob(ICONS_PATH.join("*.svg")).map { |path| File.basename(path, ".svg") }.sort
  end

  def self.next_position_for(kind)
    where(kind: kind).maximum(:position).to_i + 1
  end

  # Public so callers that mutate a record outside the normal save path (e.g.
  # purging the logo attachment, which has no effect on the parent record's
  # own columns and therefore may not trigger its after_commit callback) can
  # invalidate the cached registry explicitly.
  def self.reset_registry_cache!
    @registry = nil
    Rails.cache.delete(CACHE_KEY)
  end

  # Purges the logo and immediately busts the registry cache — purging alone
  # does not touch this record's own columns, so it won't reliably trigger
  # the after_commit callback below (especially if no other attribute changed
  # in the same request).
  def remove_logo!
    logo.purge
    self.class.reset_registry_cache!
  end

  private

  def normalize_key
    self.key = self.class.normalize(key)
  end

  def normalize_colors
    self.badge_color = badge_color.presence&.strip&.upcase
    self.badge_text_color = badge_text_color.presence&.strip&.upcase
  end

  def logo_is_an_image
    return unless logo.attached?
    return if logo.content_type.in?(ALLOWED_LOGO_TYPES)

    errors.add(:logo, "must be a PNG, JPEG, WEBP, or SVG image")
  end

  def bust_registry_cache
    self.class.reset_registry_cache!
  end
end
