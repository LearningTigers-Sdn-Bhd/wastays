# frozen_string_literal: true

module Concierge
  # A guest's own reviews of Recommendations vendors, for this browser only.
  #
  # Backed by the session while reviews live externally (Dinerzflow, or
  # whatever review store this eventually points at) rather than in wastays'
  # own database -- see VendorDirectory::Review. Unlike VoucherWallet this is
  # not keyed to a booking: reviewing is open to anyone browsing the page, not
  # gated on a live stay, so there is no booking id to scope it to.
  class ReviewBook
    SESSION_KEY = "recommendation_reviews"

    def initialize(session:)
      @session = session
    end

    # A vendor's seeded (mock-fixture) reviews plus whatever this guest has
    # submitted this session, newest first.
    def for(vendor)
      (vendor.reviews + mine_for(vendor.id)).sort_by(&:posted_at).reverse
    end

    def mine_for(vendor_id)
      store.fetch(vendor_id, []).map { |entry| build_review(entry) }
    end

    def add!(vendor_id:, guest_name:, rating:, comment:)
      entry = { "guest_name" => guest_name, "rating" => rating, "comment" => comment.presence,
                "posted_at" => Time.current.iso8601 }
      store[vendor_id] = store.fetch(vendor_id, []) + [ entry ]
      persist
      build_review(entry)
    end

    private

    attr_reader :session

    def store
      @store ||= session[SESSION_KEY].presence&.dup || {}
    end

    def persist = session[SESSION_KEY] = store

    def build_review(entry)
      VendorDirectory::Review.new(
        guest_name: entry["guest_name"],
        rating: entry["rating"],
        comment: entry["comment"],
        posted_at: Time.zone.parse(entry["posted_at"].to_s) || Time.current
      )
    end
  end
end
