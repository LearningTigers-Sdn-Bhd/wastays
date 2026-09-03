# frozen_string_literal: true

module Guests
  module MagicLinks
    class Issue
      SOURCES = %w[guest_portal concierge].freeze

      Result = Struct.new(:success?, :error_code, :masked_email, :retry_after, keyword_init: true)

      def initialize(guest:, source:, now: Time.current)
        @guest = guest
        @source = source.to_s
        @now = now
      end

      def call
        return failure(:guest_unavailable) unless guest
        return failure(:email_unavailable) if email.blank?
        raise ArgumentError, "Unknown magic-link source: #{source}" unless source.in?(SOURCES)

        guest.with_lock do
          return failure(:cooldown, retry_after: retry_after) if guest.magic_link_on_cooldown?(now: now)

          issue
        end
      end

      private

      attr_reader :guest, :source, :now

      def email = guest&.email.to_s.strip.downcase.presence

      def issue
        token = guest.generate_magic_token!(now: now)
        queued_job = GuestMailer.magic_link(guest, token).deliver_later
        unless queued_job != false && (!queued_job.respond_to?(:successfully_enqueued?) || queued_job.successfully_enqueued?)
          raise ActiveJob::EnqueueError, "Guest magic-link job was not enqueued"
        end

        Rails.logger.info("Guest magic link issued guest_id=#{guest.id} source=#{source}")
        success
      rescue StandardError => e
        guest.update_columns(magic_token_digest: nil, magic_token_expires_at: nil, updated_at: now)
        Rails.logger.warn("Guest magic link enqueue failed guest_id=#{guest.id} source=#{source} error=#{e.class}")
        failure(:delivery_unavailable)
      end

      def retry_after
        return unless guest.magic_token_expires_at

        guest.magic_token_expires_at - Guest::MAGIC_LINK_EXPIRY + Guest::RESEND_COOLDOWN
      end

      def success
        Result.new(success?: true, masked_email: masked_email)
      end

      def failure(error_code, retry_after: nil)
        Result.new(success?: false, error_code: error_code, masked_email: masked_email, retry_after: retry_after)
      end

      def masked_email
        local, domain = email.to_s.split("@", 2)
        return if local.blank? || domain.blank?

        "#{local.first}#{'•' * [ local.length - 1, 3 ].min}@#{domain}"
      end
    end
  end
end
