# frozen_string_literal: true

module Concierge
  # A guest's claimed vouchers for one booking.
  #
  # Backed by the session while the Dinerzflow claim API is being built. The
  # public surface -- claim!, claimed?, entries -- is what a database-backed
  # VoucherClaim ledger will expose, so callers survive the swap. Nothing here
  # is authoritative: real issuance, redemption caps and the redeem ledger all
  # belong to Dinerzflow.
  class VoucherWallet
    SESSION_KEY = "recommendation_claims"

    Entry = Data.define(:vendor_id, :offer_id, :code, :claimed_at) do
      def vendor = VendorDirectory.vendor(vendor_id)

      def offer = VendorDirectory.offer(vendor_id, offer_id)
    end

    def initialize(session:, booking:)
      @session = session
      @booking = booking
    end

    def claimed?(offer) = store.key?(key_for(offer))

    def find(offer) = build_entry(key_for(offer), store[key_for(offer)])

    def claim!(offer)
      return find(offer) if claimed?(offer)

      store[key_for(offer)] = { "code" => generate_code(offer), "claimed_at" => Time.current.iso8601 }
      persist
      find(offer)
    end

    # Newest first: a guest opening the wallet is nearly always looking for the
    # thing they just claimed.
    def entries
      store.filter_map { |key, value| build_entry(key, value) }
           .sort_by(&:claimed_at)
           .reverse
    end

    def any? = entries.any?

    def size = entries.size

    private

    attr_reader :session, :booking

    def store
      @store ||= session[SESSION_KEY].presence&.dup || {}
    end

    def persist = session[SESSION_KEY] = store

    def key_for(offer) = "#{booking.id}:#{offer.vendor_id}:#{offer.id}"

    def build_entry(key, value)
      return if value.blank?

      _booking_id, vendor_id, offer_id = key.split(":")
      Entry.new(
        vendor_id: vendor_id,
        offer_id: offer_id,
        code: value["code"],
        claimed_at: Time.zone.parse(value["claimed_at"].to_s) || Time.current
      )
    rescue VendorDirectory::VendorNotFound, VendorDirectory::OfferNotFound
      nil # The fixture changed under a live session; drop the orphan quietly.
    end

    # Shaped like Dinerzflow's customer_voucher.code so the QR and the printed
    # fallback look right in review.
    def generate_code(offer)
      prefix = offer.vendor_id.delete("-").upcase.first(4)
      "WS-#{prefix}-#{SecureRandom.alphanumeric(6).upcase}"
    end
  end
end
