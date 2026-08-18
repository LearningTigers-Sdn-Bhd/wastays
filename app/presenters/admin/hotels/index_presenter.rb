# frozen_string_literal: true

module Admin
  module Hotels
    class IndexPresenter
      Row = Data.define(
        :hotel,
        :name,
        :unique_id,
        :city,
        :status_label,
        :status_variant,
        :status_detail,
        :payout_reports_label,
        :payout_reports_variant,
        :registered_on,
        :onboarding_period,
        :onboarding_period_dates,
        :next_session_at,
        :next_session_trainer,
        :remaining_session_count,
        :review_path
      )

      STATUS_PRESENTATION = {
        "setup" => [ "Setup", :neutral, "Waiting for the owner to complete onboarding." ],
        "pending_review" => [ "Pending review", :warning, "Waiting for an administrator to approve this hotel." ],
        "ready_to_launch" => [ "Ready to launch", :success, "Approved and waiting for the owner to keep or clear training activity." ],
        "live" => [ "Active", :success, "Available for hotel operations and public booking." ],
        "suspended" => [ "Suspended", :destructive, "Hotel and account access are currently disabled." ]
      }.freeze

      STATUS_TABS = [
        [ "all", "All", "hotel", :total ],
        [ "setup", "Setup", "settings-2", :setup ],
        [ "pending_review", "Pending review", "clock", :pending_review ],
        [ "ready_to_launch", "Ready to launch", "rocket", :ready_to_launch ],
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

      def onboarding_queue? = active_status.in?(%w[pending_review ready_to_launch])
      def ready_to_launch? = active_status == "ready_to_launch"

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
          onboarding_details = onboarding_queue? ? onboarding_details_for(hotel) : {}

          Row.new(
            hotel: hotel,
            name: hotel.name,
            unique_id: hotel.unique_id,
            city: hotel.city.presence || "City not set",
            status_label: status_label,
            status_variant: status_variant,
            status_detail: status_detail,
            payout_reports_label: hotel.hide_payout_reports? ? "Hidden" : "Visible",
            payout_reports_variant: hotel.hide_payout_reports? ? :neutral : :success,
            registered_on: hotel.created_at.strftime("%d %b %Y"),
            onboarding_period: onboarding_details[:period],
            onboarding_period_dates: onboarding_details[:period_dates],
            next_session_at: onboarding_details[:next_session_at],
            next_session_trainer: onboarding_details[:next_session_trainer],
            remaining_session_count: onboarding_details[:remaining_session_count],
            review_path: onboarding_details[:review_path]
          )
        end
      end

      def any_rows? = rows.any?

      private

      attr_reader :summary

      def onboarding_details_for(hotel)
        start_date = hotel.onboarding_start_date
        end_date = hotel.onboarding_end_date
        scheduled_sessions = hotel.onboarding_sessions
                                  .select { |session| session.status == "scheduled" }
                                  .sort_by { |session| [ session.scheduled_at, session.created_at ] }
        next_session = scheduled_sessions.first

        {
          period: period_label(start_date, end_date),
          period_dates: "#{start_date.strftime('%d %b %Y')} – #{end_date.strftime('%d %b %Y')}",
          next_session_at: next_session && I18n.l(next_session.scheduled_at, format: "%d %b %Y, %I:%M %p"),
          next_session_trainer: next_session&.trainer_name,
          remaining_session_count: [ scheduled_sessions.size - 1, 0 ].max,
          review_path: Rails.application.routes.url_helpers.onboarding_admin_hotel_path(hotel)
        }
      end

      def period_label(start_date, end_date)
        days = (end_date - start_date).to_i
        return "< 1 day" if days.zero?

        "#{days} #{'day'.pluralize(days)}"
      end
    end
  end
end
