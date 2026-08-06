# frozen_string_literal: true

module FinancialControls
  class PostingGuard
    include Authorizable

    class PostingBlocked < StandardError; end
    class OverrideReasonRequired < PostingBlocked; end
    class PermissionRequired < PostingBlocked; end

    OVERRIDE_PERMISSION = "override_financial_date_lock".freeze
    AUDIT_SOURCES = %w[night_audit no_show].freeze
    SYSTEM_SOURCES = %w[sync automated_task].freeze
    BLOCKER_RESOLUTION_SOURCE = "audit_blocker_resolution".freeze

    def self.call!(**kwargs)
      new(**kwargs).call!
    end

    def initialize(hotel:, business_date:, actor:, posting_source:, override: false, override_reason: nil, permission_context: nil, blocker_resolution: nil, system_posting: false)
      @hotel = hotel
      @business_date = business_date.to_date
      @actor = actor
      @posting_source = posting_source.to_s
      @override = override
      @override_reason = override_reason.to_s.strip
      @permission_context = permission_context || actor
      @blocker_resolution = blocker_resolution || {}
      @system_posting = system_posting
    end

    def call!
      record = business_date_record
      raise PostingBlocked, "The business date #{@business_date} has no accounting control record." unless record

      case record.status
      when "open"
        require_authoritative_current!(record)
        true
      when "audit_running"
        require_authoritative_current!(record)
        return true if audit_owned_posting?

        raise PostingBlocked, "The business date #{@business_date} is currently in night audit. Only night audit postings are allowed."
      when "audit_blocked"
        require_authoritative_current!(record)
        return true if valid_blocker_resolution?

        raise PostingBlocked, "The business date #{@business_date} is blocked by night audit. Only audit blocker-resolution postings are allowed."
      when "closed", "force_closed"
        validate_override!
      else
        raise PostingBlocked, "The business date #{@business_date} is not open for financial posting."
      end
    end

    private

    def business_date_record
      @business_date_record ||= HotelBusinessDate.find_by(hotel: @hotel, business_date: @business_date)
    end

    def require_authoritative_current!(record)
      return if @hotel.current_business_date_record&.id == record.id

      raise PostingBlocked, "The business date #{@business_date} is not the hotel's current accounting business date."
    end

    def audit_owned_posting?
      AUDIT_SOURCES.include?(@posting_source)
    end

    def valid_blocker_resolution?
      return false unless @posting_source == BLOCKER_RESOLUTION_SOURCE
      return false if @override_reason.blank?

      @blocker_resolution[:night_audit_id].present? && @blocker_resolution[:blocker_type].present?
    end

    def validate_override!
      unless @override
        msg = if business_date_record.force_closed?
                "The business date #{@business_date} has been force-closed. Please provide an override flag to post to a force-closed date."
        else
                "The business date #{@business_date} is already closed. Please provide an override flag to post to a closed date."
        end
        raise PostingBlocked, msg
      end

      raise OverrideReasonRequired, "Override reason can't be blank." if @override_reason.blank?
      raise PermissionRequired, "Override postings require the #{OVERRIDE_PERMISSION} permission." unless override_permission?

      true
    end

    def override_permission?
      return true if system_override?

      actor_permits?(@permission_context, OVERRIDE_PERMISSION, hotel: @hotel)
    end

    def system_override?
      @system_posting || (@actor.blank? && (AUDIT_SOURCES.include?(@posting_source) || SYSTEM_SOURCES.include?(@posting_source)))
    end
  end
end
