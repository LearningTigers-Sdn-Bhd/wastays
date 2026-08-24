# frozen_string_literal: true

# An outside service that wants to be told when something happens here.
#
# Two columns decide what an endpoint hears, and both read "everything" when
# left unset, because that is what every endpoint predating them was:
#
#   hotel      nil -> serves the whole platform; set -> hears that hotel only
#   event_types []  -> every event;              set -> only those named
#
# The pairing matters for anything guest-facing. A relay that carries one
# hotel's WhatsApp traffic has no business receiving another hotel's bookings,
# and until these existed there was no way to say so.
class WebhookEndpoint < ApplicationRecord
  belongs_to :hotel, optional: true

  validates :name, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validate :event_types_are_known

  after_initialize :set_defaults, if: :new_record?

  scope :enabled, -> { where(enabled: true) }

  # Everything worth announcing, so the admin form can offer a list rather than
  # a free-text box that silently matches nothing when it is misspelled.
  EVENT_TYPES = %w[
    booking_confirmed
    booking_cancelled
    booking_updated
    booking_checked_in
    booking_completed
    housekeeping_completed
    complaint_resolved
    checkout_completed
    check_in_confirmation
    pre_arrival_notification
    check_out_receipt_message
    post_stay_review_request
    in_stay_guest_messaging
    concierge_staff_reply
  ].freeze

  # Who should actually receive one event about one hotel.
  #
  # A broadcast that does not name a hotel reaches only the platform-wide
  # endpoints: not knowing whose event this is is not a reason to hand it to
  # somebody's private relay.
  def self.listening_for(event_type, hotel_id: nil)
    enabled
      .where(hotel_id: [ nil, hotel_id ].uniq)
      .where("cardinality(event_types) = 0 OR event_types @> ARRAY[?]::text[]", event_type.to_s)
  end

  def platform_wide? = hotel_id.nil?
  def all_events? = event_types.empty?

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end

  def event_types_are_known
    unknown = Array(event_types).map(&:to_s) - EVENT_TYPES
    errors.add(:event_types, "contains unknown events: #{unknown.join(", ")}") if unknown.any?
  end
end
