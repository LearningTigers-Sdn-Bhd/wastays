# frozen_string_literal: true

module VendorDirectory
  # Reads the checked-in fixture in config/vendor_directory/mock.yml and hands
  # back the same value objects the real Dinerzflow client will return, so the
  # concierge UI can be built and reviewed before that backend exists.
  class MockAdapter
    FIXTURE_PATH = Rails.root.join("config", "vendor_directory", "mock.yml")

    def categories
      data.fetch(:categories).map do |attributes|
        Category.new(**attributes.slice(:slug, :name, :tagline, :icon))
      end
    end

    def vendors
      data.fetch(:vendors).map { |attributes| build_vendor(attributes) }
    end

    private

    def build_vendor(attributes)
      Vendor.new(
        id: attributes[:id],
        category_slug: attributes[:category],
        name: attributes[:name],
        tagline: attributes[:tagline],
        accent: attributes[:accent],
        price_range: attributes[:price_range],
        tags: Array(attributes[:tags]),
        summary: attributes[:summary].to_s.strip,
        address: attributes[:address],
        phone: attributes[:phone].presence,
        distance_km: attributes[:distance_km],
        walking_minutes: attributes[:walking_minutes],
        hours: Array(attributes[:hours]).map { |h| OpeningHours.new(**h.slice(:days, :opens, :closes)) },
        google_maps_url: attributes[:google_maps_url],
        latitude: attributes[:latitude],
        longitude: attributes[:longitude],
        offers: build_offers(attributes),
        photo_url: attributes[:photo_url].presence || placeholder_photo_url(attributes[:id])
      )
    end

    # Temporary: real vendor photography comes from Dinerzflow once that side
    # exists. Picsum Photos serves real, royalty-free stock photographs and
    # returns the same image for the same seed every time, so a vendor's
    # placeholder stays stable across requests without us hosting anything.
    def placeholder_photo_url(seed)
      "https://picsum.photos/seed/#{seed}/800/600"
    end

    def build_offers(vendor_attributes)
      Array(vendor_attributes[:offers]).map do |attributes|
        Offer.new(
          id: attributes[:id],
          vendor_id: vendor_attributes[:id],
          title: attributes[:title],
          subtitle: attributes[:subtitle],
          kind: attributes[:kind],
          value_label: attributes[:value_label],
          terms: Array(attributes[:terms]),
          valid_until: attributes[:valid_until].to_s.presence,
          per_guest_limit: attributes[:per_guest_limit],
          remaining: attributes[:remaining]
        )
      end
    end

    # Parsed once per boot in production, re-read on every call in development
    # so editing the fixture does not need a server restart.
    def data
      if Rails.env.local?
        load_fixture
      else
        self.class.cached_data
      end
    end

    def self.cached_data
      @cached_data ||= new.send(:load_fixture)
    end

    def load_fixture
      YAML.safe_load_file(FIXTURE_PATH, permitted_classes: [ Date ], symbolize_names: true)
    end
  end
end
