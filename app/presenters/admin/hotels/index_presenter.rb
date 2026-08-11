# frozen_string_literal: true

module Admin
  module Hotels
    class IndexPresenter
      Row = Data.define(:hotel, :name, :city, :status_label, :status_variant, :status_detail, :registered_on)

      STATUS_PRESENTATION = {
        "registered" => [ "Setup", :neutral, "Complete the hotel profile." ],
        "email_verified" => [ "Setup", :neutral, "Complete the hotel profile." ],
        "profile_incomplete" => [ "Setup", :neutral, "Complete the property policies." ],
        "rooms_incomplete" => [ "Setup", :neutral, "Add the hotel's room types." ],
        "inventory_incomplete" => [ "Setup", :neutral, "Add rates and inventory, then submit for review." ],
        "pending_review" => [ "Pending review", :warning, "Waiting for an administrator to approve this hotel." ],
        "approved" => [ "Active", :success, "Available for hotel operations and public booking." ],
        "live" => [ "Active", :success, "Available for hotel operations and public booking." ],
        "suspended" => [ "Suspended", :destructive, "Hotel and account access are currently disabled." ]
      }.freeze

      STATUS_TABS = [
        [ "all", "All", "hotel", :total ],
        [ "setup", "Setup", "settings-2", :setup ],
        [ "pending_review", "Pending review", "clock", :pending_review ],
        [ "active", "Active", "circle-check", :active ],
        [ "suspended", "Suspended", "circle-pause", :suspended ]
      ].freeze
      PAGE_SIZES = [ 15, 25, 50, 100 ].freeze
      DEFAULT_PAGE_SIZE = 15

      attr_reader :hotels, :page_size

      def self.normalize_page_size(value)
        requested = value.to_i
        PAGE_SIZES.include?(requested) ? requested : DEFAULT_PAGE_SIZE
      end

      def initialize(hotels:, summary:, status: nil, page_size: DEFAULT_PAGE_SIZE)
        @hotels = hotels
        @summary = summary
        @status = status
        @page_size = page_size
      end

      def active_status
        @status.presence_in(HotelsQuery::STATUS_FILTERS.keys) || "all"
      end

      def status_tabs
        STATUS_TABS.map do |name, label, icon, count_key|
          { name: name, label: label, icon: icon, count: summary.fetch(count_key) }
        end
      end

      def page_size_choices
        PAGE_SIZES.map { |size| { label: size.to_s, value: size } }
      end

      def default_page_size? = page_size == DEFAULT_PAGE_SIZE

      def rows
        @rows ||= hotels.map do |hotel|
          status_label, status_variant, status_detail = STATUS_PRESENTATION.fetch(hotel.status)

          Row.new(
            hotel: hotel,
            name: hotel.name,
            city: hotel.city.presence || "City not set",
            status_label: status_label,
            status_variant: status_variant,
            status_detail: status_detail,
            registered_on: hotel.created_at.strftime("%d %b %Y")
          )
        end
      end

      def any_rows? = rows.any?

      private

      attr_reader :summary
    end
  end
end
