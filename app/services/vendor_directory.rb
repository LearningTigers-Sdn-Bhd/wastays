# frozen_string_literal: true

# The seam between the concierge recommendation UI and whoever supplies vendors
# and vouchers. Today that is a YAML fixture; once Dinerzflow ships its guest
# claim API this becomes an HTTP client and nothing above it changes.
module VendorDirectory
  class VendorNotFound < StandardError; end
  class OfferNotFound < StandardError; end

  # Every vendor in this directory is in Kota Kinabalu; "open now" and "opens
  # at" are checked against this zone regardless of the guest's own, since
  # what matters is whether the vendor's own door is open right now, not
  # what time it is on the guest's phone.
  ZONE = "Asia/Kuala_Lumpur"

  class << self
    def adapter = @adapter ||= MockAdapter.new

    attr_writer :adapter

    def categories = adapter.categories

    def category(slug) = categories.find { |category| category.slug == slug }

    # Categories a guest should see: a tab with neither vendors nor offers is
    # a dead end, so an empty category is simply not offered.
    def visible_categories
      grouped = vendors.group_by(&:category_slug)
      categories.select { |category| grouped[category.slug].present? }
    end

    def vendors = adapter.vendors

    def vendors_in(category_slug)
      vendors.select { |vendor| vendor.category_slug == category_slug }
             .sort_by { |vendor| [ vendor.offers? ? 0 : 1, vendor.distance_km.to_f ] }
    end

    def vendor(id)
      vendors.find { |vendor| vendor.id == id } or raise VendorNotFound, id
    end

    def offer(vendor_id, offer_id)
      vendor(vendor_id).offer(offer_id) or raise OfferNotFound, offer_id
    end

    # Every offer in a category, most noteworthy first. Unlike featured_in this
    # does not dedupe by vendor -- it is the source for "View all", where the
    # point is completeness, not curated variety.
    def offers_in(category_slug)
      vendors_in(category_slug)
        .flat_map(&:offers)
        .sort_by { |offer| [ offer.scarce? ? 0 : 1, offer.expiring_soon? ? 0 : 1, offer.remaining.to_i ] }
    end

    # The strip at the top of each tab: the deals worth interrupting a scroll
    # for. Scarcity first, then the ones about to expire.
    #
    # One offer per vendor -- a rail showing the same restaurant three times
    # reads as a short list rather than a wide choice, and the vendor's other
    # offers, along with everything else in the category, are one tap away
    # through "View all". The default of 4 is sized for the view, not this
    # method: mobile shows all four as two rows of two, desktop shows only
    # the first three as a single row and leaves the fourth unrendered.
    def featured_in(category_slug, limit: 4)
      offers_in(category_slug).uniq(&:vendor_id).first(limit)
    end
  end
end
